import CloudKit
import CryptoKit
import Foundation
import Security

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    var token: String { base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "") }
    init?(token: String) {
        guard token.utf8.count == 43 else { return nil }
        self.init(base64Encoded: token.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+") + "=")
        guard count == 32, self.token == token else { return nil }
    }
}

struct FriendInvite: Identifiable, Codable {
    let seed: Data
    let senderKey: Data
    var id: String { slot(sender: true) }
    var url: URL { URL(string: "dots://circle/" + seed.token + "/" + senderKey.token)! }
    init(seed: Data, senderKey: Data) { self.seed = seed; self.senderKey = senderKey }
    init?(url: URL) {
        let parts = url.path.split(separator: "/")
        guard url.scheme == "dots", url.host == "circle", parts.count == 2,
              let seed = Data(token: String(parts[0])), let key = Data(token: String(parts[1])) else { return nil }
        self.init(seed: seed, senderKey: key)
    }
    func slot(sender: Bool) -> String {
        let label = sender ? "dotlings/inviter/1" : "dotlings/guest/1"
        return Data(HMAC<SHA256>.authenticationCode(for: Data(label.utf8), using: SymmetricKey(data: seed))).hex
    }
    var previewKey: SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: seed), info: Data("dotlings/invite-preview/1".utf8), outputByteCount: 32)
    }
}

enum LinkError: LocalizedError {
    case unavailable, denied, keychain, selfInvite, signIn
    var errorDescription: String? {
        switch self {
        case .unavailable: "Dotlings couldn’t reach iCloud. Check your connection and try again."
        case .denied: "This invitation has expired, was already used, or was turned off. Ask your friend for a new link."
        case .keychain: "Unlock your iPhone and try again so Dotlings can access your circle."
        case .selfInvite: "This is your invitation. Send it to the friend you want to invite."
        case .signIn: "Sign in to iCloud in iPhone Settings to connect with friends."
        }
    }
}

struct CircleRoute: Codable {
    let invite: FriendInvite
    let sender: Bool
    let secret: Data
    var privateKey: Curve25519.KeyAgreement.PrivateKey { get throws { try .init(rawRepresentation: secret) } }
    var own: String { invite.slot(sender: sender) }
    var peer: String { invite.slot(sender: !sender) }
    func pairKey(_ peerKey: Data) throws -> SymmetricKey {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: peerKey))
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: invite.seed,
                                              sharedInfo: Data("dotlings/mutual-moods/1".utf8), outputByteCount: 32)
    }
}

enum MoodTopic {
    static func forSlot(_ name: String) -> String {
        Data(SHA256.hash(data: Data(("dotlings/mood-alerts/1/" + name).utf8))).hex
    }
}

struct CircleEnvelope: Codable {
    let key: Data
    var preview: Data?
    var mood: Data?
    var guestKey: Data?
    var revoked = false
}

struct CircleSlot {
    let content: CircleEnvelope
    let creator: String
    let created: Date
    let record: CKRecord
}

@MainActor protocol CircleTransport {
    func account() async throws -> String
    func fetch(_ name: String) async throws -> CircleSlot?
    func write(_ content: CircleEnvelope, name: String, replacing: CircleSlot?) async throws
}

@MainActor private final class AppleCircleTransport: CircleTransport {
    private lazy var container = CKContainer(identifier: DotsConfig.container)
    func account() async throws -> String {
        switch try await container.accountStatus() {
        case .available: return try await container.userRecordID().recordName
        case .noAccount, .restricted: throw LinkError.signIn
        default: throw LinkError.unavailable
        }
    }
    func fetch(_ name: String) async throws -> CircleSlot? {
        do {
            let record = try await container.publicCloudDatabase.record(for: .init(recordName: name))
            guard record.recordType == "DotlingFriendSlot", let bytes = record["payload"] as? Data,
                  let owner = record.creatorUserRecordID?.recordName, let date = record.creationDate else { throw LinkError.denied }
            return try CircleSlot(content: JSONDecoder().decode(CircleEnvelope.self, from: bytes), creator: owner, created: date, record: record)
        } catch let error as CKError where error.code == .unknownItem { return nil }
    }
    func write(_ content: CircleEnvelope, name: String, replacing old: CircleSlot?) async throws {
        let record = old?.record ?? CKRecord(recordType: "DotlingFriendSlot", recordID: .init(recordName: name))
        if content.mood != nil && !content.revoked {
            record["moodTopic"] = MoodTopic.forSlot(name) as CKRecordValue
        } else { record["moodTopic"] = nil }
        record["payload"] = try JSONEncoder().encode(content) as CKRecordValue
        let result = try await container.publicCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
        guard let saved = result.saveResults[record.recordID] else { throw LinkError.unavailable }
        _ = try saved.get()
    }
}

protocol CircleKeys {
    func routes(_ account: String) throws -> [String: CircleRoute]
    func save(_ routes: [String: CircleRoute], account: String) throws
}

private struct DeviceCircleKeys: CircleKeys {
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Dotlings.AppleCircle.v1",
         kSecAttrAccount as String: account, kSecAttrAccessGroup as String: DotsConfig.group]
    }
    func routes(_ account: String) throws -> [String: CircleRoute] {
        var query = query(account)
        query[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let bytes = value as? Data else { throw LinkError.keychain }
        return try JSONDecoder().decode([String: CircleRoute].self, from: bytes)
    }
    func save(_ routes: [String: CircleRoute], account: String) throws {
        var entry = query(account)
        let bytes = try JSONEncoder().encode(routes)
        let status = SecItemUpdate(entry as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            entry[kSecValueData as String] = bytes
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw LinkError.keychain }
        } else if status != errSecSuccess { throw LinkError.keychain }
    }
}

@MainActor final class FriendLinks {
    static let shared = FriendLinks(transport: AppleCircleTransport(), keys: DeviceCircleKeys())
    let transport: any CircleTransport
    let keys: any CircleKeys
    init(transport: any CircleTransport, keys: any CircleKeys) { self.transport = transport; self.keys = keys }
    private let lifetime: TimeInterval = 7 * 86400

    private func store(_ route: CircleRoute, account: String) throws {
        var routes = try keys.routes(account)
        routes[route.invite.id] = route
        try keys.save(routes, account: account)
    }
    private func forget(_ route: CircleRoute, account: String) throws {
        var routes = try keys.routes(account)
        routes.removeValue(forKey: route.invite.id)
        try keys.save(routes, account: account)
    }
    private struct Card: Codable, Equatable {
        let owner: String, pet: String, kind: CompanionKind, mood: Mood, date: Date
        let activity: Mood?
        init(_ companion: Companion) {
            owner = companion.ownerName; pet = companion.petName; kind = companion.kind
            mood = companion.mood.legacySharingMood; date = companion.updatedAt
            activity = mood == companion.mood ? nil : companion.mood
        }
        func encrypted(_ key: SymmetricKey, id: String) throws -> Data {
            try ChaChaPoly.seal(JSONEncoder().encode(self), using: key, authenticating: Data(id.utf8)).combined
        }
        static func open(_ bytes: Data, key: SymmetricKey, id: String) throws -> Self {
            let data = try ChaChaPoly.open(.init(combined: bytes), using: key, authenticating: Data(id.utf8))
            return try JSONDecoder().decode(Self.self, from: data)
        }
        func friend(_ id: String) -> Companion {
            Companion(id: "friend:" + id, ownerName: owner, petName: pet, mood: activity ?? mood, updatedAt: date, kind: kind)
        }
    }
    func invite(_ pet: Companion) async throws -> FriendInvite {
        let account = try await transport.account()
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let seed = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let invite = FriendInvite(seed: seed, senderKey: privateKey.publicKey.rawRepresentation)
        let route = CircleRoute(invite: invite, sender: true, secret: privateKey.rawRepresentation)
        let preview = try Card(pet).encrypted(invite.previewKey, id: route.own)
        try store(route, account: account)
        try await transport.write(.init(key: invite.senderKey, preview: preview), name: route.own, replacing: nil)
        return invite
    }
    func accept(_ invite: FriendInvite, companion: Companion) async throws {
        let account = try await transport.account()
        guard let host = try await transport.fetch(invite.id), !host.content.revoked, host.content.key == invite.senderKey else { throw LinkError.denied }
        guard host.creator != account, host.creator != CKCurrentUserDefaultName else { throw LinkError.selfInvite }
        let existing = try keys.routes(account)[invite.id]
        guard existing?.sender != true else { throw LinkError.selfInvite }
        let route = existing ?? CircleRoute(invite: invite, sender: false, secret: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
        let key = try route.privateKey.publicKey.rawRepresentation
        if let claimed = try await transport.fetch(route.own) {
            guard claimed.content.key == key, !claimed.content.revoked,
                  claimed.created <= host.created.addingTimeInterval(lifetime) else { throw LinkError.denied }
            return
        }
        guard Date() < host.created.addingTimeInterval(lifetime) else { throw LinkError.denied }
        try store(route, account: account)
        let mood = try Card(companion).encrypted(route.pairKey(invite.senderKey), id: route.own)
        do { try await transport.write(.init(key: key, mood: mood), name: route.own, replacing: nil) }
        catch {
            if let winner = try await transport.fetch(route.own) {
                if winner.content.key == key && !winner.content.revoked { return }
                try forget(route, account: account)
                throw LinkError.denied
            }
            throw error
        }
    }
    private func connected(_ route: CircleRoute) async throws -> (CircleSlot, CircleSlot)? {
        async let a = transport.fetch(route.own)
        async let b = transport.fetch(route.peer)
        guard case let (own?, peer?) = try await (a,b), !own.content.revoked, !peer.content.revoked,
              own.content.key == (try route.privateKey.publicKey.rawRepresentation) else { return nil }
        let (host, guest) = route.sender ? (own, peer) : (peer, own)
        guard host.content.key == route.invite.senderKey, guest.created <= host.created.addingTimeInterval(lifetime),
              guest.creator != host.creator, host.content.guestKey == nil || host.content.guestKey == guest.content.key else { return nil }
        return (own, peer)
    }
    func publish(_ pet: Companion) async throws {
        let account = try await transport.account()
        var issue: Error?
        for route in try keys.routes(account).values {
            do {
                guard let (own, peer) = try await connected(route) else { continue }
                let key = try route.pairKey(peer.content.key)
                let next = Card(pet)
                if let previous = own.content.mood, let last = try? Card.open(previous, key: key, id: route.own),
                   last == next || last.date > next.date { continue }
                let mood = try next.encrypted(key, id: route.own)
                try await transport.write(.init(key: own.content.key, mood: mood, guestKey: route.sender ? peer.content.key : nil), name: route.own, replacing: own)
            } catch { issue = error }
        }
        if let issue { throw issue }
    }
    func friends() async throws -> [Companion] {
        let account = try await transport.account()
        var result: [Companion] = []
        for route in try keys.routes(account).values {
            guard let (_, peer) = try await connected(route) else { continue }
            let card: Card
            if let bytes = peer.content.mood {
                card = try Card.open(bytes, key: route.pairKey(peer.content.key), id: route.peer)
            } else if !route.sender, let bytes = peer.content.preview {
                card = try Card.open(bytes, key: route.invite.previewKey, id: route.peer)
            } else { continue }
            result.append(card.friend(route.invite.id))
        }
        return result
    }
    func peerRecords(for friends: [Companion]) async throws -> Set<String> {
        let ids = Set(friends.map(\.id))
        let routes = try keys.routes(await transport.account())
        return Set(routes.values.filter { ids.contains("friend:" + $0.invite.id) }.map(\.peer))
    }

    struct SentPass: Identifiable {
        let id: String
        let created: Date
        let expires: Date
        let accepted: Bool
    }
    func sent() async throws -> [SentPass] {
        let account = try await transport.account()
        var result: [SentPass] = []
        for r in try keys.routes(account).values where r.sender {
            guard let host = try await transport.fetch(r.own), !host.content.revoked else { continue }
            let guest = try await transport.fetch(r.peer)
            guard guest?.content.revoked != true else { continue }
            let expiry = host.created.addingTimeInterval(lifetime)
            result.append(.init(id: r.invite.id, created: host.created, expires: expiry, accepted: guest.map { $0.created <= expiry } ?? false))
        }
        return result.sorted { $0.created > $1.created }
    }
    private func disconnect(_ route: CircleRoute, account: String) async throws {
        if let own = try await transport.fetch(route.own), !own.content.revoked, own.content.key == (try route.privateKey.publicKey.rawRepresentation) {
            // Reserve the single-use record ID permanently. Remove its public key and both ciphertexts.
            try await transport.write(.init(key: Data(), revoked: true), name: route.own, replacing: own)
        }
        try forget(route, account: account)
    }
    private func remove(_ id: String) async throws {
        let account = try await transport.account()
        if let r = try keys.routes(account)[id] { try await disconnect(r, account: account) }
    }
    func leave(_ friend: Companion) async throws { try await remove(String(friend.id.dropFirst("friend:".count))) }
    func revoke(_ pass: SentPass) async throws { try await remove(pass.id) }
    func erase() async throws {
        let account = try await transport.account()
        for r in try keys.routes(account).values { try await disconnect(r, account: account) }
    }
}

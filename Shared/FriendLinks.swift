import Foundation
import Security

struct FriendInvite: Identifiable {
    static let host = "dotlings-circle-6825127572.web.app"
    let owner: String
    let pass: String
    let mutual: Bool
    var id: String { (mutual ? "together/" : "") + owner + "/" + pass }
    var url: URL { URL(string: "https://" + Self.host + "/invite#" + id)! }
    init(owner: String, pass: String, mutual: Bool = true) { self.owner = owner; self.pass = pass; self.mutual = mutual }
    init?(url: URL) {
        guard url.scheme == "dots", ["connect", "invite"].contains(url.host ?? "") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0].range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
              parts[1].range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil else { return nil }
        self.init(owner: parts[0], pass: parts[1], mutual: url.host == "connect")
    }
}

private struct FriendSession: Codable {
    let uid: String
    let token: String
    let refresh: String
    let expires: Date

    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Dotlings.FriendSession.v1",
         kSecAttrAccount as String: "device", kSecAttrAccessGroup as String: DotsConfig.group]
    }
    static func load() throws -> Self? {
        var query = Self.query
        query[kSecReturnData as String] = true
        var value: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &value)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = value as? Data else { throw LinkError.keychain }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        let changes = [kSecValueData as String: data]
        let code = SecItemUpdate(Self.query as CFDictionary, changes as CFDictionary)
        if code == errSecItemNotFound {
            var entry = Self.query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw LinkError.keychain }
        } else if code != errSecSuccess { throw LinkError.keychain }
    }
    static func clear() throws {
        let code = SecItemDelete(query as CFDictionary)
        guard code == errSecSuccess || code == errSecItemNotFound else { throw LinkError.keychain }
    }
}

enum LinkError: LocalizedError {
    case unavailable, denied, keychain, selfInvite
    var errorDescription: String? {
        switch self {
        case .unavailable: "Dotlings couldn’t reach friend sharing. Check your connection and try again."
        case .denied: "This invitation has expired, was already used, or was turned off. Ask your friend for a new link."
        case .keychain: "Unlock your iPhone and try again so Dotlings can access your circle."
        case .selfInvite: "This is your invitation. Send it to the friend you want to invite."
        }
    }
}

@MainActor
final class FriendLinks {
    static let shared = FriendLinks()
    private struct Config: Decodable { let apiKey: String; let databaseURL: URL }
    private struct Pass: Decodable { let expires: Double; let reader: String? }
    private var config: Config?
    private var connecting: Task<FriendSession, Error>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let http = URLSession(configuration: .ephemeral)

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await http.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw LinkError.unavailable }
        if status == 401 || status == 403 { throw LinkError.denied }
        guard (200..<300).contains(status) else { throw LinkError.unavailable }
        return data
    }
    private func configuration() async throws -> Config {
        if let config { return config }
        let url = URL(string: "https://" + FriendInvite.host + "/__/firebase/init.json")!
        let loaded = try decoder.decode(Config.self, from: try await send(URLRequest(url: url)))
        guard loaded.databaseURL.scheme == "https",
              let host = loaded.databaseURL.host,
              host.hasSuffix(".firebaseio.com") || host.hasSuffix(".firebasedatabase.app") else { throw LinkError.unavailable }
        config = loaded
        return loaded
    }
    private func session() async throws -> FriendSession {
        if let connecting { return try await connecting.value }
        let saved = try FriendSession.load()
        if let saved, saved.expires > Date().addingTimeInterval(90) { return saved }
        let task = Task { @MainActor in
            let config = try await self.configuration()
            let base = saved == nil ? "https://identitytoolkit.googleapis.com/v1/accounts:signUp" : "https://securetoken.googleapis.com/v1/token"
            var request = URLRequest(url: URL(string: base + "?key=" + config.apiKey)!)
            request.httpMethod = "POST"
            if let saved {
                var form = URLComponents()
                form.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token"), URLQueryItem(name: "refresh_token", value: saved.refresh)]
                request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            } else {
                request.httpBody = Data(#"{"returnSecureToken":true}"#.utf8)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let response = try await self.send(request)
            guard let obj = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  let uid = (obj["localId"] ?? obj["user_id"]) as? String,
                  let token = (obj["idToken"] ?? obj["id_token"]) as? String,
                  let refresh = (obj["refreshToken"] ?? obj["refresh_token"]) as? String,
                  let seconds = (obj["expiresIn"] ?? obj["expires_in"]) as? String,
                  let duration = Double(seconds) else { throw LinkError.unavailable }
            let value = FriendSession(uid: uid, token: token, refresh: refresh, expires: Date().addingTimeInterval(duration))
            try value.save()
            return value
        }
        connecting = task
        defer { connecting = nil }
        return try await task.value
    }
    private func db(_ method: String, _ path: String, _ session: FriendSession, _ body: Data? = nil) async throws -> Data {
        let config = try await configuration()
        var parts = URLComponents(url: config.databaseURL.appendingPathComponent(path + ".json"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "auth", value: session.token)]
        var req = URLRequest(url: parts.url!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(req)
    }
    private struct MoodCard: Codable {
        let ownerName: String, petName: String, kind: CompanionKind, mood: Mood, updatedAt: Date
        init(_ pet: Companion) {
            ownerName = pet.ownerName; petName = pet.petName; kind = pet.kind; mood = pet.mood; updatedAt = pet.updatedAt
        }
        func companion(owner: String) -> Companion {
            Companion(id: "friend:" + owner, ownerName: ownerName, petName: petName, mood: mood, updatedAt: updatedAt, kind: kind)
        }
    }
    private var lastPublished: MoodCard?
    private var publishing = false
    func publish(_ pet: Companion) async throws {
        while publishing { try await Task.sleep(for: .milliseconds(50)) }
        if lastPublished?.updatedAt == pet.updatedAt { return }
        publishing = true
        defer { publishing = false }
        let session = try await session()
        let card = MoodCard(pet)
        _ = try await db("PUT", "people/" + session.uid + "/mood", session, encoder.encode(card))
        lastPublished = card
    }
    func invite(_ pet: Companion) async throws -> FriendInvite {
        let session = try await session()
        try await publish(pet)
        let invite = FriendInvite(owner: session.uid, pass: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        let expiry = Date().addingTimeInterval(7 * 86400).timeIntervalSince1970 * 1000
        _ = try await db("PUT", "connections/" + session.uid + "/" + invite.pass, session, encoder.encode(["expires": expiry]))
        return invite
    }
    func accept(_ invite: FriendInvite, companion: Companion) async throws {
        let s = try await session()
        guard invite.owner != s.uid else { throw LinkError.selfInvite }
        if invite.mutual {
            let card = try JSONSerialization.jsonObject(with: encoder.encode(MoodCard(companion)))
            let updates: [String: Any] = [
                "connections/" + invite.owner + "/" + invite.pass + "/reader": s.uid,
                "bonds/" + invite.owner + "/" + s.uid: invite.pass,
                "bonds/" + s.uid + "/" + invite.owner: invite.pass,
                "people/" + s.uid + "/mood": card
            ]
            _ = try await db("PATCH", "", s, JSONSerialization.data(withJSONObject: updates))
            return
        }
        let base = "people/" + invite.owner
        _ = try await db("PUT", base + "/passes/" + invite.pass + "/reader", s, encoder.encode(s.uid))
        _ = try await db("PUT", base + "/grants/" + s.uid, s, encoder.encode(invite.pass))
        _ = try await db("PUT", "following/" + s.uid + "/" + invite.owner, s, encoder.encode(true))
    }
    func friends() async throws -> [Companion] {
        let s = try await session()
        let following = try await db("GET", "following/" + s.uid, s)
        let ids = try decoder.decode([String: Bool]?.self, from: following) ?? [:]
        var friends: [Companion] = []
        let bonds = try await connections(for: s)
        for owner in Set(ids.keys).union(bonds.keys) {
            do {
                let data = try await db("GET", "people/" + owner + "/mood", s)
                if let card = try decoder.decode(MoodCard?.self, from: data) { friends.append(card.companion(owner: owner)) }
            } catch LinkError.denied { continue } // Revocation takes effect on the next successful refresh.
        }
        return friends
    }
    private func connections(for s: FriendSession) async throws -> [String: String] {
        let data = try await db("GET", "bonds/" + s.uid, s)
        return try decoder.decode([String: String]?.self, from: data) ?? [:]
    }

    private func endConnection(sender: String, pass: String, reader: String?, session: FriendSession) async throws {
        var deletes = ["connections/" + sender + "/" + pass: NSNull()]
        if let reader {
            deletes["bonds/" + sender + "/" + reader] = NSNull()
            deletes["bonds/" + reader + "/" + sender] = NSNull()
        }
        _ = try await db("PATCH", "", session, JSONSerialization.data(withJSONObject: deletes))
    }

    func leave(_ friend: Companion) async throws {
        let s = try await session()
        try await leave(peer: String(friend.id.dropFirst("friend:".count)), session: s)
    }
    private func leave(peer: String, session s: FriendSession) async throws {
        if let pass = try await connections(for: s)[peer] {
            let own = try await db("GET", "connections/" + s.uid + "/" + pass, s)
            let sentByMe = try decoder.decode(Pass?.self, from: own) != nil
            try await endConnection(sender: sentByMe ? s.uid : peer, pass: pass, reader: sentByMe ? peer : s.uid, session: s)
        }
        _ = try await db("DELETE", "people/" + peer + "/grants/" + s.uid, s)
        _ = try await db("DELETE", "following/" + s.uid + "/" + peer, s)
    }
    struct SentPass: Identifiable {
        let id: String
        let expires: Date
        let reader: String?
        let mutual: Bool
        var accepted: Bool { reader != nil }
        var created: Date { expires.addingTimeInterval(-7 * 86400) }
    }
    func sent() async throws -> [SentPass] {
        let s = try await session()
        var result: [SentPass] = []
        for (path, mutual) in [("connections/" + s.uid, true), ("people/" + s.uid + "/passes", false)] {
            let data = try await db("GET", path, s)
            let passes = try decoder.decode([String: Pass]?.self, from: data) ?? [:]
            result += passes.map { SentPass(id: $0.key, expires: Date(timeIntervalSince1970: $0.value.expires / 1000), reader: $0.value.reader, mutual: mutual) }
        }
        return result.sorted { $0.expires > $1.expires }
    }
    func revoke(_ pass: SentPass) async throws {
        let s = try await session()
        if pass.mutual {
            // A pending invite may have been claimed while this screen was open.
            let data = try await db("GET", "connections/" + s.uid + "/" + pass.id, s)
            if let current = try decoder.decode(Pass?.self, from: data) {
                try await endConnection(sender: s.uid, pass: pass.id, reader: current.reader, session: s)
            }
        } else {
            _ = try await db("DELETE", "people/" + s.uid + "/passes/" + pass.id, s)
        }
    }
    private func stopSharing() async throws {
        let s = try await session()
        _ = try await db("DELETE", "people/" + s.uid, s)
        lastPublished = nil
    }
    func erase() async throws {
        guard try FriendSession.load() != nil else { return }
        let s = try await session()
        let bonds = try await connections(for: s)
        for peer in bonds.keys {
            try await leave(peer: peer, session: s)
        }
        for pass in try await sent() where pass.mutual { try await revoke(pass) }
        try await stopSharing()
        let following = try decoder.decode([String: Bool]?.self, from: try await db("GET", "following/" + s.uid, s)) ?? [:]
        for owner in following.keys { _ = try await db("DELETE", "people/" + owner + "/grants/" + s.uid, s) }
        _ = try await db("DELETE", "following/" + s.uid, s)
        let config = try await configuration()
        var req = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=" + config.apiKey)!)
        req.httpMethod = "POST"; req.httpBody = try encoder.encode(["idToken": s.token])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await send(req)
        try FriendSession.clear()
    }
}

import Foundation

enum Mood: String, Codable, CaseIterable, Identifiable {
    case happy, calm, sleepy, sad, overwhelmed, focused
    var id: String { rawValue }
    var title: String {
        switch self {
        case .happy: "Happy"
        case .calm: "Calm"
        case .sleepy: "Sleepy"
        case .sad: "A little low"
        case .overwhelmed: "Overwhelmed"
        case .focused: "Focused"
        }
    }
    var symbol: String {
        switch self {
        case .happy: "sun.max.fill"
        case .calm: "leaf.fill"
        case .sleepy: "moon.fill"
        case .sad: "cloud.drizzle.fill"
        case .overwhelmed: "wind"
        case .focused: "sparkle"
        }
    }
    var reassurance: String {
        switch self {
        case .happy: "A little sunshine, shared."
        case .calm: "Nothing to rush. Just be here."
        case .sleepy: "Small creature. Big need for a nap."
        case .sad: "You don't have to be sunshine today."
        case .overwhelmed: "One tiny thing at a time."
        case .focused: "In your own little world."
        }
    }
    var spriteIndex: Int { Self.allCases.firstIndex(of: self)! }
}

enum CompanionKind: String, Codable, CaseIterable, Identifiable {
    case lavender, blue, pillow
    case pebble, sprout, twinkle, pudding, bean, ember, moss, luna, bubble, snow, sunny, dusk, petal, nimbus, toast, puff, ripple
    case onion, cumulus, bonsai, droplet, drizzle, storm, bowling, coffee, coconut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lavender: "Lilac"; case .blue: "Sky"; case .pillow: "Cloud"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
    var defaultName: String {
        switch self {
        case .onion: "Ollie"; case .cumulus: "Floss"; case .bonsai: "Bonsy"
        case .droplet: "Dew"; case .drizzle: "Pitter"; case .storm: "Zippy"
        case .bowling: "Rollie"; case .coffee: "Mocha"; case .coconut: "Coco"
        default: title
        }
    }
    var touchAsset: String { asset.replacingOccurrences(of: "Atlas", with: "TouchAtlas") }
    var asset: String {
        switch self {
        case .lavender: "CompanionAtlas"; case .blue: "CompanionBlueAtlas"; case .pillow: "CompanionPillowAtlas"
        default: "Companion" + title + "Atlas"
        }
    }
}

struct Companion: Codable, Identifiable, Equatable {
    var id: String
    var ownerName: String
    var petName: String
    var mood: Mood
    var updatedAt: Date
    var kind: CompanionKind = .lavender
    // Shared records keep their zone identity so invitations never expose a public directory.
    var zoneName: String?
    var zoneOwner: String?
    var recordName: String?
}

enum WidgetMode: String, Codable, CaseIterable, Identifiable {
    case latest, pinned
    var id: String { rawValue }
    var title: String { self == .latest ? "Latest friend mood" : "Pinned friend" }
}

struct CircleState: Codable, Equatable {
    var cloudEnabled = false
    var companion: Companion?
    var friends: [Companion] = []
    var pinnedFriendID: String?
    var widgetMode: WidgetMode = .latest
    var lastSyncedAt: Date?
    var collection = CollectionProgress()

    init(cloudEnabled: Bool = false, companion: Companion? = nil, friends: [Companion] = [], pinnedFriendID: String? = nil,
         widgetMode: WidgetMode = .latest, lastSyncedAt: Date? = nil, collection: CollectionProgress = CollectionProgress()) {
        self.cloudEnabled = cloudEnabled; self.companion = companion; self.friends = friends
        self.pinnedFriendID = pinnedFriendID; self.widgetMode = widgetMode; self.lastSyncedAt = lastSyncedAt
        self.collection = collection
        if let companion {
            if !self.collection.owned.contains(companion.kind) { self.collection.owned.append(companion.kind) }
            if self.collection.names[companion.kind.rawValue] == nil { self.collection.names[companion.kind.rawValue] = companion.petName }
        }
    }

    private enum CodingKeys: String, CodingKey { case cloudEnabled, companion, friends, pinnedFriendID, widgetMode, lastSyncedAt, collection }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cloudEnabled = try c.decodeIfPresent(Bool.self, forKey: .cloudEnabled) ?? false
        companion = try c.decodeIfPresent(Companion.self, forKey: .companion)
        friends = try c.decodeIfPresent([Companion].self, forKey: .friends) ?? []
        pinnedFriendID = try c.decodeIfPresent(String.self, forKey: .pinnedFriendID)
        widgetMode = try c.decodeIfPresent(WidgetMode.self, forKey: .widgetMode) ?? .latest
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        collection = try c.decodeIfPresent(CollectionProgress.self, forKey: .collection) ?? CollectionProgress()
        if let companion {
            if !collection.owned.contains(companion.kind) { collection.owned.append(companion.kind) }
            if collection.names[companion.kind.rawValue] == nil { collection.names[companion.kind.rawValue] = companion.petName }
        }
    }

    var sortedFriends: [Companion] {
        friends.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
    }
    func widgetFriend(mode: WidgetMode? = nil, friendID: String? = nil) -> Companion? {
        if let friendID { return friends.first { $0.id == friendID } }
        switch mode ?? widgetMode {
        case .latest: return sortedFriends.first
        case .pinned: return friends.first { $0.id == pinnedFriendID }
        }
    }
    mutating func removeFriend(_ id: String) {
        friends.removeAll { $0.id == id }
        if pinnedFriendID == id { pinnedFriendID = nil }
    }
}

enum DotsConfig {
    static let group = "group.com.jasonmiller.dots"
    static let container = "iCloud.com.jasonmiller.dots"
    static let widgetKind = "FriendMood"
}

final class CircleStore {
    let url: URL
    init(root: URL? = nil) {
        let directory = root
            ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DotsConfig.group)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dots")
        url = directory.appendingPathComponent("circle.json")
    }
    func load() throws -> CircleState {
        guard FileManager.default.fileExists(atPath: url.path) else { return CircleState() }
        return try JSONDecoder().decode(CircleState.self, from: Data(contentsOf: url))
    }
    func save(_ state: CircleState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

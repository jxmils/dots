import WidgetKit
import SwiftUI
import AppIntents

enum FriendSelection: String, AppEnum {
    case appDefault, latest, selected
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static var caseDisplayRepresentations: [FriendSelection: DisplayRepresentation] = [
        .appDefault: "Use my Dots setting", .latest: "Latest friend mood", .selected: "One friend"
    ]
}

struct FriendEntity: AppEntity {
    let id: String
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Friend"
    static var defaultQuery = FriendQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FriendQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FriendEntity] {
        try CircleStore().load().sortedFriends.filter { identifiers.contains($0.id) }.map { FriendEntity(id: $0.id, name: $0.ownerName) }
    }
    func suggestedEntities() async throws -> [FriendEntity] {
        try CircleStore().load().sortedFriends.map { FriendEntity(id: $0.id, name: $0.ownerName) }
    }
}

struct FriendMoodIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "A friend, a little closer"
    static var description = IntentDescription("Show your latest friend's mood, or keep one person close.")
    @Parameter(title: "Show", default: .appDefault) var selection: FriendSelection
    @Parameter(title: "Friend") var friend: FriendEntity?
    static var parameterSummary: some ParameterSummary {
        When(\.$selection, .equalTo, FriendSelection.selected) { Summary("Show \(\.$selection): \(\.$friend)") }
        otherwise: { Summary("Show \(\.$selection)") }
    }
}

struct MoodEntry: TimelineEntry {
    let date: Date
    let friend: Companion?
}

struct MoodProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MoodEntry {
        MoodEntry(date: Date(), friend: Companion(id: "preview", ownerName: "Sam", petName: "Pip", mood: .happy, updatedAt: Date(), kind: .pillow))
    }
    func snapshot(for configuration: FriendMoodIntent, in context: Context) async -> MoodEntry {
        if context.isPreview { return placeholder(in: context) }
        return entry(configuration, state: (try? CircleStore().load()) ?? CircleState())
    }
    func timeline(for configuration: FriendMoodIntent, in context: Context) async -> Timeline<MoodEntry> {
        let store = CircleStore()
        var state = (try? store.load()) ?? CircleState()
        if state.cloudEnabled {
            do {
                let friends = try await CloudCircle().friends()
                // Reload before saving so a slow fetch doesn't overwrite a newer local mood or widget setting.
                state = try store.load()
                state.friends = friends
                state.lastSyncedAt = Date()
                if !friends.contains(where: { $0.id == state.pinnedFriendID }) { state.pinnedFriendID = nil }
                try store.save(state)
            } catch { /* Keep the last received mood, with its original timestamp. */ }
        }
        return Timeline(entries: [entry(configuration, state: state)], policy: .after(Date().addingTimeInterval(20 * 60)))
    }
    private func entry(_ configuration: FriendMoodIntent, state: CircleState) -> MoodEntry {
        let friend: Companion?
        switch configuration.selection {
        case .appDefault: friend = state.widgetFriend()
        case .latest: friend = state.widgetFriend(mode: .latest)
        case .selected: friend = configuration.friend.flatMap { state.widgetFriend(friendID: $0.id) }
        }
        return MoodEntry(date: Date(), friend: friend)
    }
}

struct MoodWidgetView: View {
    let entry: MoodEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                FriendWidgetView(friend: entry.friend, circular: true)
            case .accessoryInline:
                FriendWidgetView(friend: entry.friend, inline: true)
            case .systemSmall:
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(entry.friend?.ownerName ?? "Your little circle").font(DotsStyle.round(15, weight: .bold)).lineLimit(1)
                        Spacer(); Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(DotsStyle.plum)
                    }
                    if let friend = entry.friend {
                        CompanionView(mood: friend.mood, kind: friend.kind).frame(maxWidth: .infinity, maxHeight: .infinity)
                        HStack { Text(friend.mood.title); Spacer(); Text(friend.updatedAt, style: .relative) }.font(.system(size: 10)).lineLimit(1)
                    } else {
                        Spacer(); Text("A small hello goes a long way.").font(DotsStyle.round(14)); Spacer()
                        Text("Add a friend in Dots").font(.caption2)
                    }
                }.foregroundStyle(DotsStyle.ink)
            default:
                FriendWidgetView(friend: entry.friend)
            }
        }
        .containerBackground(for: .widget) { DotsStyle.paper }
        .widgetURL(URL(string: "dots://friends"))
    }
}

@main
struct DotsWidget: Widget {
    let kind = DotsConfig.widgetKind
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FriendMoodIntent.self, provider: MoodProvider()) { MoodWidgetView(entry: $0) }
            .configurationDisplayName("A little closer")
            .description("A small glimpse of how a friend is feeling.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

#if DEBUG
import SwiftUI

// Fictional sample data for repeatable simulator captures. Excluded from distribution builds.
@MainActor struct StoreCapture: View {
    @State private var page: String
    @State private var model: CircleModel

    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--capture-page")
        let requested = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "home"
        let page = ["home", "low", "friends", "collection", "widget", "hatch", "name", "profile"].contains(requested) ? requested : "home"
        var state = Self.sample()
        if ["low", "profile"].contains(page) {
            state.companion?.kind = .coconut; state.companion?.petName = "Coco"
            state.companion?.mood = page == "low" ? .sad : .happy
        }
        _page = State(initialValue: page)
        _model = State(initialValue: CircleModel(previewState: state))
    }

    static func sample() -> CircleState {
        let now = Date()
        let me = Companion(id: "capture-me", ownerName: "Alex", petName: "Cloud", mood: .happy, updatedAt: now, kind: .pillow)
        let friends = [
            Companion(id: "capture-sam", ownerName: "Sam", petName: "Coco", mood: .calm, updatedAt: now.addingTimeInterval(-300), kind: .coconut),
            Companion(id: "capture-mia", ownerName: "Mia", petName: "Sprout", mood: .overwhelmed, updatedAt: now.addingTimeInterval(-900), kind: .sprout),
            Companion(id: "capture-leo", ownerName: "Leo", petName: "Twinkle", mood: .happy, updatedAt: now.addingTimeInterval(-1800), kind: .twinkle)
        ]
        var collection = CollectionProgress()
        collection.owned = [.lavender, .blue, .pillow, .twinkle, .coconut, .bonsai]
        for kind in collection.owned { collection.names[kind.rawValue] = kind.defaultName }
        collection.lastCheckInDay = CheckInDay.number(now)
        collection.streak = 100; collection.bestStreak = 100; collection.totalDays = 100
        collection.earnedMilestones = [5, 10, 25, 50, 100]
        return CircleState(cloudEnabled: true, companion: me, friends: friends, pinnedFriendID: "capture-sam", widgetMode: .pinned, lastSyncedAt: now, collection: collection)
    }

    var body: some View {
        Group {
            switch page {
            case "hatch": HatchingView(free: true)
            case "name": HatchingView(free: true, previewRevealed: .coconut)
            case "profile": SettingsView(onChooseDot: { page = "collection" })
            default: DotsRoot(tab: tab).id(page)
            }
        }.environment(model).preferredColorScheme(.light)
            .background(DotsStyle.paper.ignoresSafeArea())
    }
    private var tab: DotsTab {
        switch page {
        case "friends": .friends
        case "collection": .collection
        case "widget": .widget
        default: .home
        }
    }
}
#endif

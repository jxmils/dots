import Foundation
import UIKit

@main struct Checks {
    @MainActor static func main() throws {
        let now = Date(timeIntervalSince1970: 1_792_540_000)
        let a = Companion(id: "a", ownerName: "Alex", petName: "Mochi", mood: .calm, updatedAt: now)
        let b = Companion(id: "b", ownerName: "Sam", petName: "Pip", mood: .happy, updatedAt: now.addingTimeInterval(600), kind: .pillow)
        var state = CircleState(companion: a, friends: [a, b])
        precondition(state.widgetFriend()?.id == "b", "Latest must select the newest mood")
        state.pinnedFriendID = "a"; state.widgetMode = .pinned
        precondition(state.widgetFriend()?.id == "a", "Pin must override chronology")
        precondition(state.widgetFriend(mode: .latest)?.id == "b", "Explicit latest must override the app setting")
        precondition(state.widgetFriend(friendID: "missing") == nil, "Missing friend must never silently become another person")
        state.removeFriend("a")
        precondition(state.pinnedFriendID == nil && state.widgetFriend() == nil, "Removing a pinned friend must clear the widget")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CircleStore(root: root)
        try store.save(state)
        let restored = try store.load()
        precondition(restored == state, "Save/load must retain the complete circle")
        try Data("invalid".utf8).write(to: store.url)
        do { _ = try store.load(); fatalError("Corrupt storage must be reported") } catch {}
        let modelStore = CircleStore(root: root.appendingPathComponent("model"))
        let model = CircleModel(store: modelStore)
        model.adopt(owner: " Jason ", name: " Cloud ", kind: .pillow)
        precondition(model.state.companion?.ownerName == "Jason" && model.state.companion?.petName == "Cloud")
        model.setMood(.sleepy)
        let savedMood = try modelStore.load().companion?.mood
        precondition(savedMood == .sleepy, "Mood changes must persist before syncing")
        precondition(model.state.friends.isEmpty && !model.state.cloudEnabled, "New installs must have no fake friends or implicit sharing")
        model.rename(owner: "  ", pet: "")
        precondition(model.state.companion?.ownerName == "Jason", "Blank rename must preserve the existing name")
        precondition(CompanionKind.allCases.count == 29, "The collection must contain all 29 creatures")
        var progress = CollectionProgress()
        precondition(progress.hatch(.pillow, free: true), "The first hatch must be free")
        precondition(!progress.hatch(.blue, free: true), "The free hatch must not repeat")
        for day in 1...5 { progress.checkIn(on: day) }
        precondition(progress.streak == 5 && progress.eggs == [5], "The fifth actual check-in earns one egg")
        progress.checkIn(on: 5)
        precondition(progress.totalDays == 5 && progress.eggs.count == 1, "Repeated mood taps must not farm rewards")
        progress.checkIn(on: 4)
        precondition(progress.lastCheckInDay == 5, "Turning the clock back must not rewind the ledger")
        precondition(progress.canOfferRestore(on: 8), "A gap should offer a restore")
        progress.checkIn(on: 8, restore: true)
        precondition(progress.streak == 6 && progress.totalDays == 6 && progress.restoresUsed == 1,
                     "A restore bridges the gap but never counts the missed days")
        progress.checkIn(on: 10, restore: true)
        progress.checkIn(on: 12, restore: true)
        precondition(progress.restoresRemaining == 0 && progress.streak == 8, "Only three lifetime restores are available")
        progress.checkIn(on: 15, restore: true)
        precondition(progress.streak == 1 && progress.restoresUsed == 3 && progress.eggs == [5] && progress.owned == [.pillow],
                     "After all restores are spent, reset only the streak and keep earned rewards")
        for day in 16...19 { progress.checkIn(on: day) }
        precondition(progress.eggs == [5], "A milestone can only be earned once across streak resets")
        var full = CollectionProgress()
        precondition(full.hatch(.lavender, free: true))
        for day in 1...CollectionProgress.milestones.last! { full.checkIn(on: day) }
        precondition(full.eggs.count == CompanionKind.allCases.count - 1, "The milestone schedule must supply every remaining creature")
        while let kind = full.unowned.first { precondition(full.hatch(kind, free: false)) }
        precondition(Set(full.owned).count == CompanionKind.allCases.count && full.eggs.isEmpty, "All reward hatches must be new creatures")
        let namingStore = CircleStore(root: root.appendingPathComponent("names"))
        var namingState = CircleState(companion: a)
        namingState.collection.names[a.kind.rawValue] = a.petName
        namingState.collection.eggs = [5]
        try namingStore.save(namingState)
        let namingModel = CircleModel(store: namingStore)
        let hatched = namingModel.hatch()!
        precondition(namingModel.state.collection.names[hatched.rawValue] == hatched.defaultName, "A hatch must start with its default name")
        precondition(namingModel.state.companion?.kind == a.kind, "Hatching must keep the preferred profile Dot until the user chooses")
        precondition(namingModel.nameCreature(hatched, pet: "  Coconutty  "))
        precondition(namingModel.state.companion?.petName == a.petName, "Naming a new pet must not rename the existing profile Dot")
        namingModel.activate(a.kind)
        precondition(namingModel.state.companion?.petName == a.petName, "Each owned creature keeps its own name")
        let locked = namingModel.state.collection.unowned.first!
        namingModel.activate(locked)
        precondition(namingModel.state.companion?.kind == a.kind, "Locked creatures cannot be selected as the profile Dot")
        namingModel.activate(hatched)
        precondition(namingModel.state.companion?.kind == hatched, "The chosen owned creature becomes the profile and shared Dot")
        precondition(namingModel.state.companion?.mood == a.mood, "Selecting a profile Dot must preserve the chosen mood")
        precondition(namingModel.state.companion?.petName == "Coconutty", "The hatch name must survive switching companions")
        let savedNames = try namingStore.load().collection.names
        precondition(savedNames[hatched.rawValue] == "Coconutty", "Names must persist")
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        oldJSON.removeValue(forKey: "collection")
        let migrated = try JSONDecoder().decode(CircleState.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        precondition(migrated.collection.owned == [a.kind], "An existing companion must remain owned after the update")
        precondition(migrated.collection.names[a.kind.rawValue] == a.petName, "The existing companion name must migrate too")
        let iso = ISO8601DateFormatter()
        let zone = TimeZone(identifier: "Europe/London")!
        precondition(CheckInDay.number(iso.date(from: "2026-03-29T11:00:00Z")!, timeZone: zone) -
                     CheckInDay.number(iso.date(from: "2026-03-28T12:00:00Z")!, timeZone: zone) == 1,
                     "The daylight-saving change must count as one calendar day")
        let budget = MemoryRestoreBudget(); try budget.record(3)
        let withBudget = CircleModel(store: CircleStore(root: root.appendingPathComponent("restores")), restoreBudget: budget)
        precondition(withBudget.state.collection.restoresRemaining == 0, "A fresh companion must retain the lifetime restore receipt")
        CompanionArt.directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        for kind in CompanionKind.allCases {
            for mood in Mood.allCases {
                guard let image = CompanionArt.image(mood, kind: kind), let cg = image.cgImage else { fatalError("Missing \(kind) \(mood)") }
                precondition(cg.width == 512 && cg.height == 512, "Atlas cells must be 512px")
                let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: 512 * 512 * 4)
                raw.initialize(repeating: 0, count: 512 * 512 * 4)
                defer { raw.deallocate() }
                guard let context = CGContext(data: raw, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Could not inspect pixels") }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
                precondition(raw[3] <= 5, "Sprite corners must be transparent within 2 percent alpha: \(kind.rawValue)/\(mood.rawValue)")
                precondition(raw[(256 * 512 + 256) * 4 + 3] > 240, "Sprites must have a visible body")
                print("artwork \(kind.rawValue)/\(mood.rawValue) corner alpha \(raw[3])")
            }
        }
        print("Behavior, persistence, streak rewards, three lifetime restores and all \(CompanionKind.allCases.count * Mood.allCases.count) mood sprites passed")
    }
}

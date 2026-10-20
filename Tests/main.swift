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
        CompanionArt.directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        for kind in CompanionKind.allCases {
            for mood in Mood.allCases {
                guard let image = CompanionArt.image(mood, kind: kind), let cg = image.cgImage else { fatalError("Missing \(kind) \(mood)") }
                precondition(cg.width == 512 && cg.height == 512, "Atlas cells must be 512px")
                let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: 512 * 512 * 4)
                defer { raw.deallocate() }
                guard let context = CGContext(data: raw, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Could not inspect pixels") }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
                precondition(raw[3] == 0, "Sprites must retain transparent corners")
                precondition(raw[(256 * 512 + 256) * 4 + 3] > 240, "Sprites must have a visible body")
                print("artwork \(kind.rawValue)/\(mood.rawValue) corner alpha \(raw[3])")
            }
        }
        print("Behavior, storage and all 18 mood sprites passed")
    }
}

import Foundation
import SwiftUI
import UIKit
import CloudKit

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
        precondition(progress.displayOrder.first == .pillow, "Owned creatures must appear before locked creatures")
        precondition(Set(progress.displayOrder) == Set(CompanionKind.allCases) && progress.displayOrder.count == 29,
                     "Collection ordering must preserve every creature exactly once")
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
        var quiet = CollectionProgress()
        quiet.owned = [.lavender]
        for day in 1...4 { quiet.checkInQuietly(on: day) }
        quiet.checkInQuietly(on: 7); quiet.checkInQuietly(on: 8)
        precondition(quiet.streak == 2 && quiet.totalDays == 6 && quiet.restoresUsed == 0,
                     "Quiet check-ins must count immediately without consuming a restore")
        quiet.checkInQuietly(on: 8)
        precondition(quiet.totalDays == 6 && quiet.canRestoreCurrentStreak(on: 8))
        precondition(quiet.restoreCurrentStreak(on: 8))
        precondition(quiet.streak == 6 && quiet.totalDays == 6 && quiet.restoresUsed == 1 && quiet.eggs == [5],
                     "An explicit restore counts only actual days and catches up milestone rewards")
        precondition(!quiet.restoreCurrentStreak(on: 8), "A restore cannot be spent twice")
        quiet.checkInQuietly(on: 11); quiet.checkInQuietly(on: 14)
        precondition(quiet.restorableStreak == 1 && quiet.streak == 1,
                     "A new gap replaces the previous restore opportunity")
        quiet.restoresUsed = 3
        precondition(!quiet.restoreCurrentStreak(on: 14), "Quiet check-ins retain the lifetime limit")
        var quietState = CircleState(companion: a)
        quietState.collection.owned = [.lavender]
        quietState.collection.lastCheckInDay = CheckInDay.number(Date()) - 3
        quietState.collection.streak = 4
        let quietModel = CircleModel(previewState: quietState)
        quietModel.setMood(.calm)
        precondition(!quietModel.showRestore && quietModel.state.collection.streak == 1,
                     "Setting a mood must never open a streak reminder")
        let legacyStore = CircleStore(root: root.appendingPathComponent("pending-restore"))
        var legacy = quietState
        legacy.collection.pendingCheckInDay = CheckInDay.number(Date())
        try legacyStore.save(legacy)
        let migratedCheckIn = CircleModel(store: legacyStore)
        precondition(!migratedCheckIn.showRestore && migratedCheckIn.state.collection.pendingCheckInDay == nil,
                     "A saved restore prompt must not reopen after updating")
        precondition(migratedCheckIn.state.collection.streak == 1 && migratedCheckIn.state.collection.restorableStreak == 4
                     && migratedCheckIn.state.collection.totalDays == 1 && migratedCheckIn.state.collection.restoresUsed == 0,
                     "Migrate a pending check-in without losing the day or spending a restore")
        let savedMigration = try legacyStore.load()
        precondition(savedMigration.collection == migratedCheckIn.state.collection)
        let technicalError = CKError(.serverRejectedRequest, userInfo: [NSLocalizedDescriptionKey: "Cannot create new type Companion in production schema CKRecordID secret"])
        let message = CircleSyncMessage.text(for: technicalError)
        precondition(!message.contains("CKRecord") && !message.contains("schema") && !message.contains("secret"),
                     "Server diagnostics must never appear in user-facing sync messages")
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
        var motion = SpritePlayback(count: 7)
        motion.play(CompanionMotion.rub, interval: CompanionMotion.rubInterval, repeats: true, at: 10)
        var previous = motion.weights(at: 10)
        for tick in 1...240 {
            let weights = motion.weights(at: 10 + Double(tick) / 60)
            precondition(abs(weights.reduce(0, +) - 1) < 1e-9 && weights.allSatisfy { $0 >= 0 && $0 <= 1 },
                         "A blend must retain full opacity without overshoot")
            precondition(zip(previous, weights).map { abs($0 - $1) }.max()! < 0.28,
                         "Each display sample must advance smoothly, including the loop seam")
            precondition(previous != weights, "Petting must not hold on a still drawing between display samples")
            previous = weights
        }
        let interrupted = motion.weights(at: 10.537)
        motion.play([0], interval: 0.24, at: 10.537)
        precondition(motion.weights(at: 10.537) == interrupted, "Lifting a finger must start from the visible blend")
        precondition(motion.weights(at: 11) == [1, 0, 0, 0, 0, 0, 0] && !motion.isMoving(at: 11),
                     "Settling must return to rest and stop display updates")
        motion.play(CompanionMotion.tap, interval: CompanionMotion.tapInterval, at: 12)
        let tappedAgain = motion.weights(at: 12.137)
        motion.play(CompanionMotion.tap, interval: CompanionMotion.tapInterval, at: 12.137)
        precondition(motion.weights(at: 12.137) == tappedAgain, "Rapid taps must not reset to the resting image")
        precondition(!motion.isMoving(at: 13), "A tap must finish without an idle animation timer")
        func solid(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        }
        let blend = ImageRenderer(content: SpriteCanvas(images: [solid(.red), solid(.blue)], weights: [0.5, 0.5]).frame(width: 16, height: 16))
        blend.scale = 1
        guard let mixed = blend.uiImage?.cgImage else { fatalError("Blend renderer must produce pixels") }
        var rgba = [UInt8](repeating: 0, count: 16 * 16 * 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(mixed, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let pixel = (8 * 16 + 8) * 4
        precondition(rgba[pixel + 3] >= 254 && abs(Int(rgba[pixel]) - Int(rgba[pixel + 2])) < 3,
                     "Mid-transition artwork must remain opaque with balanced colors")
        print("Continuous 60 Hz sampling, loop seams, release, rapid taps, idle stopping and rendered blend alpha passed")
        var ritual = HatchRitual()
        precondition(ritual.stage == .sleeping)
        ritual.warm(.nan); ritual.warm(-1)
        precondition(ritual.warmth == 0, "Invalid warmth cannot advance an egg")
        for _ in 0..<4 { precondition(!ritual.tap(), "Warming taps cannot spend an egg") }
        precondition(ritual.ready && ritual.cracks == 0)
        precondition(!ritual.tap() && ritual.stage == .firstCrack)
        precondition(!ritual.tap() && ritual.stage == .secondCrack)
        precondition(ritual.tap() && ritual.isOpening, "Only the third crack starts the reveal")
        for _ in 0..<20 { precondition(!ritual.tap(), "Repeated taps during the reveal cannot spend another egg") }
        precondition(ritual.cracks == 3)
        ritual.retryOpening()
        precondition(!ritual.isOpening && ritual.cracks == 2 && ritual.tap(), "A failed save must allow a retry")
        CompanionArt.directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        precondition(DotlingAnimation.allCases.reduce(0) { $0 + $1.durations.count } == 73)
        for motion in DotlingAnimation.allCases {
            for index in motion.durations.indices {
                guard let image = CompanionArt.motionImage(motion, frame: index)?.cgImage else {
                    fatalError("Missing Dusk movement frame")
                }
                precondition(image.width == 384 && image.height == 416)
            }
            precondition(CompanionArt.motionImage(motion, frame: -1) == nil)
            precondition(CompanionArt.motionImage(motion, frame: motion.durations.count) == nil)
            for mood in Mood.allCases {
                let rest: DotlingPose = mood == .happy ? .frame(.idle, 0) : .rest(mood)
                precondition(DotlingAnimation.pose(for: nil, mood: mood, elapsed: 0, reducedMotion: false) == rest)
                for elapsed in [0.0, motion.duration / 2, motion.duration - 0.001] {
                    precondition(DotlingAnimation.pose(for: motion, mood: mood, elapsed: elapsed, reducedMotion: false)
                                 == .frame(motion, motion.frame(at: elapsed)), "Every mood can play every action")
                }
                precondition(DotlingAnimation.pose(for: motion, mood: mood, elapsed: motion.duration, reducedMotion: false) == rest,
                             "Completed actions, including Blink, restore the chosen mood")
                precondition(DotlingAnimation.pose(for: motion, mood: mood, elapsed: 0.5, petting: true, reducedMotion: false)
                             == .frame(.idle, 3), "Petting works in every mood")
                precondition(DotlingAnimation.pose(for: motion, mood: mood, elapsed: 0.5, petting: true, reducedMotion: true) == rest,
                             "Reduce Motion preserves the selected mood without movement")
            }
        }
        precondition(DotlingAnimation.idle.frame(at: 1.8) == 2, "Blink timing must reach the half-closed eyes")
        for kind in CompanionKind.allCases {
            for action in DotlingAnimation.allCases {
                let images = CompanionArt.motionFrames(action, kind: kind)
                precondition(images.count == action.durations.count, "Every companion must support every action: \(kind)/\(action)")
                for image in images {
                    guard let cg = image.cgImage else { fatalError("Undecodable animation frame") }
                    precondition(cg.width == 384 && cg.height == 416)
                }
            }
        }
        print("All 2,117 collection animation frames decoded")

        print("All 10 actions across 6 moods, return to selected mood, petting and reduced motion passed")
        let duskRest = CompanionArt.image(.happy, kind: .dusk)!
        precondition(duskRest.pngData() == CompanionArt.touchImage(0, kind: .dusk)?.pngData(),
                     "Dusk's resting and first action drawings must use the same registered artwork")
        precondition(CompanionMotion.blink(rubbed: true, held: true, reducedMotion: false).last == 4,
                     "Petting the new strip must hold the closed eyes rather than replay a full blink")
        precondition(CompanionMotion.blink(rubbed: false, held: false, reducedMotion: true) == [0],
                     "Reduce Motion must leave the new strip still")
        var duskBlink = SpritePlayback(count: 7)
        duskBlink.play(CompanionMotion.blink(rubbed: true, held: true, reducedMotion: false), interval: 0.14, at: 0)
        precondition(duskBlink.weights(at: 1)[4] == 1 && !duskBlink.isMoving(at: 1))
        let held = duskBlink.weights(at: 1)
        duskBlink.play([0], interval: 0.24, at: 1)
        precondition(duskBlink.weights(at: 1) == held && duskBlink.weights(at: 1.3)[0] == 1,
                     "Releasing Dusk must blend from closed eyes to the selected rest frame")
        for mood in Mood.allCases {
            for frame in 0..<6 {
                precondition(CompanionArt.touchImage(frame, kind: .dusk, mood: mood) != nil,
                             "Every Dusk mood must retain its own supported touch sequence")
            }
        }
        for stage in EggStage.allCases {
            guard let cg = CompanionArt.eggImage(stage)?.cgImage else { fatalError("Missing egg frame \(stage)") }
            precondition(cg.width == 512 && cg.height == 512, "Egg frames must keep a fixed canvas")
            let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: 512 * 512 * 4)
            raw.initialize(repeating: 0, count: 512 * 512 * 4)
            defer { raw.deallocate() }
            let context = CGContext(data: raw, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
            for corner in [0, 511, 511 * 512, 512 * 512 - 1] { precondition(raw[corner * 4 + 3] <= 5, "Egg corners must be transparent") }
            precondition((0..<(512 * 512)).filter { raw[$0 * 4 + 3] > 200 }.count > 10000, "Each egg stage must contain visible artwork")
        }
        print("Egg warming, three-tap reveal, repeat-tap protection and all 12 egg images passed")
        precondition(CompanionTouchLayout.frames.count == CompanionKind.allCases.count, "Every pet needs aligned touch artwork")
        for kind in CompanionKind.allCases {
            guard let layout = CompanionTouchLayout.frames[kind.touchAsset] else { fatalError("Missing touch layout") }
            precondition(layout.count == 6 && Set(layout.map { $0[6] }).count == 1,
                         "All six drawings must use one uniform scale without per-frame stretching")
            for frame in layout {
                precondition(frame.count == 7 && frame[0] >= 0 && frame[1] >= 0 && frame[2] > 0 && frame[3] > 0 &&
                             frame[0] + frame[2] <= 1536 && frame[1] + frame[3] <= 1024 && frame[6] > 0,
                             "Touch crops must remain inside the atlas")
            }
            let frames = Mood.allCases.map { ($0.rawValue, CompanionArt.image($0, kind: kind)) }
                + (0..<6).map { ("touch-\($0)", CompanionArt.touchImage($0, kind: kind)) }
            precondition(CompanionArt.touchImage(-1, kind: kind) == nil && CompanionArt.touchImage(6, kind: kind) == nil,
                         "Invalid touch frames must not crop another cell")
            for (name, image) in frames {
                guard let cg = image?.cgImage else { fatalError("Missing \(kind) \(name)") }
                precondition(cg.width == 512 && cg.height == 512, "Atlas cells must be 512px")
                let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: 512 * 512 * 4)
                raw.initialize(repeating: 0, count: 512 * 512 * 4)
                defer { raw.deallocate() }
                guard let context = CGContext(data: raw, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Could not inspect pixels") }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 512))
                for corner in [0, 511, 511 * 512, 512 * 512 - 1] {
                    precondition(raw[corner * 4 + 3] <= 5, "Sprite corners must be transparent within 2 percent alpha: \(kind.rawValue)/\(name)")
                }
                precondition(raw[(256 * 512 + 256) * 4 + 3] > 240, "Sprites must have a visible body")
                print("artwork \(kind.rawValue)/\(name) corner alpha \(raw[3])")
            }
        }
        print("Behavior, persistence, streak rewards, three lifetime restores and all \(CompanionKind.allCases.count * (Mood.allCases.count + 6)) mood and touch sprites passed")
    }
}

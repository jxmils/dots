import Foundation
import SwiftUI
import UIKit
import CloudKit

private final class TestPetRecovery: PetRecovery {
    var archive: PetArchive?
    func read() throws -> PetArchive? { archive }
    func write(_ value: PetArchive) throws { archive = value }
    func clear() throws { archive = nil }
}

private final class TestCircleKeys: CircleKeys {
    var values: [String: [String: CircleRoute]] = [:]
    func routes(_ account: String) throws -> [String: CircleRoute] { values[account] ?? [:] }
    func save(_ routes: [String: CircleRoute], account: String) throws { values[account] = routes }
}

@MainActor private final class TestCircleDatabase {
    var records: [String: CircleSlot] = [:]
    var now = Date()
}

@MainActor private struct TestCircleTransport: CircleTransport {
    let id: String
    let db: TestCircleDatabase
    func account() async throws -> String { id }
    func fetch(_ name: String) async throws -> CircleSlot? { db.records[name] }
    func write(_ content: CircleEnvelope, name: String, replacing prior: CircleSlot?) async throws {
        let old = db.records[name]
        if let old {
            guard old.creator == id, let prior, old.record === prior.record else { throw LinkError.denied }
        } else if prior != nil { throw LinkError.denied }
        db.records[name] = CircleSlot(content: content, creator: id, created: old?.created ?? db.now,
                                      record: CKRecord(recordType: "DotlingFriendSlot"))
    }
}

@MainActor private func checkMutualInvitations(_ a: Companion, _ b: Companion) async throws {
    let db = TestCircleDatabase()
    func client(_ id: String) -> FriendLinks {
        FriendLinks(transport: TestCircleTransport(id: id, db: db), keys: TestCircleKeys())
    }
    let alice = client("alice"), bob = client("bob"), chris = client("chris")
    let invite = try await alice.invite(a)
    precondition(FriendInvite(url: invite.url)?.id == invite.id)
    do { try await alice.accept(invite, companion: a); preconditionFailure("Self invite accepted") }
    catch LinkError.selfInvite {}
    try await bob.accept(invite, companion: b)
    try await bob.accept(invite, companion: b)
    do { try await chris.accept(invite, companion: b); preconditionFailure("Forwarded invite reused") }
    catch LinkError.denied {}
    let firstA = try await alice.friends(), firstB = try await bob.friends()
    precondition(firstA.map(\.mood) == [b.mood] && firstB.map(\.mood) == [a.mood])
    var newA = a, newB = b
    newA.mood = .studious; newA.updatedAt = Date()
    newB.mood = .sick; newB.updatedAt = Date()
    try await alice.publish(newA)
    try await bob.publish(newB)
    let changedA = try await alice.friends(), changedB = try await bob.friends()
    precondition(changedA.map(\.mood) == [.sick] && changedB.map(\.mood) == [.studious])
    precondition(db.records.values.allSatisfy { $0.content.mood != nil && $0.content.preview == nil })
    let alicePasses = try await alice.sent()
    precondition(alicePasses.first?.accepted == true)
    try await bob.leave(changedB[0])
    let remainingA = try await alice.friends(), remainingB = try await bob.friends()
    precondition(remainingA.isEmpty && remainingB.isEmpty)
    do { try await chris.accept(invite, companion: b); preconditionFailure("Cancelled invite reused") }
    catch LinkError.denied {}
    db.now = Date().addingTimeInterval(-8 * 86400)
    let expired = try await alice.invite(a)
    do { try await chris.accept(expired, companion: b); preconditionFailure("Expired invite accepted") }
    catch LinkError.denied {}
    db.now = Date()
    let pending = try await alice.invite(a)
    let passes = try await alice.sent()
    try await alice.revoke(passes.first { $0.id == pending.id }!)
    do { try await chris.accept(pending, companion: b); preconditionFailure("Revoked invite accepted") }
    catch LinkError.denied {}
    print("Mutual iCloud invitation behavior passed with three simulated accounts")
}

@main struct Checks {
    @MainActor static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_792_540_000)
        let a = Companion(id: "a", ownerName: "Alex", petName: "Mochi", mood: .calm, updatedAt: now)
        let b = Companion(id: "b", ownerName: "Sam", petName: "Pip", mood: .happy, updatedAt: now.addingTimeInterval(600), kind: .pillow)
        try await checkMutualInvitations(a,b)
        var state = CircleState(companion: a, friends: [a, b])
        precondition(state.widgetFriend()?.id == "b", "Latest must select the newest mood")
        state.pinnedFriendID = "a"; state.widgetMode = .pinned
        precondition(state.widgetFriend()?.id == "a", "Pin must override chronology")
        precondition(state.widgetFriend(mode: .latest)?.id == "b", "Explicit latest must override the app setting")
        precondition(state.widgetFriend(friendID: "missing") == nil, "Missing friend must never silently become another person")
        state.removeFriend("a")
        precondition(state.pinnedFriendID == nil && state.widgetFriend() == nil, "Removing a pinned friend must clear the widget")
        var arranged = CircleState(companion: a, friends: [a, b])
        arranged.arrangeFriends(["a", "a", "unknown", "b"])
        precondition(arranged.sortedFriends.map(\.id) == ["a", "b"])
        precondition(arranged.friendOrder == ["a", "b"], "Ignore duplicates and unknown IDs")
        precondition(arranged.widgetFriend(mode: .latest)?.id == "b", "Circle order must not change the latest widget")
        var updatedB = b
        updatedB.updatedAt = now.addingTimeInterval(1200)
        let newcomer = Companion(id: "c", ownerName: "Mia", petName: "Leaf", mood: .sad, updatedAt: now.addingTimeInterval(1800))
        arranged.receiveFriends([newcomer, updatedB, a], at: now)
        precondition(arranged.sortedFriends.map(\.id) == ["a", "b", "c"], "Refresh preserves chosen order and appends newcomers")
        precondition(arranged.widgetFriend(mode: .latest)?.id == "c")
        precondition(arranged.friendOrder == ["a", "b", "c"], "Append newcomers to the saved arrangement")
        var latestA = a
        latestA.updatedAt = now.addingTimeInterval(2400)
        arranged.receiveFriends([updatedB, newcomer, latestA], at: now)
        precondition(arranged.sortedFriends.map(\.id) == ["a", "b", "c"])
        precondition(arranged.widgetFriend(mode: .latest)?.id == "a")
        precondition(arranged.friendOrder(moving: "a", relativeTo: "c", after: true) == ["b", "c", "a"])
        precondition(arranged.friendOrder(moving: "c", relativeTo: "a", after: false) == ["c", "a", "b"])
        precondition(arranged.friendOrder(moving: "a", relativeTo: "c", after: false) == ["b", "a", "c"])
        precondition(arranged.friendOrder(moving: "c", relativeTo: "a", after: true) == ["a", "c", "b"])
        precondition(arranged.friendOrder(moving: "a", relativeTo: "a", after: true) == nil)
        precondition(arranged.friendOrder(moving: "removed", relativeTo: "a", after: true) == nil)
        precondition(arranged.friendOrder(moving: "a", relativeTo: "removed", after: true) == nil)
        precondition(arranged.sortedFriends.map(\.id) == ["a", "b", "c"], "Previewing or cancelling must not change order")
        let roundtrip = try JSONDecoder().decode(CircleState.self, from: JSONEncoder().encode(arranged))
        precondition(roundtrip == arranged, "Arrangement survives relaunch")
        arranged.removeFriend("a")
        precondition(arranged.sortedFriends.map(\.id) == ["b", "c"] && !arranged.friendOrder.contains("a"))
        arranged.receiveFriends([newcomer], at: now)
        precondition(arranged.sortedFriends.map(\.id) == ["c"] && !arranged.friendOrder.contains("b"))
        let legacyOrder = try JSONDecoder().decode(CircleState.self, from: Data("{}".utf8))
        precondition(legacyOrder.friendOrder.isEmpty, "Existing saved circles migrate without reset")
        for kind in CompanionKind.allCases {
            let reaction = DotlingSignature.reaction(for: kind)
            precondition(reaction.phase(at: 0) == 0 && reaction.phase(at: reaction.duration) == 0)
            for sample in 0...120 {
                let time = Double(sample) / 120 * reaction.duration
                precondition(abs(reaction.phase(at: time)) <= 1)
                precondition(reaction.phase(at: time, reducedMotion: true) == 0)
            }
            precondition(abs(reaction.phase(at: 0.001)) < 0.00001
                         && abs(reaction.phase(at: reaction.duration - 0.001)) < 0.00001,
                         "Reactions ease in and out without snapping")
        }
        print("Circle arrangement persistence, refresh, migration, latest-widget isolation and 29 reaction boundaries passed")
        var localTest = CircleState(companion: a, friends: [b])
        precondition(localTest.testFriendStartedAt == nil && !localTest.updateTestFriend(at: now))
        precondition(TestFriend.interval == 5)
        let originalCollection = localTest.collection
        localTest.enableTestFriend(at: now)
        localTest.enableTestFriend(at: now.addingTimeInterval(10))
        precondition(localTest.testFriendStartedAt == now && localTest.friends.count == 2)
        precondition(!localTest.updateTestFriend(at: now.addingTimeInterval(4.999)))
        for (index, mood) in Mood.allCases.enumerated() {
            localTest.updateTestFriend(at: now.addingTimeInterval(Double(index) * 5))
            precondition(localTest.friends.first { $0.id == TestFriend.id }?.mood == mood)
        }
        let cycle = Double(Mood.allCases.count) * TestFriend.interval
        localTest.updateTestFriend(at: now.addingTimeInterval(cycle))
        precondition(localTest.friends.first { $0.id == TestFriend.id }?.mood == .happy)
        localTest.pinnedFriendID = TestFriend.id
        localTest.receiveFriends([b], at: now.addingTimeInterval(cycle + TestFriend.interval))
        precondition(localTest.widgetFriend(friendID: TestFriend.id)?.mood == .calm && localTest.pinnedFriendID == TestFriend.id,
                     "Cloud refresh must retain the local test friend and its pin")
        precondition(localTest.companion == a && localTest.collection == originalCollection && !localTest.cloudEnabled,
                     "Test moods must never change the user's mood, rewards or cloud sharing")
        var decodedTest = try JSONDecoder().decode(CircleState.self, from: JSONEncoder().encode(localTest))
        precondition(decodedTest == localTest, "The local opt-in must survive relaunch")
        decodedTest.updateTestFriend(at: now.addingTimeInterval(3600 + 15))
        precondition(decodedTest.friends.first { $0.id == TestFriend.id }?.mood == .sad,
                     "After a suspension, use elapsed time rather than replaying missed ticks")
        decodedTest.removeFriend(TestFriend.id)
        decodedTest.receiveFriends([b], at: now.addingTimeInterval(4000))
        precondition(decodedTest.testFriendStartedAt == nil && decodedTest.pinnedFriendID == nil && decodedTest.friends == [b],
                     "Removing the test friend must clear its pin and stop future cycles")
        var alerts = CircleState(friends: [a, b])
        alerts.enableMoodAlerts()
        var active = b
        active.mood = .workingOut
        active.updatedAt = b.updatedAt.addingTimeInterval(10)
        precondition(alerts.moodChanges(in: [a, active], fromLinks: false) == [active])
        precondition(alerts.moodChanges(in: [a, active], fromLinks: false).isEmpty)
        precondition(alerts.moodChanges(in: [a, b], fromLinks: false).isEmpty)
        active.petName = "New name"
        active.updatedAt.addTimeInterval(5)
        precondition(alerts.moodChanges(in: [a, active], fromLinks: false).isEmpty)
        alerts.alertHistory = nil
        precondition(alerts.moodChanges(in: [a, b], fromLinks: false).isEmpty)
        var mixed = CircleState()
        var linked = a
        linked.id = "friend:test-link"
        for firstIsLink in [false, true] {
            mixed.receiveFriends(firstIsLink ? [linked] : [b], fromLinks: firstIsLink, at: now)
            mixed.receiveFriends(firstIsLink ? [b] : [linked], fromLinks: !firstIsLink, at: now)
            precondition(Set(mixed.friends.map(\.id)) == [b.id, linked.id])
            mixed.pinnedFriendID = linked.id
            mixed.receiveFriends([], fromLinks: false, at: now)
            precondition(mixed.friends == [linked] && mixed.pinnedFriendID == linked.id)
            mixed.receiveFriends([b], fromLinks: false, at: now)
            mixed.receiveFriends([], fromLinks: true, at: now)
            precondition(mixed.friends == [b] && mixed.pinnedFriendID == nil)
        }
        let oldState = try JSONDecoder().decode(CircleState.self, from: Data("{}".utf8))
        precondition(oldState.testFriendStartedAt == nil && oldState.friends.isEmpty)
        print("Local test friend: opt-in, 5-second moods, wraparound, resume, cloud merge, persistence and removal passed")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CircleStore(root: root)
        try store.save(state)
        let restored = try store.load()
        precondition(restored == state, "Save/load must retain the complete circle")
        try Data("invalid".utf8).write(to: store.url)
        do { _ = try store.load(); fatalError("Corrupt storage must be reported") } catch {}
        let recovery = TestPetRecovery()
        let reinstallStore = CircleStore(root: root.appendingPathComponent("reinstall"))
        var installedState = CircleState(companion: a, friends: [b])
        installedState.collection.owned.append(.coffee)
        installedState.collection.names[CompanionKind.coffee.rawValue] = "Bean"
        installedState.collection.eggs = [5]
        try reinstallStore.save(installedState)
        let upgradedModel = CircleModel(store: reinstallStore, petRecovery: recovery)
        upgradedModel.activate(.coffee)
        precondition(upgradedModel.nameCreature(.coffee, pet: "Espresso"))
        try FileManager.default.removeItem(at: reinstallStore.url)
        let reinstalled = CircleModel(store: reinstallStore, petRecovery: recovery)
        precondition(reinstalled.state.companion == upgradedModel.state.companion)
        precondition(reinstalled.state.collection == upgradedModel.state.collection && reinstalled.state.friends.isEmpty)
        await reinstalled.deleteCompanion()
        precondition(recovery.archive == nil)
        try FileManager.default.removeItem(at: reinstallStore.url)
        let cleanInstall = CircleModel(store: reinstallStore, petRecovery: recovery)
        precondition(cleanInstall.state.companion == nil)
        print("Existing pets migrated, selected pet and collection recovered after app data removal, explicit deletion respected")
        let quota = CKError(.quotaExceeded)
        let batch = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["pet": quota]])
        for failure in [quota, batch] {
            precondition(CircleSyncMessage.text(for: failure).contains("iCloud storage is full"))
        }
        let dragStore = CircleStore(root: root.appendingPathComponent("drag-order"))
        try dragStore.save(roundtrip)
        let dragModel = CircleModel(store: dragStore)
        precondition(dragModel.moveFriend("c", relativeTo: "a", after: false))
        let savedDragOrder = try dragStore.load().sortedFriends.map(\.id)
        precondition(savedDragOrder == ["c", "a", "b"])
        precondition(!dragModel.moveFriend("removed", relativeTo: "a", after: false))
        precondition(dragModel.state.widgetFriend(mode: .latest)?.id == "a", "Dragging must not alter latest-mood widgets")
        dragModel.setWidget(.pinned, pinned: "c")
        dragModel.setWidget(.latest, pinned: nil)
        let unpinned = try dragStore.load()
        precondition(unpinned.pinnedFriendID == nil && unpinned.widgetFriend()?.id == "a")
        precondition(unpinned.sortedFriends.map(\.id) == savedDragOrder)
        let modelStore = CircleStore(root: root.appendingPathComponent("model"))
        let model = CircleModel(store: modelStore)
        model.adopt(owner: " Jason ", name: " Cloud ", kind: .pillow)
        precondition(model.state.companion?.ownerName == "Jason" && model.state.companion?.petName == "Cloud")
        model.setMood(.sleepy)
        let earnedBeforePurchase = model.state.collection
        model.applyCollectionAccess(true)
        precondition(model.availableCollection.owned.count == 29 && model.state.collection == earnedBeforePurchase)
        model.activate(.coffee)
        let paidSelection = try modelStore.load()
        precondition(paidSelection.companion?.kind == .coffee && !paidSelection.collection.owned.contains(.coffee))
        precondition(PetArchive(paidSelection)?.restoredState.collection.owned == earnedBeforePurchase.owned)
        model.applyCollectionAccess(false)
        precondition(model.state.companion?.kind == .pillow && model.state.collection.owned == earnedBeforePurchase.owned)
        precondition(model.availableCollection.earnedMilestones == earnedBeforePurchase.earnedMilestones)
        print("Collection purchase, paid pet selection, reinstall recovery and refund preserve earned pets and streaks")
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
        var ownerCollection = progress
        ownerCollection.names[CompanionKind.pillow.rawValue] = "Cloud"
        ownerCollection.completeCollection()
        precondition(ownerCollection.isComplete && ownerCollection.eggs.isEmpty)
        precondition(ownerCollection.names[CompanionKind.pillow.rawValue] == "Cloud")
        precondition(ownerCollection.earnedMilestones == progress.earnedMilestones
                     && ownerCollection.streak == progress.streak
                     && ownerCollection.restoresUsed == progress.restoresUsed,
                     "Completing the collection must not add streak credit or spend a restore")
        for day in 20...24 { ownerCollection.checkIn(on: day) }
        precondition(ownerCollection.earnedMilestones.contains(10) && ownerCollection.eggs.isEmpty,
                     "A full collection still records later milestones without adding an egg")
        let wrongCode = CircleModel(previewState: quietState)
        precondition(!wrongCode.addTestFriend(ownerCode: "invalid") && wrongCode.state == quietState)
        precondition(!wrongCode.unlockOwnerCollection(code: "invalid") && wrongCode.state == quietState)
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
        print("Continuous 60 Hz sampling, loop seams, release, rapid taps and idle stopping passed")
        if ProcessInfo.processInfo.environment["DOTLINGS_HEADLESS"] == "1" {
            print("SKIPPED: SwiftUI GPU blend render on headless host; run full local visual checks separately")
        } else {
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
            print("Rendered blend alpha passed")
        }
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
        for kind in CompanionKind.allCases {
            let anchor = CompanionArt.motionImage(.idle, frame: 0, kind: kind)!
            let target = CompanionArt.opaqueBounds(anchor)!
            for mood in Mood.allCases {
                guard let portrait = CompanionArt.displayImage(mood, kind: kind),
                      let bounds = CompanionArt.opaqueBounds(portrait) else { fatalError("Missing registered mood") }
                precondition(portrait.size == anchor.size, "Rest and motion must share a canvas")
                precondition(abs(bounds.maxY - target.maxY) <= 2,
                             "Rest and motion must share a baseline: \(kind)/\(mood): \(bounds) vs \(target)")
                precondition(bounds.width <= target.width + 2 && bounds.height <= target.height + 2,
                             "Resting moods must not grow beyond Happy: \(kind)/\(mood)")
                precondition(min(abs(bounds.width - target.width), abs(bounds.height - target.height)) <= 2,
                             "Resting moods must fit Happy without arbitrary shrinking: \(kind)/\(mood): \(bounds) vs \(target)")
                precondition(abs(bounds.midX - target.midX) <= 2, "Mood changes must not shift sideways")
                if mood == .happy {
                    precondition(portrait.pngData() == anchor.pngData(), "Happy must remain pixel-identical to its approved anchor")
                }
            }
        }
        print("All mood portraits match the Happy canvas, envelope, center and resting baseline")
        precondition(DotlingAnimation.allCases.reduce(0) { $0 + $1.durations.count } == 73)
        precondition(DotlingAnimation.swipe(translation: CGSize(width: -65, height: 5)) == .moveLeft)
        precondition(DotlingAnimation.swipe(translation: CGSize(width: 45, height: -8)) == .moveRight)
        precondition(DotlingAnimation.swipe(translation: CGSize(width: 45, height: 60)) == nil)
        precondition(DotlingAnimation.swipe(translation: CGSize(width: 8, height: 0)) == nil)
        precondition(DotlingAnimation.idle.frame(at: DotlingAnimation.blinkStart) == 2)
        precondition(DotlingAnimation.idle.frame(at: DotlingAnimation.blinkStart + 0.08) == 3)
        precondition(DotlingAnimation.blinkDuration < 0.3)
        precondition(DotlingAnimation.automaticInterval == 6_000_000_000)
        precondition(Set(DotlingAnimation.automaticChoices(after: nil)) == Set(DotlingAnimation.allCases),
                     "Automatic emotes must include every available movement")
        for previous in DotlingAnimation.allCases {
            let choices = DotlingAnimation.automaticChoices(after: previous)
            precondition(!choices.contains(previous) && choices.count == DotlingAnimation.allCases.count - 1,
                         "Random emotes must vary without excluding any other movement")
        }
        for kind in CompanionKind.allCases {
            for mood in [Mood.sick, .studious, .workingOut] {
                for action in DotlingAnimation.allCases {
                    autoreleasepool {
                        let frames = CompanionArt.motionFrames(action, kind: kind, mood: mood)
                        precondition(frames.count == action.durations.count,
                                     "Missing illustrated frames for \(kind)/\(mood)/\(action)")
                        precondition(frames.allSatisfy { $0.size == CGSize(width: 384, height: 416) })
                        let painted = Set(frames.compactMap { $0.cgImage.map(ObjectIdentifier.init) })
                        precondition(painted.count >= (action == .lookAround ? 8 : 3),
                                     "Missing distinct poses for \(kind)/\(mood)/\(action)")
                    }
                }
            }
        }
        print("All 870 pet, mood and movement combinations loaded through the native animation player")
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
        let sharedEgg = CompanionArt.eggFrames()
        precondition(sharedEgg.count == 12, "A closed egg must not choose a placeholder pet")
        for stage in EggStage.allCases where stage.needsCompanion {
            precondition(CompanionArt.eggImage(stage) == nil, "An open egg requires its actual awarded Dotling")
        }
        var finalPortraits = Set<Data>()
        var hatchAssets = Set<String>()
        for kind in CompanionKind.allCases {
            autoreleasepool {
                let frames = CompanionArt.eggFrames(kind: kind)
                precondition(frames.count == 24, "Every awarded Dotling needs a complete hatch: \(kind)")
                hatchAssets.insert(EggStage.nest.asset(for: kind)!)
                finalPortraits.insert(frames.last!.pngData()!)
                precondition(frames[11].pngData() == frames[12].pngData(), "The shell must share exact pixels at the opening join")
                precondition(frames[17].pngData() == frames[18].pngData(), "The pet peek must share exact pixels at the reveal join")
                for (index, image) in frames.enumerated() {
                    guard let cg = image.cgImage else { fatalError("Undecodable egg frame") }
                    precondition(cg.width == 512 && cg.height == 600, "Egg frames must keep the approved fixed canvas")
                    var raw = [UInt8](repeating: 0, count: 512 * 600 * 4)
                    raw.withUnsafeMutableBytes { bytes in
                        let context = CGContext(data: bytes.baseAddress, width: 512, height: 600, bitsPerComponent: 8, bytesPerRow: 2048,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                        context.draw(cg, in: CGRect(x: 0, y: 0, width: 512, height: 600))
                    }
                    for corner in [0, 511, 599 * 512, 512 * 600 - 1] { precondition(raw[corner * 4 + 3] <= 5, "Egg corners must be transparent") }
                    precondition((0..<(512 * 600)).filter { raw[$0 * 4 + 3] > 200 }.count > 10000, "Empty hatch pose: \(kind)/\(index)")
                }
            }
        }
        precondition(hatchAssets.count == CompanionKind.allCases.count && finalPortraits.count == CompanionKind.allCases.count,
                     "Every Dotling must have its own reveal, never a shared Lavender placeholder")
        for reduced in [false, true] {
            let sequence = EggStage.ceremony(reduceMotion: reduced)
            precondition(sequence.last?.stage == .nest && sequence.allSatisfy { $0.milliseconds > 0 })
            if reduced { precondition(sequence.count == 2, "Reduce Motion must skip rocking and rising") }
        }
        print("Egg warming, three-tap reveal, repeat-tap protection, exact joins and all 29 character hatches passed")
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

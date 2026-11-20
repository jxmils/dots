import Foundation
import Observation
import CloudKit
import CryptoKit
import WidgetKit
import UIKit

@MainActor @Observable
final class CircleModel {
    private(set) var state: CircleState
    var error: String?
    var syncIssue: String?
    var syncing = false
    var sharing = false
    var deleting = false
    var share: CKShare?
    var outgoingInvite: FriendInvite?
    var incomingInvite: FriendInvite?
    var showSharing = false
    var showSettings = false
    var showWidgetGuide = false
    var showHatch = false
    var showRestore = false
    private(set) var storageAvailable = true
    private let store: CircleStore
    let cloud = CloudCircle()
    private var syncAgain = false
    let preview: Bool
    private let restoreBudget: any RestoreBudget

    private let petRecovery: (any PetRecovery)?
    private var lastArchivedPet: PetArchive?

    init(store: CircleStore = CircleStore(), preview: Bool = false, restoreBudget: (any RestoreBudget)? = nil,
         petRecovery: (any PetRecovery)? = nil) {
        self.store = store
        self.preview = preview
        #if targetEnvironment(macCatalyst)
        self.petRecovery = petRecovery
        self.restoreBudget = restoreBudget ?? MemoryRestoreBudget()
        #else
        self.petRecovery = preview ? nil : (petRecovery ?? DevicePetRecovery())
        self.restoreBudget = restoreBudget ?? KeychainRestoreBudget()
        #endif
        state = CircleState()
        do {
            if let installed = try store.loadIfPresent() {
                state = installed
                if !preview { backUpPet(in: installed) } // Also migrate pets from version 1.0 on launch.
            } else if !preview, let archive = try self.petRecovery?.read() {
                let restored = archive.restoredState
                try store.save(restored)
                state = restored
                lastArchivedPet = archive
            }
        }
        catch {
            state = CircleState(); storageAvailable = false
            self.error = "Your saved circle couldn't be read. Please restart the app before making changes. Your saved data hasn't been replaced."
        }
        if !preview {
            do { state.collection.restoresUsed = max(state.collection.restoresUsed, try self.restoreBudget.used()) }
            catch { self.error = error.localizedDescription }
        }
        if state.testFriendStartedAt != nil {
            if TestFriend.available { state.updateTestFriend(at: Date()) }
            else { state.removeFriend(TestFriend.id) }
            persist()
        }
        if let pending = state.collection.pendingCheckInDay {
            state.collection.checkInQuietly(on: pending)
            state.collection.pendingCheckInDay = nil
            persist()
        }
    }

    init(previewState: CircleState) {
        store = CircleStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        state = previewState
        preview = true
        petRecovery = nil
        restoreBudget = MemoryRestoreBudget()
    }

    private func backUpPet(in state: CircleState) {
        guard let petRecovery, let archive = PetArchive(state), archive != lastArchivedPet else { return }
        do {
            try petRecovery.write(archive)
            lastArchivedPet = archive
        } catch {
            self.error = "Your pet is saved in Dotlings, but its reinstall backup couldn't be updated. Keep the app installed and reopen it after unlocking your iPhone."
        }
    }

    private func saveState(_ value: CircleState) throws {
        try store.save(value)
        backUpPet(in: value)
    }

    private func persist() {
        guard !preview, storageAvailable else { return }
        do { try saveState(state); WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind) }
        catch { self.error = "Your change couldn't be saved. Please try again." }
    }

    func adopt(owner: String, name: String, kind: CompanionKind = .lavender) {
        guard storageAvailable else { return }
        let owner = String(owner.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !owner.isEmpty, !name.isEmpty else { return }
        state.companion = Companion(id: UUID().uuidString, ownerName: owner, petName: name, mood: .calm, updatedAt: Date(), kind: kind)
        if !state.collection.owned.contains(kind) { state.collection.owned.append(kind) }
        state.collection.names[kind.rawValue] = name
        persist()
        Task { await refresh() }
    }

    func setMood(_ mood: Mood) {
        guard state.companion != nil else { return }
        state.companion?.mood = mood
        state.companion?.updatedAt = Date()
        let day = CheckInDay.number(Date())
        state.collection.checkInQuietly(on: day)
        persist()
        Task { await refresh() }
    }

    func rename(owner: String, pet: String) {
        let owner = String(owner.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let pet = String(pet.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !owner.isEmpty, !pet.isEmpty else { return }
        state.companion?.ownerName = owner; state.companion?.petName = pet
        if let kind = state.companion?.kind { state.collection.names[kind.rawValue] = pet }
        state.companion?.updatedAt = Date()
        persist()
        Task { await refresh() }
    }

    func setWidget(_ mode: WidgetMode, pinned: String?) {
        state.widgetMode = mode
        state.pinnedFriendID = pinned
        persist()
    }

    func hatch(owner: String? = nil) -> CompanionKind? {
        guard storageAvailable, let kind = state.collection.unowned.randomElement() else { return nil }
        let free = state.companion == nil
        let name = (owner ?? state.companion?.ownerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let before = state
        guard state.collection.hatch(kind, free: free) else { return nil }
        if free {
            state.companion = Companion(id: UUID().uuidString, ownerName: String(name.prefix(24)), petName: kind.defaultName,
                                        mood: .calm, updatedAt: Date(), kind: kind)
        }
        do {
            if !preview { try saveState(state); WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind) }
        } catch {
            state = before; self.error = "Your hatch couldn't be saved. Your egg is still safe."; return nil
        }
        Task { await refresh() }
        return kind
    }

    @discardableResult func nameCreature(_ kind: CompanionKind, pet: String) -> Bool {
        guard storageAvailable, state.collection.owned.contains(kind) else { return false }
        let value = String(pet.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let name = value.isEmpty ? kind.defaultName : value
        let before = state
        state.collection.names[kind.rawValue] = name
        if state.companion?.kind == kind {
            state.companion?.petName = name
            state.companion?.updatedAt = Date()
        }
        do {
            if !preview { try saveState(state); WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind) }
        } catch {
            state = before; self.error = "That name couldn't be saved. Please try again."; return false
        }
        Task { await refresh() }
        return true
    }

    func activate(_ kind: CompanionKind) {
        guard state.collection.owned.contains(kind), state.companion != nil else { return }
        let name = state.collection.names[kind.rawValue] ?? kind.defaultName
        state.companion?.kind = kind
        state.companion?.petName = name
        state.companion?.updatedAt = Date()
        persist()
        Task { await refresh() }
    }

    func resolveRestore(use: Bool) {
        let day = CheckInDay.number(Date())
        let before = state
        do {
            let used = try restoreBudget.used()
            state.collection.restoresUsed = max(state.collection.restoresUsed, used)
            if use {
                guard state.collection.restoreCurrentStreak(on: day) else {
                    error = "This streak can no longer be restored. Your check-ins and companions are safe."
                    return
                }
            } else { state.collection.restorableStreak = nil }
            if !preview { try saveState(state) }
            if use { try restoreBudget.record(state.collection.restoresUsed) }
            showRestore = false
            persist()
        } catch {
            state = before
            try? saveState(before)
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        guard !preview, !deleting, state.sharingEnabled, state.companion != nil else { return }
        if syncing { syncAgain = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncAgain = false
            var issue: String?
            if state.cloudEnabled {
                do {
                    if let companion = state.companion { try await cloud.publish(companion) }
                    try await cloud.subscribe()
                } catch { issue = CircleSyncMessage.text(for: error) }
                do {
                    let friends = try await cloud.friends()
                    state.receiveFriends(friends + state.friends.filter { $0.id.hasPrefix("friend:") }, at: Date())
                    state.lastSyncedAt = Date()
                    persist()
                } catch { issue = issue ?? CircleSyncMessage.text(for: error) }
            }
            if state.linkConnected {
                if issue != nil {
                    let hasAppleFriends = state.friends.contains { $0.zoneName != nil }
                    issue = hasAppleFriends ? "An older iCloud connection couldn’t update. You can still invite friends with a new link." : nil
                }
                if state.linkPublishing, let pet = state.companion {
                    do { try await FriendLinks.shared.publish(pet) }
                    catch { issue = "Your mood is saved. Dotlings will try sharing it again when you reconnect." }
                }
                do {
                    let friends = try await FriendLinks.shared.friends()
                    state.receiveFriends(friends + state.friends.filter { !$0.id.hasPrefix("friend:") }, at: Date())
                    state.lastSyncedAt = Date()
                    persist()
                } catch { issue = "Pull down to try loading your friends again." }
            }
            syncIssue = issue
        } while syncAgain && !deleting
    }

    func invite() async {
        guard let pet = state.companion, storageAvailable, !deleting, !sharing else { return }
        sharing = true
        defer { sharing = false }
        state.linkConnected = true
        state.linkPublishing = true
        persist()
        do { outgoingInvite = try await FriendLinks.shared.invite(pet) }
        catch { self.error = (error as? LinkError)?.localizedDescription ?? LinkError.unavailable.localizedDescription }
    }

    func acceptLink(_ invite: FriendInvite) async {
        guard storageAvailable, !sharing, !deleting else { return }
        sharing = true
        defer { sharing = false }
        state.linkConnected = true
        persist()
        do {
            try await FriendLinks.shared.accept(invite)
            await refresh()
        } catch { self.error = (error as? LinkError)?.localizedDescription ?? LinkError.unavailable.localizedDescription }
    }

    func manageAppleInvites() async {
        guard let companion = state.companion, !sharing else { return }
        sharing = true; defer { sharing = false }
        do {
            share = try await cloud.sharingRecord(for: companion)
            state.cloudEnabled = true
            persist()
            UIApplication.shared.registerForRemoteNotifications()
            syncIssue = nil
            showSharing = true
            await refresh()
        } catch { self.error = CircleSyncMessage.text(for: error) }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await cloud.accept(metadata)
            state.cloudEnabled = true
            persist()
            await refresh()
        } catch { self.error = "The invitation couldn't be accepted: \(error.localizedDescription)" }
    }

    @discardableResult func arrangeFriends(_ ids: [String]) -> Bool {
        guard storageAvailable else { return false }
        var updated = state
        updated.arrangeFriends(ids)
        do {
            if !preview { try saveState(updated) }
            state = updated
        } catch {
            self.error = "Your friend order couldn't be saved. Please try again."
            return false
        }
        return true
    }

    @discardableResult func moveFriend(_ id: String, relativeTo target: String, after: Bool) -> Bool {
        guard let order = state.friendOrder(moving: id, relativeTo: target, after: after) else { return false }
        return arrangeFriends(order)
    }

    private func matchesOwnerCode(_ code: String) -> Bool {
        let normalized = code.lowercased().filter { !$0.isWhitespace && $0 != "-" }
        let digest = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return digest == "f946e27586a11014aba3aaded3c67ee2153692b1ce5b6c6fbd1a347fe7d6ccb3"
    }

    func unlockOwnerCollection(code: String) -> Bool {
        guard TestBuild.hasLocalTools, storageAvailable, state.companion != nil else { return false }
        guard matchesOwnerCode(code) else { return false }

        var updated = state
        updated.collection.completeCollection()
        do {
            if !preview { try saveState(updated) }
            state = updated
            return true
        } catch {
            self.error = "Your collection couldn't be saved. Please try again."
            return false
        }
    }

    func addTestFriend(ownerCode: String) -> Bool {
        guard TestFriend.available, storageAvailable, state.companion != nil,
              matchesOwnerCode(ownerCode) else { return false }
        var updated = state
        updated.enableTestFriend(at: Date())
        do {
            if !preview { try saveState(updated) }
            state = updated
            if !preview { WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind) }
            return true
        } catch {
            self.error = "Sky couldn't be saved on this device. Please try again."
            return false
        }
    }

    func tickTestFriend() {
        guard TestFriend.available else { return }
        // The start time is already saved. Widgets derive the mood when iOS refreshes them.
        state.updateTestFriend(at: Date())
    }

    func remove(_ friend: Companion) async {
        if friend.id == TestFriend.id {
            state.removeFriend(friend.id); persist(); return
        }
        do {
            if friend.id.hasPrefix("friend:") { try await FriendLinks.shared.leave(friend) }
            else { try await cloud.leave(friend) }
            state.removeFriend(friend.id); persist()
        }
        catch { self.error = "Couldn't leave this circle: \(error.localizedDescription)" }
    }

    func deleteCompanion() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            // Wait for publication to finish so an in-flight save cannot recreate the deleted share.
            while syncing || sharing { try await Task.sleep(for: .milliseconds(100)) }
            if state.linkConnected { try await FriendLinks.shared.erase() }
            if state.cloudEnabled { try await cloud.deleteOwnCompanion() }
            let restores = max(state.collection.restoresUsed, try restoreBudget.used())
            try restoreBudget.record(restores)
            try petRecovery?.clear()
            lastArchivedPet = nil
            var empty = CircleState()
            empty.collection.restoresUsed = restores
            try store.save(empty)
            state = empty
            syncIssue = nil
            WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind)
            showSettings = false
        } catch { self.error = "Couldn't remove the shared companion. Please reconnect and try again: \(error.localizedDescription)" }
    }
}

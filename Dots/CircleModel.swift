import Foundation
import Observation
import CloudKit
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

    init(store: CircleStore = CircleStore(), preview: Bool = false, restoreBudget: (any RestoreBudget)? = nil) {
        self.store = store
        self.preview = preview
        #if targetEnvironment(macCatalyst)
        self.restoreBudget = restoreBudget ?? MemoryRestoreBudget()
        #else
        self.restoreBudget = restoreBudget ?? KeychainRestoreBudget()
        #endif
        do { state = try store.load() }
        catch {
            state = CircleState(); storageAvailable = false
            self.error = "Your saved circle couldn't be read. Please restart the app before making changes. Your saved data hasn't been replaced."
        }
        if !preview {
            do { state.collection.restoresUsed = max(state.collection.restoresUsed, try self.restoreBudget.used()) }
            catch { self.error = error.localizedDescription }
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
        restoreBudget = MemoryRestoreBudget()
    }

    private func persist() {
        guard !preview, storageAvailable else { return }
        do { try store.save(state); WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind) }
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
            if !preview { try store.save(state); WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind) }
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
            if !preview { try store.save(state); WidgetCenter.shared.reloadTimelines(ofKind: DotsConfig.widgetKind) }
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
            if !preview { try store.save(state) }
            if use { try restoreBudget.record(state.collection.restoresUsed) }
            showRestore = false
            persist()
        } catch {
            state = before
            try? store.save(before)
            self.error = error.localizedDescription
        }
    }

    func connect() async {
        guard !preview else { return }
        do {
            try await cloud.checkAccount()
            state.cloudEnabled = true
            persist()
            UIApplication.shared.registerForRemoteNotifications()
            await refresh()
        } catch { self.error = CircleSyncMessage.text(for: error) }
    }

    func refresh() async {
        guard !preview, !deleting, state.cloudEnabled, state.companion != nil else { return }
        if syncing { syncAgain = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncAgain = false
            do {
                if let companion = state.companion { try await cloud.publish(companion) }
                let friends = try await cloud.friends()
                state.friends = friends
                if !friends.contains(where: { $0.id == state.pinnedFriendID }) { state.pinnedFriendID = nil }
                state.lastSyncedAt = Date()
                persist()
                try await cloud.subscribe()
                syncIssue = nil
            } catch { syncIssue = CircleSyncMessage.text(for: error) }
        } while syncAgain && !deleting
    }

    func invite() async {
        guard let companion = state.companion, !sharing else { return }
        sharing = true; defer { sharing = false }
        await connect()
        guard state.cloudEnabled else { return }
        do {
            share = try await cloud.sharingRecord(for: companion)
            showSharing = true
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

    func remove(_ friend: Companion) async {
        do { try await cloud.leave(friend); state.removeFriend(friend.id); persist() }
        catch { self.error = "Couldn't leave this circle: \(error.localizedDescription)" }
    }

    func deleteCompanion() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            // Wait for publication to finish so an in-flight save cannot recreate the deleted share.
            while syncing || sharing { try await Task.sleep(for: .milliseconds(100)) }
            if state.cloudEnabled { try await cloud.deleteOwnCompanion() }
            let restores = max(state.collection.restoresUsed, try restoreBudget.used())
            try restoreBudget.record(restores)
            state = CircleState(); state.collection.restoresUsed = restores
            syncIssue = nil
            persist(); showSettings = false
        } catch { self.error = "Couldn't remove the shared companion. Please reconnect and try again: \(error.localizedDescription)" }
    }
}

import Foundation
import Observation
import CloudKit
import WidgetKit
import UIKit

@MainActor @Observable
final class CircleModel {
    private(set) var state: CircleState
    var error: String?
    var syncing = false
    var sharing = false
    var deleting = false
    var share: CKShare?
    var showSharing = false
    var showSettings = false
    var showWidgetGuide = false
    private(set) var storageAvailable = true
    private let store: CircleStore
    let cloud = CloudCircle()
    private var syncAgain = false
    let preview: Bool

    init(store: CircleStore = CircleStore(), preview: Bool = false) {
        self.store = store
        self.preview = preview
        do { state = try store.load() }
        catch {
            state = CircleState(); storageAvailable = false
            self.error = "Your saved circle couldn't be read. Please restart the app before making changes. Your saved data hasn't been replaced."
        }
    }

    init(previewState: CircleState) {
        store = CircleStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        state = previewState
        preview = true
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
        persist()
        Task { await refresh() }
    }

    func setMood(_ mood: Mood) {
        guard state.companion != nil else { return }
        state.companion?.mood = mood
        state.companion?.updatedAt = Date()
        persist()
        Task { await refresh() }
    }

    func rename(owner: String, pet: String) {
        let owner = String(owner.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let pet = String(pet.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !owner.isEmpty, !pet.isEmpty else { return }
        state.companion?.ownerName = owner; state.companion?.petName = pet
        state.companion?.updatedAt = Date()
        persist()
        Task { await refresh() }
    }

    func setWidget(_ mode: WidgetMode, pinned: String?) {
        state.widgetMode = mode
        state.pinnedFriendID = pinned
        persist()
    }

    func connect() async {
        guard !preview else { return }
        do {
            try await cloud.checkAccount()
            state.cloudEnabled = true
            persist()
            UIApplication.shared.registerForRemoteNotifications()
            await refresh()
        } catch { self.error = error.localizedDescription }
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
            } catch { self.error = "Your mood is saved on this device. Friends couldn't be updated: \(error.localizedDescription)" }
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
        } catch { self.error = error.localizedDescription }
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
            state = CircleState(); persist(); showSettings = false
        } catch { self.error = "Couldn't remove the shared companion. Please reconnect and try again: \(error.localizedDescription)" }
    }
}

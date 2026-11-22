import Foundation
import Observation
import CloudKit
import CryptoKit
import WidgetKit
import UIKit
import UserNotifications
import StoreKit

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
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
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

    private(set) var changingAlerts = false
    private(set) var alertIssue: String?
    private(set) var alertsDenied = false
    private var subscribedFriendIDs: Set<String>?
    private var subscriptionOwner: String?
    private var reconcileAlerts = false

    func setMoodAlerts(_ enabled: Bool) async {
        guard !preview, !changingAlerts, let me = state.companion else { return }
        changingAlerts = true
        alertsDenied = false
        alertIssue = nil
        defer { changingAlerts = false }
        if enabled {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                    alertsDenied = true
                    alertIssue = "Allow Dotlings notifications in iPhone Settings, then turn on friend updates here."
                    return
                }
            } catch { self.alertIssue = "Couldn’t turn on notifications. Try again in a moment."; return }
            guard state.companion?.id == me.id else { return }
            state.enableMoodAlerts()
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            state.alertHistory = nil
        }
        subscribedFriendIDs = nil
        reconcileAlerts = true
        persist()
        await refresh()
    }

    private func updateSubscriptions() async throws {
        guard state.linkConnected, let owner = state.companion?.id,
              state.alertHistory != nil || reconcileAlerts else { return }
        let friends = state.alertHistory == nil ? [] : state.friends.filter { $0.id.hasPrefix("friend:") }
        let ids = Set(friends.map(\.id))
        guard subscribedFriendIDs != ids || subscriptionOwner != owner else { return }
        let peers: Set<String> = friends.isEmpty ? [] : try await FriendLinks.shared.peerRecords(for: friends)
        try await cloud.syncMoodSubscriptions(owner: owner, peers: peers)
        subscribedFriendIDs = ids
        subscriptionOwner = owner
        reconcileAlerts = false
    }

    private func received(_ friends: [Companion], fromLinks: Bool) async {
        let changes = state.moodChanges(in: friends, fromLinks: fromLinks)
        state.receiveFriends(friends, fromLinks: fromLinks, at: Date())
        state.lastSyncedAt = Date()
        persist()
        for friend in changes where state.alertHistory?[friend.id]?.date == friend.updatedAt {
            let content = UNMutableNotificationContent()
            content.title = friend.ownerName
            content.body = "Shared a new mood."
            content.sound = .default
            content.threadIdentifier = "dotlings-circle"
            content.userInfo = ["dotlingsMood": true]
            let request = UNNotificationRequest(identifier: "mood-" + friend.id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static let allPetsID = "com.jasonmiller.dots.allpets"
    private(set) var allPetsProduct: Product?
    var allPetsPrice: String? {
        #if DEBUG || DOTS_RENDER
        if preview { return "$1.99" } // U.S. storefront fixture for native screen captures.
        #endif
        return allPetsProduct?.displayPrice
    }
    private(set) var hasAllPets = false
    private(set) var storeBusy = false
    private(set) var loadingProduct = false
    var storeMessage: String?

    var availableCollection: CollectionProgress {
        var collection = state.collection
        if hasAllPets { collection.completeCollection() }
        return collection
    }

    func loadAllPetsProduct() async {
        guard !preview, allPetsProduct == nil, !loadingProduct else { return }
        loadingProduct = true
        defer { loadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.allPetsID])
            allPetsProduct = products.first { $0.id == Self.allPetsID && $0.type == .nonConsumable }
            storeMessage = allPetsProduct == nil ? "The shop is temporarily unavailable." : nil
        } catch { storeMessage = "The App Store couldn’t connect. Try again in a moment." }
    }

    func watchPurchases() async {
        guard !preview else { return }
        async let initial: Void = refreshPurchaseAccess()
        for await result in StoreKit.Transaction.updates {
            guard !Task.isCancelled else { break }
            guard case .verified(let transaction) = result, transaction.productID == Self.allPetsID else { continue }
            await refreshPurchaseAccess()
            await transaction.finish()
        }
        await initial
    }

    private var accessCheck = 0
    private func refreshPurchaseAccess() async {
        accessCheck += 1
        let check = accessCheck
        let result = await StoreKit.Transaction.currentEntitlement(for: Self.allPetsID)
        guard check == accessCheck else { return }
        switch result {
        case .verified(let transaction): applyCollectionAccess(transaction.revocationDate == nil)
        case .unverified: storeMessage = "Apple couldn’t verify this purchase."; return
        case nil: applyCollectionAccess(false)
        }
    }

    func applyCollectionAccess(_ entitled: Bool) {
        hasAllPets = entitled
        if !hasAllPets, state.collection.selectedWithPurchase == true,
           let earned = state.collection.owned.first, let chosen = state.companion?.kind {
            state.collection.selectedWithPurchase = nil
            if !state.collection.owned.contains(chosen) { activate(earned) }
            else { persist() }
        }
    }

    func buyAllPets() async {
        guard !preview, !storeBusy, !hasAllPets, let product = allPetsProduct else { return }
        storeBusy = true
        storeMessage = nil
        defer { storeBusy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)) where transaction.productID == Self.allPetsID:
                await refreshPurchaseAccess()
                await transaction.finish()
            case .success: storeMessage = "Apple couldn’t verify this purchase."
            case .pending: storeMessage = "Your purchase is waiting for approval."
            case .userCancelled: break
            @unknown default: storeMessage = "Check your purchase again in a moment."
            }
        } catch { storeMessage = "Your purchase couldn’t be completed. Please try again." }
    }

    func restoreAllPets() async {
        guard !preview, !storeBusy else { return }
        storeBusy = true
        defer { storeBusy = false }
        do {
            try await AppStore.sync()
            await refreshPurchaseAccess()
            storeMessage = hasAllPets ? "All your Dotlings are available." : "No all-pets purchase was found for this Apple Account."
        } catch { storeMessage = "Couldn’t restore purchases. Please try again." }
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
        guard storageAvailable, availableCollection.owned.contains(kind) else { return false }
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
        guard availableCollection.owned.contains(kind), state.companion != nil else { return }
        state.collection.selectedWithPurchase = state.collection.owned.contains(kind) ? nil : true
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

    func refresh(waitForCompletion: Bool = false) async {
        guard !preview, !deleting, state.sharingEnabled, state.companion != nil else { return }
        if syncing {
            syncAgain = true
            if waitForCompletion { await withCheckedContinuation { refreshWaiters.append($0) } }
            return
        }
        syncing = true
        defer {
            syncing = false
            for waiter in refreshWaiters { waiter.resume() }
            refreshWaiters.removeAll()
        }
        repeat {
            syncAgain = false
            async let apple = refreshAppleFriends()
            async let links = refreshLinkedFriends()
            let (appleIssue, linkIssue) = await (apple, links)
            syncIssue = linkIssue ?? appleIssue
            do {
                try await updateSubscriptions()
                if !alertsDenied { alertIssue = nil }
            } catch { alertIssue = "Friend alerts couldn’t connect. Check for mood updates to retry." }
        } while syncAgain && !deleting
    }

    private func refreshAppleFriends() async -> String? {
        guard state.cloudEnabled else { return nil }
        var issue: String?
        do {
            try await cloud.subscribe()
            if let companion = state.companion { try await cloud.publish(companion) }
        } catch { issue = CircleSyncMessage.text(for: error) }
        do {
            let friends = try await cloud.friends()
            await received(friends, fromLinks: false)
        } catch { issue = issue ?? CircleSyncMessage.text(for: error) }
        if issue != nil && state.linkConnected {
            return state.friends.contains { $0.zoneName != nil } ? "An older iCloud connection couldn’t update. New friend links still work." : nil
        }
        return issue
    }

    private func refreshLinkedFriends() async -> String? {
        guard state.linkConnected else { return nil }
        var issue: String?
        if state.linkPublishing, let pet = state.companion {
            do { try await FriendLinks.shared.publish(pet) }
            catch { issue = "Your mood is saved. Dotlings will try sharing it again when you reconnect." }
        }
        do {
            let friends = try await FriendLinks.shared.friends()
            await received(friends, fromLinks: true)
        } catch { issue = issue ?? "Pull down to try loading your friends again." }
        return issue
    }

    func invite() async {
        guard let pet = state.companion, storageAvailable, !deleting, !sharing else { return }
        sharing = true
        defer { sharing = false }
        do {
            outgoingInvite = try await FriendLinks.shared.invite(pet)
            state.linkConnected = true
            state.linkPublishing = true
            persist()
        }
        catch { self.error = (error as? LinkError)?.localizedDescription ?? LinkError.unavailable.localizedDescription }
    }

    func acceptLink(_ invite: FriendInvite) async {
        guard let pet = state.companion, storageAvailable, !sharing, !deleting else { return }
        sharing = true
        defer { sharing = false }
        do {
            try await FriendLinks.shared.accept(invite, companion: pet)
            state.linkConnected = true
            state.linkPublishing = true
            persist()
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
            await refresh()
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
            if state.linkConnected {
                if let owner = state.companion?.id, state.alertHistory != nil || reconcileAlerts {
                    try await cloud.syncMoodSubscriptions(owner: owner, peers: [])
                }
                try await FriendLinks.shared.erase()
            }
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

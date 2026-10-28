import CloudKit
import Foundation

enum CircleError: LocalizedError {
    case noICloud, invalidCompanion
    var errorDescription: String? {
        switch self {
        case .noICloud: "Sign in to iCloud in your iPhone Settings to connect with friends."
        case .invalidCompanion: "This invitation doesn't contain a Dotlings companion."
        }
    }
}

enum CircleSyncMessage {
    static func text(for error: Error) -> String {
        if let error = error as? CircleError { return error.localizedDescription }
        if let error = error as? CKError, error.code == .notAuthenticated {
            return "Sign in to iCloud in your iPhone Settings to reconnect with friends."
        }
        return "Friends couldn't be updated right now. Please try again later."
    }
}

@MainActor
final class CloudCircle {
    lazy var container = CKContainer(identifier: DotsConfig.container)
    private var ownZone: CKRecordZone.ID { .init(zoneName: "MyCompanion", ownerName: CKCurrentUserDefaultName) }
    private var ownID: CKRecord.ID { .init(recordName: "companion", zoneID: ownZone) }

    func checkAccount() async throws {
        guard try await container.accountStatus() == .available else { throw CircleError.noICloud }
    }

    func publish(_ companion: Companion) async throws {
        try await checkAccount()
        let database = container.privateCloudDatabase
        _ = try await database.save(CKRecordZone(zoneID: ownZone))
        let record: CKRecord
        do { record = try await database.record(for: ownID) }
        catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: "Companion", recordID: ownID)
        }
        record["companionID"] = companion.id as CKRecordValue
        record["ownerName"] = companion.ownerName as CKRecordValue
        record["petName"] = companion.petName as CKRecordValue
        record["mood"] = companion.mood.rawValue as CKRecordValue
        record["kind"] = companion.kind.rawValue as CKRecordValue
        record["updatedAt"] = companion.updatedAt as CKRecordValue
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        _ = try result.saveResults[ownID]?.get()
    }

    func sharingRecord(for companion: Companion) async throws -> CKShare {
        try await publish(companion)
        let database = container.privateCloudDatabase
        let record = try await database.record(for: ownID)
        if let existing = record.share {
            guard let share = try await database.record(for: existing.recordID) as? CKShare else { throw CircleError.invalidCompanion }
            return share
        }
        let share = CKShare(rootRecord: record)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "\(companion.ownerName)'s companion" as CKRecordValue
        let result = try await database.modifyRecords(saving: [record, share], deleting: [], atomically: true)
        // Check both per-record results; a completed operation can still contain record failures.
        for value in result.saveResults.values { _ = try value.get() }
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else { throw CircleError.invalidCompanion }
        return saved
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        try await checkAccount()
        let results = try await container.accept([metadata])
        for result in results.values { _ = try result.get() }
    }

    func friends() async throws -> [Companion] {
        try await checkAccount()
        let database = container.sharedCloudDatabase
        let zones = try await database.allRecordZones()
        var friends: [Companion] = []
        for zone in zones {
            var token: CKServerChangeToken?
            var more = true
            while more {
                let changes = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: token)
                for result in changes.modificationResultsByID.values {
                    let record = try result.get().record
                    if let friend = Self.companion(record) { friends.append(friend) }
                }
                token = changes.changeToken
                more = changes.moreComing
            }
        }
        // Fetching from a nil token produces the complete current set, including revoked shares.
        return Array(Dictionary(friends.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b }).values)
    }

    private static func companion(_ record: CKRecord) -> Companion? {
        guard record.recordType == "Companion",
              let owner = record["ownerName"] as? String,
              let pet = record["petName"] as? String,
              let raw = record["mood"] as? String, let mood = Mood(rawValue: raw),
              let updatedAt = record["updatedAt"] as? Date else { return nil }
        let zone = record.recordID.zoneID
        return Companion(id: "\(zone.ownerName)|\(zone.zoneName)|\(record.recordID.recordName)",
                         ownerName: owner, petName: pet, mood: mood, updatedAt: updatedAt,
                         kind: CompanionKind(rawValue: record["kind"] as? String ?? "") ?? .lavender,
                         zoneName: zone.zoneName, zoneOwner: zone.ownerName, recordName: record.recordID.recordName)
    }

    func leave(_ friend: Companion) async throws {
        guard let zoneName = friend.zoneName, let owner = friend.zoneOwner,
              let recordName = friend.recordName else { throw CircleError.invalidCompanion }
        let id = CKRecord.ID(recordName: recordName, zoneID: .init(zoneName: zoneName, ownerName: owner))
        // In the participant's shared database, deleting the shared root leaves the share;
        // it does not delete the owner's record in their private database.
        _ = try await container.sharedCloudDatabase.deleteRecord(withID: id)
    }

    func subscribe() async throws {
        for (database, id) in [(container.privateCloudDatabase, "dots-private"), (container.sharedCloudDatabase, "dots-friends")] {
            do { _ = try await database.subscription(for: id) }
            catch let error as CKError where error.code == .unknownItem {
                let subscription = CKDatabaseSubscription(subscriptionID: id)
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                subscription.notificationInfo = info
                _ = try await database.save(subscription)
            }
        }
    }

    func deleteOwnCompanion() async throws {
        // Deleting the zone also deletes its share and immediately revokes access for recipients.
        do { _ = try await container.privateCloudDatabase.deleteRecordZone(withID: ownZone) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // A previously removed or never-created zone already has the intended empty state.
        }
    }
}

extension Notification.Name {
    static let dotsShareAccepted = Notification.Name("dotsShareAccepted")
    static let dotsRefresh = Notification.Name("dotsRefresh")
}

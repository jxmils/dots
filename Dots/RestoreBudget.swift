import Foundation
import Security

protocol RestoreBudget {
    func used() throws -> Int
    func record(_ count: Int) throws
}

final class MemoryRestoreBudget: RestoreBudget {
    private var count = 0
    func used() throws -> Int { count }
    func record(_ count: Int) throws { self.count = max(self.count, count) }
}

// This small receipt survives an in-app companion reset. It contains only the number of used restores.
// Synchronizable Keychain items can follow the user's iCloud Keychain; actual device behavior needs testing.
final class KeychainRestoreBudget: RestoreBudget {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.jasonmiller.dots.streak-restores",
         kSecAttrAccount as String: "lifetime-budget",
         kSecAttrSynchronizable as String: true]
    }
    func used() throws -> Int {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return 0 }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8).flatMap(Int.init) else { throw BudgetError.unavailable }
        return value
    }
    func record(_ count: Int) throws {
        let value = max(try used(), count)
        let data = Data(String(value).utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BudgetError.unavailable }
        } else if status != errSecSuccess { throw BudgetError.unavailable }
    }
    enum BudgetError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Your restore budget couldn't be read securely. Please unlock your device and try again." }
    }
}

// Keep only the owner's data. A reinstall must not restore another person's cached mood.
struct PetArchive: Codable, Equatable {
    let companion: Companion
    let collection: CollectionProgress
    let linkConnected: Bool?
    let linkPublishing: Bool?
    let cloudEnabled: Bool

    init?(_ state: CircleState) {
        guard let companion = state.companion else { return nil }
        self.companion = companion
        collection = state.collection
        cloudEnabled = state.cloudEnabled
        linkConnected = state.linkConnected
        linkPublishing = state.linkPublishing
    }

    var restoredState: CircleState {
        var state = CircleState(cloudEnabled: cloudEnabled, companion: companion, collection: collection)
        state.linkConnected = linkConnected ?? false
        state.linkPublishing = linkPublishing ?? false
        return state
    }
}

protocol PetRecovery {
    func read() throws -> PetArchive?
    func write(_ archive: PetArchive) throws
    func clear() throws
}

struct DevicePetRecovery: PetRecovery {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.jasonmiller.dots.pet-recovery.v1",
         kSecAttrAccount as String: "collection",
         kSecAttrSynchronizable as String: false]
    }
    func read() throws -> PetArchive? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw RecoveryError.unavailable }
        return try JSONDecoder().decode(PetArchive.self, from: data)
    }
    func write(_ archive: PetArchive) throws {
        let attributes = [kSecValueData as String: try JSONEncoder().encode(archive)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw RecoveryError.unavailable }
        } else if status != errSecSuccess { throw RecoveryError.unavailable }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RecoveryError.unavailable }
    }
    enum RecoveryError: Error { case unavailable }
}

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

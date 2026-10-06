import Foundation
import Security

/// The 32-byte key that encrypts the on-device database (SQLCipher, via LimeCore). It is made
/// once, on first launch, and lives only in the Keychain: available after the first unlock (a
/// later background mesh relay needs that) and this-device-only, so it never reaches an iCloud
/// backup or another device.
enum StorageKeychain {
    enum KeychainError: Error {
        case randomFailed(OSStatus)
        case unexpected(OSStatus)
    }

    static let defaultService = "app.lime.storage"
    private static let account = "database-key"

    /// Returns the stored key, creating and storing a new random one on first use.
    static func loadOrCreateKey(service: String = defaultService) throws -> Data {
        if let existing = try read(service: service) { return existing }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainError.randomFailed(status) }
        let key = Data(bytes)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem, let existing = try read(service: service) {
            return existing // another launch won the race
        }
        guard addStatus == errSecSuccess else { throw KeychainError.unexpected(addStatus) }
        return key
    }

    /// The stored key, or nil when there is none (or it is unusable, which is treated the same way).
    static func existingKey(service: String = defaultService) -> Data? {
        (try? read(service: service)) ?? nil
    }

    static func deleteKey(service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func read(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw KeychainError.unexpected(status)
        }
        return data
    }
}

import Foundation
import Security

/// The signed-in session's tokens, in the Keychain: this device only, available after first unlock.
/// They never go to iCloud, and signing out removes them.
enum SessionKeychain {
    static let defaultService = "app.lime.session"
    private static let account = "tokens"

    static func save(_ tokens: AuthTokens, service: String = defaultService) throws {
        let data = try JSONEncoder().encode(tokens)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            let status = SecItemAdd(base.merging(attributes) { $1 } as CFDictionary, nil)
            guard status == errSecSuccess else { throw StorageKeychain.KeychainError.unexpected(status) }
        } else if updated != errSecSuccess {
            throw StorageKeychain.KeychainError.unexpected(updated)
        }
    }

    static func load(service: String = defaultService) -> AuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    static func clear(service: String = defaultService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

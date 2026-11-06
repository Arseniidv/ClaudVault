import Foundation
import Security

/// Восстановленная Google-сессия (refresh token), полученная
/// через QR-перенос с другого устройства.
///
/// `GIDSignIn` не позволяет инжектировать чужую сессию, поэтому
/// токены хранятся здесь, а `GoogleOAuthManager` обменивает
/// refresh token на access token напрямую через OAuth2 endpoint.
struct GoogleRestoredSession: Codable {
    var refreshToken: String
    var clientID: String
    var userID: String
    var email: String
    var displayName: String?
    var grantedScopes: [String]
    /// Кэш access token'а до его реального истечения.
    var accessToken: String?
    var accessTokenExpiresAt: Date?
}

/// Keychain-хранилище восстановленной Google-сессии.
/// Не синхронизируется между устройствами — попадает на устройство
/// только через зашифрованный QR-пакет.
struct GoogleSessionStore {

    func load() -> GoogleRestoredSession? {
        let account = "google-restored|session"
        var query = Self.baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleRestoredSession.self, from: data)
    }

    func save(_ session: GoogleRestoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }

        let account = "google-restored|session"
        let query = Self.baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func delete() {
        let account = "google-restored|session"
        let query = Self.baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.claudvault.storage.auth",
            kSecAttrAccount as String: account
        ]

        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        return query
    }
}

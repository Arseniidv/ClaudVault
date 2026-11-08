import Foundation
import Security

/// Восстановленная Google-сессия (refresh token), полученная
/// через QR-перенос с другого устройства или экспортированная
/// при смене пользователя CloudVault.
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
///
/// Записи изолированы по пользователю CloudVault: аккаунт
/// `google-restored|session|<ownerID>`. Легаси-ключ
/// `google-restored|session` (до введения изоляции) владельца
/// не имеет и удаляется `deleteLegacyItem` — чужую сессию
/// присваивать нельзя.
struct GoogleSessionStore {

    private static let accountPrefix = "google-restored|session"
    /// Легаси-ключ до версионирования по ownerID.
    private static let legacyAccount = "google-restored|session"

    func load(ownerID: String) -> GoogleRestoredSession? {
        guard !ownerID.isEmpty else { return nil }
        return load(account: Self.account(for: ownerID))
    }

    func save(_ session: GoogleRestoredSession, ownerID: String) {
        guard !ownerID.isEmpty,
              let data = try? JSONEncoder().encode(session) else { return }

        let query = Self.baseQuery(account: Self.account(for: ownerID))
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

    func delete(ownerID: String) {
        guard !ownerID.isEmpty else { return }
        let query = Self.baseQuery(account: Self.account(for: ownerID))
        SecItemDelete(query as CFDictionary)
    }

    /// Удаляет легаси-ключ `google-restored|session`, оставшийся
    /// от версии без owner-изоляции. Вызывается один раз при входе
    /// пользователя — см. `UserSessionCoordinator`.
    static func deleteLegacyItem() {
        SecItemDelete(baseQuery(account: legacyAccount) as CFDictionary)
    }

    // MARK: - Private

    private static func account(for ownerID: String) -> String {
        "\(accountPrefix)|\(ownerID)"
    }

    private func load(account: String) -> GoogleRestoredSession? {
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

import Foundation
import Security

/// Keychain-хранилище токенов OneDrive (access/refresh).
///
/// Записи лежат в едином сервисе `com.claudvault.storage.auth`
/// через `KeychainItemStore` — с `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// и Data Protection Keychain на macOS. При первом обращении
/// выполняется разовый перенос из легаси-сервиса
/// `my.ClaudVault.onedrive`.
struct OneDriveTokenStore {

    private static let account = "onedrive|tokens"
    private static let legacyService = "my.ClaudVault.onedrive"
    private static let legacyAccount = "tokens"
    private static let migrationFlagKey = "OneDriveKeychainMigrationV1"

    struct StoredTokens: Codable {
        var accessToken: String
        var refreshToken: String
        /// Дата истечения access token (с запасом на обработку).
        var expiresAt: Date
    }

    func load() -> StoredTokens? {
        if let data = KeychainItemStore.load(account: Self.account),
           let tokens = try? JSONDecoder().decode(StoredTokens.self, from: data) {
            return tokens
        }
        return loadLegacyAndMigrate()
    }

    func save(_ tokens: StoredTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try? KeychainItemStore.save(data, account: Self.account)
    }

    func delete() {
        try? KeychainItemStore.delete(account: Self.account)
    }

    /// Одноразовый перенос токенов из легаси Keychain-сервиса
    /// `my.ClaudVault.onedrive` в единое хранилище.
    /// На macOS легаси-айтемы лежат в файловой связке ключей,
    /// поэтому запрос к ним идёт без `kSecUseDataProtectionKeychain`.
    private func loadLegacyAndMigrate() -> StoredTokens? {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationFlagKey) else {
            return nil
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecAttrAccount as String: Self.legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // Флаг ставим только при однозначном ответе Keychain:
        // айтем найден (мигрируем) или его нет (мигрировать нечего).
        // При прочих ошибках (например, `errSecInteractionNotAllowed`
        // на заблокированном устройстве) миграция повторится
        // при следующем обращении.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return nil
        }
        defaults.set(true, forKey: Self.migrationFlagKey)

        guard status == errSecSuccess,
              let data = result as? Data,
              let tokens = try? JSONDecoder().decode(
                  StoredTokens.self, from: data
              ) else {
            return nil
        }

        try? KeychainItemStore.save(data, account: Self.account)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecAttrAccount as String: Self.legacyAccount
        ] as CFDictionary)
        return tokens
    }
}

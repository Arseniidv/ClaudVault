import Foundation
import Security

/// Keychain-хранилище токенов OneDrive (access/refresh).
///
/// Записи лежат в едином сервисе `com.claudvault.storage.auth`
/// через `KeychainItemStore` — с `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// и Data Protection Keychain на macOS. Ключ аккаунта включает
/// `ownerID` текущего пользователя (`onedrive|tokens|<ownerID>`),
/// поэтому токены разных аккаунтов CloudVault не пересекаются.
///
/// Токены, сохранённые до введения изоляции (общий ключ
/// `onedrive|tokens` и легаси-сервис `my.ClaudVault.onedrive`),
/// владельца не имеют и НЕ мигрируются — `deleteLegacyItems`
/// удаляет их при первом входе, чтобы исключить утечку чужих
/// credentials. Пользователю достаточно один раз переподключить
/// OneDrive.
struct OneDriveTokenStore {

    private static let accountPrefix = "onedrive|tokens"
    /// Легаси-ключ до версионирования по ownerID.
    private static let legacyAccount = "onedrive|tokens"
    private static let legacyService = "my.ClaudVault.onedrive"
    private static let legacyAccountName = "tokens"

    struct StoredTokens: Codable {
        var accessToken: String
        var refreshToken: String
        /// Дата истечения access token (с запасом на обработку).
        var expiresAt: Date
    }

    /// Аккаунт текущего пользователя; nil — сеанса нет,
    /// читать/писать нельзя.
    private var scopedAccount: String? {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return nil
        }
        return "\(Self.accountPrefix)|\(ownerID)"
    }

    func load() -> StoredTokens? {
        guard let account = scopedAccount,
              let data = KeychainItemStore.load(account: account) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func save(_ tokens: StoredTokens) {
        guard let account = scopedAccount,
              let data = try? JSONEncoder().encode(tokens) else { return }
        try? KeychainItemStore.save(data, account: account)
    }

    func delete() {
        guard let account = scopedAccount else { return }
        try? KeychainItemStore.delete(account: account)
    }

    /// Удаляет токены, сохранённые до введения owner-изоляции:
    /// общий ключ `onedrive|tokens` и айтемы легаси-сервиса
    /// `my.ClaudVault.onedrive`. Вызывается один раз при входе
    /// пользователя — см. `UserSessionCoordinator`.
    static func deleteLegacyItems() {
        try? KeychainItemStore.delete(account: legacyAccount)

        // На macOS легаси-айтемы лежат в файловой связке ключей,
        // поэтому запрос идёт без `kSecUseDataProtectionKeychain`.
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccountName
        ] as CFDictionary)
    }
}

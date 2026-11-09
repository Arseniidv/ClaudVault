import Foundation
import Security
import SwiftyDropbox

/// Мост между синхронным протоколом `SecureStorageAccess` SwiftyDropbox
/// и единым Keychain-хранилищем приложения (`com.claudvault.storage.auth`).
///
/// SDK сохраняет `DropboxAccessToken` (JSON) по ключу Dropbox UID
/// в аккаунтах `dropbox-sdk|<uid>` — отдельно от нормализованных
/// `CloudAccountSession`-записей, но в том же Keychain-сервисе
/// с теми же атрибутами доступности.
///
/// При первом запуске переносит токены из легаси-сервиса
/// `<bundleId>.dropbox.authv2`, который использовал
/// `SecureStorageAccessDefaultImpl`.
nonisolated final class DropboxSecureStorageAccess: SecureStorageAccess {

    private static let accountPrefix = "dropbox-sdk|"
    /// Карта владения: `dropbox-owner|<uid>` → ownerID пользователя
    /// CloudVault. SDK хранит токены по Dropbox UID без привязки
    /// к аккаунту приложения, поэтому принадлежность учитываем
    /// отдельными ключами в том же Keychain-сервисе.
    private static let ownerPrefix = "dropbox-owner|"
    private static let legacyServiceSuffix = "dropbox.authv2"
    private static let migrationFlagKey = "DropboxKeychainMigrationV1"

    init() {
        migrateLegacyTokensIfNeeded()
    }

    // MARK: - SecureStorageAccess

    /// Атрибут доступности задаётся при каждой записи
    /// в `KeychainItemStore` — отдельная миграция не нужна.
    func checkAccessibilityMigrationOneTime() {}

    func setAccessTokenData(for userId: String, data: Data) -> Bool {
        do {
            try KeychainItemStore.save(data, account: Self.account(for: userId))
            return true
        } catch {
            #if DEBUG
            print("[Dropbox] Keychain save failed: \(error)")
            #endif
            return false
        }
    }

    /// UID'ы Dropbox-аккаунтов, принадлежащих текущему
    /// пользователю CloudVault. Токены без записи о владельце
    /// (сохранённые до введения изоляции) не возвращаются —
    /// их удаляет `deleteOrphanedTokens` при первом входе.
    func getAllUserIds() -> [String] {
        ownedUserIds()
    }

    /// UID'ы токенов, принадлежащих текущему пользователю.
    /// Без активного пользователя возвращает пустой список —
    /// SDK не должен восстанавливать чужую сессию.
    func ownedUserIds() -> [String] {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return []
        }
        return KeychainItemStore.allAccounts()
            .filter { $0.hasPrefix(Self.accountPrefix) }
            .map { String($0.dropFirst(Self.accountPrefix.count)) }
            .filter { owner(ofDropboxUID: $0) == ownerID }
    }

    /// Записывает владельца Dropbox-токена. Вызывается после
    /// успешного connect/restore, когда известен и Dropbox UID,
    /// и текущий пользователь CloudVault.
    func setOwner(_ appOwnerID: String, forDropboxUID uid: String) {
        guard !appOwnerID.isEmpty else { return }
        try? KeychainItemStore.save(
            Data(appOwnerID.utf8),
            account: Self.ownerAccount(for: uid)
        )
    }

    /// Владелец Dropbox-токена; nil — токен «бесхозный»
    /// (записан до введения изоляции).
    func owner(ofDropboxUID uid: String) -> String? {
        guard let data = KeychainItemStore.load(
            account: Self.ownerAccount(for: uid)
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Удаляет Dropbox-токены без записи о владельце — наследие
    /// версии до owner-изоляции. Вызывается один раз при входе
    /// пользователя — см. `UserSessionCoordinator`.
    static func deleteOrphanedTokens() {
        let access = DropboxSecureStorageAccess()
        for account in KeychainItemStore.allAccounts()
        where account.hasPrefix(accountPrefix) {
            let uid = String(account.dropFirst(accountPrefix.count))
            if access.owner(ofDropboxUID: uid) == nil {
                try? KeychainItemStore.delete(account: account)
            }
        }
        // Карты владельцев без соответствующих токенов тоже чистим.
        for account in KeychainItemStore.allAccounts()
        where account.hasPrefix(ownerPrefix) {
            let uid = String(account.dropFirst(ownerPrefix.count))
            let tokenAccount = "\(accountPrefix)\(uid)"
            if KeychainItemStore.load(account: tokenAccount) == nil {
                try? KeychainItemStore.delete(account: account)
            }
        }
    }

    private static func ownerAccount(for uid: String) -> String {
        "\(ownerPrefix)\(uid)"
    }

    /// Defense-in-depth: даже если SDK запросит токен по UID
    /// напрямую (минуя `getAllUserIds`), «бесхозные» и чужие
    /// токены не отдаются — владелец обязан совпадать с
    /// текущим пользователем CloudVault.
    func getDropboxAccessToken(for key: String) -> DropboxAccessToken? {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty,
              owner(ofDropboxUID: key) == ownerID else {
            return nil
        }
        guard let data = KeychainItemStore.load(
            account: Self.account(for: key)
        ) else {
            return nil
        }

        if let token = try? JSONDecoder().decode(
            DropboxAccessToken.self, from: data
        ) {
            return token
        }

        // Совместимость со старыми версиями SDK: токен хранился строкой.
        if let accessToken = String(data: data, encoding: .utf8),
           !accessToken.isEmpty {
            return DropboxAccessToken(accessToken: accessToken, uid: key)
        }
        return nil
    }

    func deleteInfo(for key: String) -> Bool {
        do {
            try KeychainItemStore.delete(account: Self.account(for: key))
            try? KeychainItemStore.delete(
                account: Self.ownerAccount(for: key)
            )
            return true
        } catch {
            return false
        }
    }

    func deleteInfoForAllKeys() -> Bool {
        KeychainItemStore.deleteAccounts(withPrefix: Self.accountPrefix)
        return true
    }

    // MARK: - Legacy migration

    /// Переносит токены, сохранённые `SecureStorageAccessDefaultImpl`
    /// в сервисе `<bundleId>.dropbox.authv2`, в единое хранилище.
    /// На macOS легаси-айтемы лежат в файловой связке ключей,
    /// поэтому запрос к ним идёт без `kSecUseDataProtectionKeychain`.
    private func migrateLegacyTokensIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationFlagKey),
              let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.isEmpty else {
            return
        }

        let legacyService = "\(bundleID).\(Self.legacyServiceSuffix)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // Флаг ставим только при однозначном ответе Keychain —
        // см. комментарий в `OneDriveTokenStore.loadLegacyAndMigrate`.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return
        }
        defaults.set(true, forKey: Self.migrationFlagKey)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return
        }

        for item in items {
            guard let uid = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else {
                continue
            }
            try? KeychainItemStore.save(
                data, account: Self.account(for: uid)
            )
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: uid
            ] as CFDictionary)
        }
    }

    private static func account(for uid: String) -> String {
        "\(accountPrefix)\(uid)"
    }
}

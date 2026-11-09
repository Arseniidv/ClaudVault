import Foundation
import Security
import SwiftyDropbox

/// Мост между синхронным протоколом `SecureStorageAccess` SwiftyDropbox
/// и единым Keychain-хранилищем приложения (`com.claudvault.storage.auth`).
///
/// Новые токены сохраняются в owner-scoped аккаунтах
/// `dropbox-sdk|<ownerID>|<uid>`: владелец и токен — одна запись,
/// поэтому OAuth-токен нельзя «потерять» из-за отдельного owner-маппинга.
///
/// Legacy-форматы продолжают читаться:
/// - `dropbox-sdk|<uid>` + `dropbox-owner|<uid>` → ownerID (текущая
///   изоляция до scoped-аккаунтов, мигрирует при первом чтении);
/// - `<bundleId>.dropbox.authv2` из `SecureStorageAccessDefaultImpl`
///   переносится в `dropbox-sdk|<uid>` без владельца — такие записи
///   по-прежнему считаются бесхозными и чистятся `deleteOrphanedTokens`,
///   потому что владельца доказать нельзя.
nonisolated final class DropboxSecureStorageAccess: SecureStorageAccess {

    private static let accountPrefix = "dropbox-sdk|"
    /// Legacy owner-маппинг: `dropbox-owner|<uid>` → ownerID.
    /// Для новых токенов не используется — владелец зашит в account.
    private static let ownerPrefix = "dropbox-owner|"
    private static let legacyServiceSuffix = "dropbox.authv2"
    private static let migrationFlagKey = "DropboxKeychainMigrationV1"

    /// Разбор Keychain-аккаунта Dropbox-токена.
    enum AccountKind: Equatable {
        /// `dropbox-sdk|<ownerID>|<uid>` — токен конкретного
        /// пользователя ClaudVault.
        case scoped(ownerID: String, uid: String)
        /// `dropbox-sdk|<uid>` — legacy-запись, владелец
        /// проверяется по `dropbox-owner|<uid>`.
        case legacy(uid: String)
    }

    init() {
        migrateLegacyTokensIfNeeded()
    }

    // MARK: - SecureStorageAccess

    /// Атрибут доступности задаётся при каждой записи
    /// в `KeychainItemStore` — отдельная миграция не нужна.
    func checkAccessibilityMigrationOneTime() {}

    /// Сохраняет JSON `DropboxAccessToken` под аккаунтом текущего
    /// владельца. Без `ownerID` запись запрещена: токен без владельца
    /// был бы недоступен восстановлению и удалялся cleanup'ом.
    func setAccessTokenData(for userId: String, data: Data) -> Bool {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return false
        }
        do {
            try KeychainItemStore.save(
                data,
                account: Self.scopedAccount(for: ownerID, uid: userId)
            )
            return true
        } catch {
            #if DEBUG
            print("[Dropbox] Keychain save failed: \(error)")
            #endif
            return false
        }
    }

    /// UID'ы Dropbox-аккаунтов текущего пользователя для SDK.
    /// Протокол не позволяет пробросить ошибку — критические пути
    /// приложения используют `ownedUserIds() throws` напрямую.
    func getAllUserIds() -> [String] {
        (try? ownedUserIds()) ?? []
    }

    /// UID'ы токенов, принадлежащих текущему пользователю.
    /// Ошибки Keychain пробрасываются: временная недоступность
    /// хранилища не должна выглядеть как «токенов нет».
    func ownedUserIds() throws -> [String] {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return []
        }

        try Self.migrateOwnedTokensIfNeeded(ownerID: ownerID)

        var uids = Set<String>()
        for account in try KeychainItemStore.allAccountsResult() {
            switch Self.classify(account) {
            case .scoped(let scopedOwner, let uid):
                if scopedOwner == ownerID {
                    uids.insert(uid)
                }
            case .legacy(let uid):
                if try Self.ownerIDResult(forDropboxUID: uid) == ownerID {
                    uids.insert(uid)
                }
            case nil:
                continue
            }
        }
        return uids.sorted()
    }

    /// Проверяет, что `uid` принадлежит `ownerID` — по scoped-аккаунту
    /// или по legacy owner-маппингу. Используется QR-переносом,
    /// где владелец передаётся явно, а не через CurrentUserContext.
    func isTokenOwned(uid: String, ownerID: String) throws -> Bool {
        guard !ownerID.isEmpty else { return false }
        if try KeychainItemStore.loadResult(
            account: Self.scopedAccount(for: ownerID, uid: uid)
        ) != nil {
            return true
        }
        guard try Self.ownerIDResult(forDropboxUID: uid) == ownerID else {
            return false
        }
        return try KeychainItemStore.loadResult(
            account: Self.legacyTokenAccount(for: uid)
        ) != nil
    }

    /// Полный `DropboxAccessToken` текущего владельца.
    /// Бросает ошибки Keychain; `nil` — записи нет или она
    /// недоступна текущему владельцу.
    func loadOwnedAccessToken(for uid: String) throws -> DropboxAccessToken? {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return nil
        }

        let scopedAccount = Self.scopedAccount(for: ownerID, uid: uid)
        if let data = try KeychainItemStore.loadResult(account: scopedAccount) {
            // Scoped-запись — источник истины: если она повреждена,
            // не откатываемся на legacy, чтобы не понизить токен.
            return Self.decodeToken(data, uid: uid)
        }

        guard try Self.ownerIDResult(forDropboxUID: uid) == ownerID else {
            return nil
        }
        guard let data = try KeychainItemStore.loadResult(
            account: Self.legacyTokenAccount(for: uid)
        ) else {
            return nil
        }
        return Self.decodeToken(data, uid: uid)
    }

    /// Удаляет токен `uid` только если он принадлежит текущему
    /// пользователю: scoped-аккаунт + legacy-запись с его owner-маппингом.
    func deleteOwnedToken(for uid: String) throws {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return
        }
        try KeychainItemStore.delete(
            account: Self.scopedAccount(for: ownerID, uid: uid)
        )
        if try Self.ownerIDResult(forDropboxUID: uid) == ownerID {
            try KeychainItemStore.delete(
                account: Self.legacyTokenAccount(for: uid)
            )
            try KeychainItemStore.delete(
                account: Self.ownerAccount(for: uid)
            )
        }
    }

    /// Defense-in-depth для протокола SDK: даже если токен запросят
    /// по UID напрямую, чужие и «бесхозные» записи не отдаются.
    func getDropboxAccessToken(for key: String) -> DropboxAccessToken? {
        try? loadOwnedAccessToken(for: key)
    }

    /// `deleteInfo(for:)` в SDK вызывается для конкретного токена.
    /// Удаляем только запись текущего владельца — `unlinkClients()`
    /// не должен стирать сессии других пользователей ClaudVault.
    func deleteInfo(for key: String) -> Bool {
        do {
            try deleteOwnedToken(for: key)
            return true
        } catch {
            return false
        }
    }

    /// Аналог `clearStoredAccessTokens`, но scoped по текущему
    /// владельцу: SDK-семантика «все ключи» здесь означала бы
    /// удаление чужих сессий, что недопустимо.
    func deleteInfoForAllKeys() -> Bool {
        guard let ownerID = CurrentUserContext.shared.ownerID,
              !ownerID.isEmpty else {
            return true
        }
        do {
            for account in try KeychainItemStore.allAccountsResult() {
                switch Self.classify(account) {
                case .scoped(let scopedOwner, _):
                    if scopedOwner == ownerID {
                        try KeychainItemStore.delete(account: account)
                    }
                case .legacy(let uid):
                    if try Self.ownerIDResult(forDropboxUID: uid) == ownerID {
                        try KeychainItemStore.delete(
                            account: Self.legacyTokenAccount(for: uid)
                        )
                        try KeychainItemStore.delete(
                            account: Self.ownerAccount(for: uid)
                        )
                    }
                case nil:
                    continue
                }
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Legacy cleanup

    /// Удаляет Dropbox-токены без доказуемого владельца — наследие
    /// версии до owner-изоляции. Ошибка чтения owner-маппинга
    /// НЕ считается отсутствием владельца: при ней запись сохраняется.
    static func deleteOrphanedTokens() {
        guard let accounts = try? KeychainItemStore.allAccountsResult()
        else {
            // Keychain недоступен — ничего не удаляем.
            return
        }

        let tokenUIDs = Set(accounts.compactMap { account -> String? in
            switch classify(account) {
            case .scoped(_, let uid), .legacy(let uid):
                return uid
            case nil:
                return nil
            }
        })

        for account in accounts {
            switch classify(account) {
            case .scoped:
                // Scoped-запись всегда содержит владельца.
                continue
            case .legacy(let uid):
                let ownerData: Data?
                do {
                    ownerData = try KeychainItemStore.loadResult(
                        account: ownerAccount(for: uid)
                    )
                } catch {
                    // Временная ошибка Keychain — не трогаем токен.
                    continue
                }
                guard ownerData == nil else { continue }
                // Владельца доказуемо нет — удаляем токен и пустой
                // owner-ключ (если он есть).
                try? KeychainItemStore.delete(
                    account: legacyTokenAccount(for: uid)
                )
                try? KeychainItemStore.delete(
                    account: ownerAccount(for: uid)
                )
            case nil:
                continue
            }
        }

        // Owner-маппинги без соответствующего токена — мусор.
        for account in accounts where account.hasPrefix(ownerPrefix) {
            let uid = String(account.dropFirst(ownerPrefix.count))
            if !tokenUIDs.contains(uid) {
                try? KeychainItemStore.delete(account: account)
            }
        }
    }

    // MARK: - Account helpers

    /// `dropbox-sdk|<ownerID>|<uid>`: владелец — первый сегмент,
    /// UID — остаток (UID Dropbox не содержит `|`).
    static func scopedAccount(for ownerID: String, uid: String) -> String {
        "\(accountPrefix)\(ownerID)|\(uid)"
    }

    /// Legacy SDK-аккаунт `dropbox-sdk|<uid>` — до scoped-миграции.
    static func legacyTokenAccount(for uid: String) -> String {
        "\(accountPrefix)\(uid)"
    }

    private static func ownerAccount(for uid: String) -> String {
        "\(ownerPrefix)\(uid)"
    }

    /// Разбирает account Dropbox-токена. `nil` — не токен
    /// (owner-маппинг, CloudAccountSession и т.п.).
    static func classify(_ account: String) -> AccountKind? {
        guard account.hasPrefix(accountPrefix) else { return nil }
        let rest = String(account.dropFirst(accountPrefix.count))
        guard !rest.isEmpty else { return nil }

        if let separator = rest.firstIndex(of: "|") {
            let ownerID = String(rest[..<separator])
            let uid = String(rest[rest.index(after: separator)...])
            guard !ownerID.isEmpty, !uid.isEmpty else { return nil }
            return .scoped(ownerID: ownerID, uid: uid)
        }
        return .legacy(uid: rest)
    }

    /// Владелец legacy-токена из `dropbox-owner|<uid>`.
    /// Ошибки Keychain пробрасываются — `nil` означает только
    /// «записи нет» или повреждённые данные.
    static func ownerIDResult(forDropboxUID uid: String) throws -> String? {
        guard let data = try KeychainItemStore.loadResult(
            account: ownerAccount(for: uid)
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Token coding

    /// JSON — основной формат SDK 10.x. String-fallback оставлен
    /// только для данных, которые точно не JSON (старые версии
    /// хранили access token строкой): повреждённый JSON не должен
    /// превращаться в токен без refresh/expiration.
    private static func decodeToken(_ data: Data, uid: String) -> DropboxAccessToken? {
        if let token = try? JSONDecoder().decode(
            DropboxAccessToken.self, from: data
        ) {
            return token
        }
        guard !looksLikeJSON(data),
              let accessToken = String(data: data, encoding: .utf8),
              !accessToken.isEmpty else {
            return nil
        }
        return DropboxAccessToken(accessToken: accessToken, uid: uid)
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                index = data.index(after: index)
                continue
            }
            return byte == 0x7B || byte == 0x5B // '{' or '['
        }
        return false
    }

    // MARK: - Migrations

    /// Legacy `dropbox-sdk|<uid>` + owner-маппинг → scoped-аккаунт.
    /// Best-effort: при любой ошибке записи/проверки legacy-запись
    /// сохраняется и остаётся читаемой через owner-маппинг.
    private static func migrateOwnedTokensIfNeeded(ownerID: String) throws {
        let accounts = try KeychainItemStore.allAccountsResult()
        var scopedUIDs = Set<String>()
        for account in accounts {
            if case .scoped(let scopedOwner, let uid) = classify(account),
               scopedOwner == ownerID {
                scopedUIDs.insert(uid)
            }
        }

        for account in accounts {
            guard case .legacy(let uid) = classify(account),
                  try ownerIDResult(forDropboxUID: uid) == ownerID else {
                continue
            }

            let legacyAccount = legacyTokenAccount(for: uid)
            let scopedAccount = scopedAccount(for: ownerID, uid: uid)

            if scopedUIDs.contains(uid) {
                // Scoped уже есть — legacy можно убрать, но только
                // если scoped реально читается.
                if (try? KeychainItemStore.loadResult(account: scopedAccount)) != nil {
                    try? KeychainItemStore.delete(account: legacyAccount)
                    try? KeychainItemStore.delete(account: ownerAccount(for: uid))
                }
                continue
            }

            guard let data = try KeychainItemStore.loadResult(
                account: legacyAccount
            ) else {
                continue
            }

            do {
                try KeychainItemStore.save(data, account: scopedAccount)
                guard try KeychainItemStore.loadResult(account: scopedAccount) == data
                else {
                    continue
                }
                try? KeychainItemStore.delete(account: legacyAccount)
                try? KeychainItemStore.delete(account: ownerAccount(for: uid))
            } catch {
                // Запись/проверка не удалась — legacy остаётся нетронутым.
                continue
            }
        }
    }

    /// Переносит токены, сохранённые `SecureStorageAccessDefaultImpl`
    /// в сервисе `<bundleId>.dropbox.authv2`, в текущее хранилище.
    /// На macOS легаси-айтемы лежат в файловой связке ключей,
    /// поэтому запрос к ним идёт без `kSecUseDataProtectionKeychain`.
    ///
    /// Старый токен удаляется только после успешной записи И
    /// проверки чтения нового; при сбое legacy-запись остаётся,
    /// а migration flag не выставляется — перенос повторится.
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
        // временная ошибка не должна отключать миграцию навсегда.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return
        }

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            defaults.set(true, forKey: Self.migrationFlagKey)
            return
        }

        var allMigrated = true
        for item in items {
            guard let uid = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else {
                continue
            }

            let account = Self.legacyTokenAccount(for: uid)
            do {
                try KeychainItemStore.save(data, account: account)
                guard try KeychainItemStore.loadResult(account: account) == data
                else {
                    allMigrated = false
                    continue
                }
            } catch {
                allMigrated = false
                continue
            }

            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: uid
            ] as CFDictionary)
        }

        if allMigrated {
            defaults.set(true, forKey: Self.migrationFlagKey)
        }
    }
}

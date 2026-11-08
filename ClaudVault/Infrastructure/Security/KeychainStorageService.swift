import Foundation
import Security

private nonisolated enum KeychainConstants {
    static let service = "com.claudvault.storage.auth"
}

enum KeychainStorageError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidStoredSession
    case missingOwnerID

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain error (OSStatus: \(status))"
        case .invalidStoredSession:
            return "Stored cloud session is invalid"
        case .missingOwnerID:
            return "Cloud session has no owner"
        }
    }
}

/// Низкоуровневое синхронное Key-Value хранилище поверх `SecItem`.
///
/// Используется и `KeychainStorageService` (нормализованные
/// `CloudAccountSession`-записи), и синхронными адаптерами
/// облачных SDK (SwiftyDropbox `SecureStorageAccess`), которым
/// actor-изоляция недоступна. Все операции сериализуются
/// через `NSLock`; `Security` framework сам по себе потокобезопасен.
nonisolated enum KeychainItemStore {

    private static let lock = NSLock()

    static func save(_ data: Data, account: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String:
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainStorageError.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStorageError.unexpectedStatus(addStatus)
        }
    }

    static func load(account: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return data
    }

    static func delete(account: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStorageError.unexpectedStatus(status)
        }
    }

    static func allData() -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [Data] else {
            return []
        }
        return items
    }

    static func allAccounts() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    static func deleteAccounts(withPrefix prefix: String) {
        for account in allAccounts() where account.hasPrefix(prefix) {
            try? delete(account: account)
        }
    }

    static func baseQuery(account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service
        ]

        if let account {
            query[kSecAttrAccount as String] = account
        }

        #if os(macOS)
        // Data Protection Keychain — обязательное условие для macOS:
        // токены не должны попадать в синхронизируемую/файловую
        // связку ключей.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        return query
    }
}

/// Потокобезопасное хранилище сессий облачных аккаунтов.
///
/// Единая точка хранения токенов Google Drive, Dropbox и OneDrive:
/// все записи — generic-password items в системном Keychain
/// с сервисом `com.claudvault.storage.auth`, доступностью
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (не попадает
/// в бэкапы/миграции) и Data Protection Keychain на macOS.
///
/// `CloudAccountSession`-записи — нормализованный индекс
/// (`<provider>|<email>`). Сырые SDK-токены (например,
/// `DropboxAccessToken` под ключом `dropbox-sdk|<uid>`)
/// лежат рядом в том же сервисе, но в `listAllSessions()`
/// не попадают, т.к. не декодируются в `CloudAccountSession`.
actor KeychainStorageService {
    private static let shared = KeychainStorageService()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static func makeDefault() -> KeychainStorageService {
        .shared
    }

    /// Сохраняет сессию под ключом `<ownerID>|<provider>|<email>`.
    /// Сессия без `ownerID` не записывается — несуществующий
    /// владелец означал бы утечку токенов между аккаунтами.
    func saveSession(_ session: CloudAccountSession) throws {
        guard !session.ownerID.isEmpty else {
            throw KeychainStorageError.missingOwnerID
        }
        let account = Self.accountKey(
            ownerID: session.ownerID,
            provider: session.provider,
            userEmail: session.userEmail
        )
        let payload = try encoder.encode(session)
        try KeychainItemStore.save(payload, account: account)
    }

    func loadSession(
        for provider: CloudProviderType,
        email: String,
        ownerID: String
    ) -> CloudAccountSession? {
        guard !ownerID.isEmpty else { return nil }
        let account = Self.accountKey(
            ownerID: ownerID,
            provider: provider,
            userEmail: email
        )
        guard let data = KeychainItemStore.load(account: account) else {
            return nil
        }
        return try? decoder.decode(CloudAccountSession.self, from: data)
    }

    func deleteSession(
        for provider: CloudProviderType,
        email: String,
        ownerID: String
    ) throws {
        guard !ownerID.isEmpty else { return }
        let account = Self.accountKey(
            ownerID: ownerID,
            provider: provider,
            userEmail: email
        )
        try KeychainItemStore.delete(account: account)
    }

    /// Удаляет все `CloudAccountSession`-записи провайдера
    /// текущего пользователя (любой email). Удобно для sign-out,
    /// когда email неизвестен. Чужие сессии не затрагиваются.
    func deleteSessions(
        for provider: CloudProviderType,
        ownerID: String
    ) throws {
        for session in listAllSessions(ownerID: ownerID)
        where session.provider == provider {
            try deleteSession(
                for: provider,
                email: session.userEmail,
                ownerID: ownerID
            )
        }
    }

    /// Все `CloudAccountSession`-записи указанного пользователя.
    /// Записи других владельцев и записи без ownerID не возвращаются.
    func listAllSessions(ownerID: String) -> [CloudAccountSession] {
        guard !ownerID.isEmpty else { return [] }
        // allData() возвращает только значения, поэтому принадлежность
        // проверяем по ownerID внутри самого payload — этого достаточно:
        // чужие и бесхозные ("") записи отбрасываются декодером-фильтром.
        return KeychainItemStore.allData().compactMap { data in
            guard let session = try? decoder.decode(
                CloudAccountSession.self, from: data
            ), session.ownerID == ownerID else {
                return nil
            }
            return session
        }
    }

    /// Удаляет `CloudAccountSession`-записи старого формата
    /// `<provider>|<email>` — без владельца они содержат
    /// access/refresh-токены и не могут быть безопасно привязаны
    /// ни к одному аккаунту. Вызывается один раз при входе
    /// пользователя — см. `UserSessionCoordinator`. Пользователю
    /// достаточно один раз переподключить облачные сервисы.
    @discardableResult
    func deleteLegacySessions() -> Int {
        var deleted = 0
        for account in KeychainItemStore.allAccounts() {
            // Новый формат: "<ownerID>|<provider>|<email>" — 2 разделителя.
            // Провайдерские служебные ключи ("dropbox-sdk|…",
            // "google-restored|…", "onedrive|tokens|…") отсекаются
            // проверкой первого компонента на CloudProviderType
            // и неудачным декодированием ниже.
            let parts = account.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  CloudProviderType(rawValue: String(parts[0])) != nil,
                  let data = KeychainItemStore.load(account: account),
                  let session = try? decoder.decode(
                      CloudAccountSession.self, from: data
                  ), session.ownerID.isEmpty else {
                continue
            }
            try? KeychainItemStore.delete(account: account)
            deleted += 1
        }
        return deleted
    }

    private static func accountKey(
        ownerID: String,
        provider: CloudProviderType,
        userEmail: String
    ) -> String {
        let normalizedEmail = userEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return "\(ownerID)|\(provider.rawValue)|\(normalizedEmail)"
    }
}

import Foundation
import Security

private nonisolated enum KeychainConstants {
    static let service = "com.claudvault.storage.auth"
}

enum KeychainStorageError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidStoredSession

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain error (OSStatus: \(status))"
        case .invalidStoredSession:
            return "Stored cloud session is invalid"
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

    func saveSession(_ session: CloudAccountSession) throws {
        let account = Self.accountKey(
            provider: session.provider,
            userEmail: session.userEmail
        )
        let payload = try encoder.encode(session)
        try KeychainItemStore.save(payload, account: account)
    }

    func loadSession(
        for provider: CloudProviderType,
        email: String
    ) -> CloudAccountSession? {
        let account = Self.accountKey(provider: provider, userEmail: email)
        guard let data = KeychainItemStore.load(account: account) else {
            return nil
        }
        return try? decoder.decode(CloudAccountSession.self, from: data)
    }

    func deleteSession(
        for provider: CloudProviderType,
        email: String
    ) throws {
        let account = Self.accountKey(provider: provider, userEmail: email)
        try KeychainItemStore.delete(account: account)
    }

    /// Удаляет все `CloudAccountSession`-записи провайдера
    /// (любой email). Удобно для sign-out, когда email неизвестен.
    func deleteSessions(for provider: CloudProviderType) throws {
        for session in listAllSessions() where session.provider == provider {
            try deleteSession(for: provider, email: session.userEmail)
        }
    }

    func listAllSessions() -> [CloudAccountSession] {
        KeychainItemStore.allData().compactMap { data in
            try? decoder.decode(CloudAccountSession.self, from: data)
        }
    }

    private static func accountKey(
        provider: CloudProviderType,
        userEmail: String
    ) -> String {
        let normalizedEmail = userEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return "\(provider.rawValue)|\(normalizedEmail)"
    }
}

import Foundation
import OSLog

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
///
/// Все операции throwing: «записи нет» (`load` → nil) не должна
/// маскироваться под ошибку доступа или повреждённые данные —
/// вызывающий код обязан различать эти случаи.
struct GoogleSessionStore {

    private static let logger = Logger(
        subsystem: "ClaudVault",
        category: "google-session-store"
    )

    private static let accountPrefix = "google-restored|session"
    /// Легаси-ключ до версионирования по ownerID.
    private static let legacyAccount = "google-restored|session"

    /// Читает сессию владельца. `nil` — записи нет;
    /// ошибка Keychain и битый JSON пробрасываются как `throw`,
    /// запись при этом не удаляется.
    func load(ownerID: String) throws -> GoogleRestoredSession? {
        guard !ownerID.isEmpty else {
            throw KeychainStorageError.missingOwnerID
        }
        guard let data = try KeychainItemStore.loadResult(
            account: Self.account(for: ownerID)
        ) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(GoogleRestoredSession.self, from: data)
        } catch {
            throw KeychainStorageError.invalidStoredSession
        }
    }

    func save(_ session: GoogleRestoredSession, ownerID: String) throws {
        guard !ownerID.isEmpty else {
            throw KeychainStorageError.missingOwnerID
        }
        let data = try JSONEncoder().encode(session)
        try KeychainItemStore.save(data, account: Self.account(for: ownerID))
    }

    /// Удаление идемпотентно: отсутствие записи — не ошибка.
    func delete(ownerID: String) throws {
        guard !ownerID.isEmpty else {
            throw KeychainStorageError.missingOwnerID
        }
        try KeychainItemStore.delete(account: Self.account(for: ownerID))
    }

    /// Удаляет легаси-ключ `google-restored|session`, оставшийся
    /// от версии без owner-изоляции. Вызывается один раз при входе
    /// пользователя — см. `UserSessionCoordinator`.
    static func deleteLegacyItem() {
        do {
            try KeychainItemStore.delete(account: legacyAccount)
        } catch {
            logger.error(
                "Failed to delete legacy Google session item: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private

    private static func account(for ownerID: String) -> String {
        "\(accountPrefix)|\(ownerID)"
    }
}

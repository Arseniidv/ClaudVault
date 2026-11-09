import XCTest
import Security
@testable import ClaudVault
import ClaudVaultDomain

/// Тесты Keychain-хранилища восстановленных Google-сессий
/// и обмена refresh token в `GoogleOAuthManager`.
///
/// Используется реальный Keychain (как в AccountIsolationTests):
/// в unsigned-билдах операции падают с errSecMissingEntitlement —
/// такие тесты пропускаются через XCTSkip. «Новый экземпляр
/// store» здесь — это новая итерация жизни процесса внутри
/// тест-раннера; проверка именно завершения процесса — в
/// ручном чек-листе на устройстве.
@MainActor
final class GoogleSessionStoreTests: XCTestCase {

    private let ownerA = "owner-A-\(UUID().uuidString)"
    private let ownerB = "owner-B-\(UUID().uuidString)"
    private let store = GoogleSessionStore()

    override func tearDown() {
        CurrentUserContext.shared.set(nil)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Пропускает тест, если Keychain недоступен (сборка без подписи).
    private func requireKeychain(file: StaticString = #filePath, line: UInt = #line) throws {
        let probeAccount = "google-session-tests-probe-\(UUID().uuidString)"
        do {
            try KeychainItemStore.save(Data("probe".utf8), account: probeAccount)
            try? KeychainItemStore.delete(account: probeAccount)
        } catch KeychainStorageError.unexpectedStatus(let status)
                    where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain недоступен без code signing", file: file, line: line)
        } catch {
            // Прочие ошибки не фатальны для самого факта доступности.
        }
    }

    private func makeSession(
        refreshToken: String = "rt-synthetic",
        accessToken: String? = nil,
        expiresAt: Date? = nil
    ) -> GoogleRestoredSession {
        GoogleRestoredSession(
            refreshToken: refreshToken,
            clientID: "test-client-id",
            userID: "user-synthetic",
            email: "synthetic@example.com",
            displayName: nil,
            grantedScopes: [GoogleOAuthManager.driveScope],
            accessToken: accessToken,
            accessTokenExpiresAt: expiresAt
        )
    }

    private func makeManager(
        exchangeCalls: ExchangeCallCounter,
        outcome: @escaping @MainActor (GoogleRestoredSession) async -> GoogleOAuthManager.RestoredTokenExchange
    ) -> GoogleOAuthManager {
        GoogleOAuthManager(clientID: "test-client-id") { session in
            exchangeCalls.increment()
            return await outcome(session)
        }
    }

    /// Счётчик вызовов exchange, безопасный для async-контекста.
    private final class ExchangeCallCounter: @unchecked Sendable {
        private var count = 0
        private let lock = NSLock()

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    // MARK: - Store: persistence & isolation

    func testSaveLoadRoundTrip() throws {
        try requireKeychain()
        let expires = Date().addingTimeInterval(3600)
        let session = makeSession(
            accessToken: "at-synthetic",
            expiresAt: expires
        )
        try store.save(session, ownerID: ownerA)
        defer { try? store.delete(ownerID: ownerA) }

        // «Новый экземпляр store» — имитация повторного чтения
        // после перезапуска внутри одного процесса.
        let loaded = try GoogleSessionStore().load(ownerID: ownerA)
        XCTAssertEqual(loaded?.refreshToken, "rt-synthetic")
        XCTAssertEqual(loaded?.accessToken, "at-synthetic")
        XCTAssertEqual(loaded?.accessTokenExpiresAt, expires)
        XCTAssertEqual(loaded?.clientID, "test-client-id")
    }

    func testOtherOwnerCannotReadSession() throws {
        try requireKeychain()
        try store.save(makeSession(), ownerID: ownerA)
        defer { try? store.delete(ownerID: ownerA) }

        XCTAssertNil(try store.load(ownerID: ownerB))
        XCTAssertNotNil(try store.load(ownerID: ownerA))
    }

    func testMissingRecordReturnsNil() throws {
        try requireKeychain()
        // Случайный ownerID, под которым ничего не сохранялось.
        let unknownOwner = "owner-unknown-\(UUID().uuidString)"
        XCTAssertNil(try store.load(ownerID: unknownOwner))
    }

    func testEmptyOwnerIDIsRejected() throws {
        try requireKeychain()
        XCTAssertThrowsError(try store.save(makeSession(), ownerID: "")) { error in
            guard case KeychainStorageError.missingOwnerID = error else {
                return XCTFail("Ожидался missingOwnerID, получено \(error)")
            }
        }
        XCTAssertThrowsError(try store.load(ownerID: "")) { error in
            guard case KeychainStorageError.missingOwnerID = error else {
                return XCTFail("Ожидался missingOwnerID, получено \(error)")
            }
        }
        XCTAssertThrowsError(try store.delete(ownerID: "")) { error in
            guard case KeychainStorageError.missingOwnerID = error else {
                return XCTFail("Ожидался missingOwnerID, получено \(error)")
            }
        }
    }

    func testCorruptRecordThrowsAndIsNotDeleted() throws {
        try requireKeychain()
        let account = "google-restored|session|\(ownerA)"
        let garbage = Data("not-json".utf8)
        var insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.claudvault.storage.auth",
            kSecAttrAccount as String: account,
            kSecValueData as String: garbage,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        #if os(macOS)
        insert[kSecUseDataProtectionKeychain as String] = true
        #endif
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw XCTSkip("Keychain недоступен (status \(addStatus))")
        }
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.claudvault.storage.auth",
                kSecAttrAccount as String: account
            ] as CFDictionary)
        }

        // Ошибка декодирования — throw, а не тихий nil;
        // сама запись при этом НЕ удаляется.
        XCTAssertThrowsError(try store.load(ownerID: ownerA)) { error in
            guard case KeychainStorageError.invalidStoredSession = error else {
                return XCTFail("Ожидался invalidStoredSession, получено \(error)")
            }
        }
        XCTAssertNotNil(KeychainItemStore.load(account: account))
    }

    func testDeleteIsIdempotentAndLegacyCleanupKeepsScopedRecords() throws {
        try requireKeychain()
        try store.save(makeSession(), ownerID: ownerA)

        try store.delete(ownerID: ownerA)
        XCTAssertNil(try store.load(ownerID: ownerA))
        // Повторное удаление отсутствующей записи — не ошибка.
        try store.delete(ownerID: ownerA)

        // deleteLegacyItem удаляет только ключ без владельца,
        // owner-scoped записи не трогает.
        try store.save(makeSession(), ownerID: ownerA)
        defer { try? store.delete(ownerID: ownerA) }
        GoogleSessionStore.deleteLegacyItem()
        XCTAssertNotNil(try store.load(ownerID: ownerA))
    }

    // MARK: - OAuthManager: restored-session refresh

    func testExpiredTokenIsRefreshedAndStored() async throws {
        try requireKeychain()
        CurrentUserContext.shared.set(ownerA)
        try store.save(makeSession(), ownerID: ownerA)
        defer {
            CurrentUserContext.shared.set(nil)
            try? store.delete(ownerID: ownerA)
        }

        let counter = ExchangeCallCounter()
        let manager = makeManager(exchangeCalls: counter) { _ in
            .success(accessToken: "at-new", expiresIn: 3600, refreshToken: nil)
        }

        let token = try await manager.freshAccessToken()
        XCTAssertEqual(token, "at-new")
        XCTAssertEqual(counter.value, 1)

        let stored = try store.load(ownerID: ownerA)
        XCTAssertEqual(stored?.accessToken, "at-new")
        XCTAssertNotNil(stored?.accessTokenExpiresAt)
        // refresh_token не вернулся в ответе — прежний сохранён.
        XCTAssertEqual(stored?.refreshToken, "rt-synthetic")
    }

    func testRotatedRefreshTokenIsPersisted() async throws {
        try requireKeychain()
        CurrentUserContext.shared.set(ownerA)
        try store.save(makeSession(), ownerID: ownerA)
        defer {
            CurrentUserContext.shared.set(nil)
            try? store.delete(ownerID: ownerA)
        }

        let counter = ExchangeCallCounter()
        let manager = makeManager(exchangeCalls: counter) { _ in
            .success(accessToken: "at-new", expiresIn: 3600, refreshToken: "rt-rotated")
        }

        _ = try await manager.freshAccessToken()
        let stored = try store.load(ownerID: ownerA)
        XCTAssertEqual(stored?.refreshToken, "rt-rotated")
    }

    func testValidCachedTokenSkipsExchange() async throws {
        try requireKeychain()
        CurrentUserContext.shared.set(ownerA)
        try store.save(makeSession(
            accessToken: "at-cached",
            expiresAt: Date().addingTimeInterval(3600)
        ), ownerID: ownerA)
        defer {
            CurrentUserContext.shared.set(nil)
            try? store.delete(ownerID: ownerA)
        }

        let counter = ExchangeCallCounter()
        let manager = makeManager(exchangeCalls: counter) { _ in
            .success(accessToken: "at-should-not-be-used", expiresIn: 3600, refreshToken: nil)
        }

        let token = try await manager.freshAccessToken()
        XCTAssertEqual(token, "at-cached")
        XCTAssertEqual(counter.value, 0)
    }

    func testInvalidGrantDeletesSession() async throws {
        try requireKeychain()
        CurrentUserContext.shared.set(ownerA)
        try store.save(makeSession(), ownerID: ownerA)
        defer {
            CurrentUserContext.shared.set(nil)
            try? store.delete(ownerID: ownerA)
        }

        let counter = ExchangeCallCounter()
        let manager = makeManager(exchangeCalls: counter) { _ in
            .invalidGrant
        }

        do {
            _ = try await manager.freshAccessToken()
            XCTFail("Ожидалась ошибка notSignedIn")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(error, .notSignedIn)
        }
        // Протухший refresh token — сессия удалена,
        // повторное использование невозможно.
        XCTAssertNil(try store.load(ownerID: ownerA))
    }

    func testConcurrentRefreshesShareSingleExchange() async throws {
        try requireKeychain()
        CurrentUserContext.shared.set(ownerA)
        try store.save(makeSession(), ownerID: ownerA)
        defer {
            CurrentUserContext.shared.set(nil)
            try? store.delete(ownerID: ownerA)
        }

        let counter = ExchangeCallCounter()
        let manager = makeManager(exchangeCalls: counter) { _ in
            // Небольшая задержка гарантирует пересечение вызовов.
            try? await Task.sleep(nanoseconds: 100_000_000)
            return .success(accessToken: "at-shared", expiresIn: 3600, refreshToken: nil)
        }

        async let first = manager.freshAccessToken()
        async let second = manager.freshAccessToken()
        let (tokenA, tokenB) = try await (first, second)

        XCTAssertEqual(tokenA, "at-shared")
        XCTAssertEqual(tokenB, "at-shared")
        XCTAssertEqual(counter.value, 1)
    }

    func testLateRefreshAfterOwnerSwitchDoesNotWrite() async throws {
        try requireKeychain()
        CurrentUserContext.shared.set(ownerA)
        try store.save(makeSession(), ownerID: ownerA)
        defer {
            CurrentUserContext.shared.set(nil)
            try? store.delete(ownerID: ownerA)
            try? store.delete(ownerID: ownerB)
        }

        // Exchange «зависает», пока тест не переключит владельца.
        final class ResumeBox: @unchecked Sendable {
            var continuation: CheckedContinuation<
                GoogleOAuthManager.RestoredTokenExchange, Never
            >?
        }
        let box = ResumeBox()
        let manager = GoogleOAuthManager(clientID: "test-client-id") { _ in
            await withCheckedContinuation { continuation in
                box.continuation = continuation
            }
        }

        async let pending = manager.freshAccessToken()
        // Даём обмену начаться.
        try await Task.sleep(nanoseconds: 100_000_000)

        // Пользователь вышел/сменился, пока шёл сетевой запрос.
        CurrentUserContext.shared.set(ownerB)
        box.continuation?.resume(returning: .success(
            accessToken: "at-late",
            expiresIn: 3600,
            refreshToken: nil
        ))

        do {
            _ = try await pending
            XCTFail("Ожидалась CancellationError")
        } catch is CancellationError {
            // Ожидаемо: поздний результат не должен записаться.
        }

        // Сессия ownerA не должна содержать access token —
        // save пропущен из-за смены владельца.
        let stored = try store.load(ownerID: ownerA)
        XCTAssertNil(stored?.accessToken)
        XCTAssertNil(try store.load(ownerID: ownerB))
    }
}

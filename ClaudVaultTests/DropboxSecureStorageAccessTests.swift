import XCTest
import Security
import SwiftyDropbox
@testable import ClaudVault

/// Тесты owner-scoped хранения Dropbox-токенов.
/// Keychain в unsigned-билдах может быть недоступен — такие тесты
/// пропускаются по аналогии с AccountIsolationTests.
final class DropboxSecureStorageAccessTests: XCTestCase {

    override func tearDown() {
        CurrentUserContext.shared.set(nil)
        super.tearDown()
    }

    // MARK: - Account parsing

    func testClassifyScopedAndLegacyAccounts() {
        XCTAssertEqual(
            DropboxSecureStorageAccess.classify("dropbox-sdk|owner-1|uid-1"),
            .scoped(ownerID: "owner-1", uid: "uid-1")
        )
        XCTAssertEqual(
            DropboxSecureStorageAccess.classify("dropbox-sdk|uid-1"),
            .legacy(uid: "uid-1")
        )
        XCTAssertNil(DropboxSecureStorageAccess.classify("dropbox-owner|uid-1"))
        XCTAssertNil(DropboxSecureStorageAccess.classify("owner|dropbox|email"))
    }

    // MARK: - Scoped storage

    func testScopedTokenRoundTripKeepsRefreshToken() throws {
        try requireKeychain()
        let owner = "owner-\(UUID().uuidString)"
        let otherOwner = "other-\(UUID().uuidString)"
        let uid = "uid-\(UUID().uuidString)"
        let storage = DropboxSecureStorageAccess()
        let token = DropboxAccessToken(
            accessToken: "access-\(UUID().uuidString)",
            uid: uid,
            refreshToken: "refresh-\(UUID().uuidString)",
            tokenExpirationTimestamp: 4_000_000_000
        )
        let data = try JSONEncoder().encode(token)

        CurrentUserContext.shared.set(owner)
        XCTAssertTrue(storage.setAccessTokenData(for: uid, data: data))
        defer { cleanup(uid: uid, owners: [owner, otherOwner]) }

        let loaded = try storage.loadOwnedAccessToken(for: uid)
        XCTAssertEqual(loaded?.accessToken, token.accessToken)
        XCTAssertEqual(loaded?.refreshToken, token.refreshToken)
        XCTAssertEqual(
            loaded?.tokenExpirationTimestamp,
            token.tokenExpirationTimestamp
        )
        XCTAssertEqual(try storage.ownedUserIds(), [uid])

        // Другой владелец не видит и не может прочитать токен.
        CurrentUserContext.shared.set(otherOwner)
        XCTAssertEqual(try storage.ownedUserIds(), [])
        XCTAssertNil(try storage.loadOwnedAccessToken(for: uid))
        XCTAssertNil(storage.getDropboxAccessToken(for: uid))

        // Тот же Dropbox UID у другого пользователя — независимая запись.
        let otherToken = DropboxAccessToken(
            accessToken: "other-access",
            uid: uid,
            refreshToken: "other-refresh",
            tokenExpirationTimestamp: 4_000_000_100
        )
        let otherData = try JSONEncoder().encode(otherToken)
        XCTAssertTrue(storage.setAccessTokenData(for: uid, data: otherData))
        let loadedOther = try storage.loadOwnedAccessToken(for: uid)
        XCTAssertEqual(loadedOther?.refreshToken, "other-refresh")

        CurrentUserContext.shared.set(owner)
        let loadedOwner = try storage.loadOwnedAccessToken(for: uid)
        XCTAssertEqual(loadedOwner?.refreshToken, token.refreshToken)
    }

    func testCorruptJSONIsNotTreatedAsStringToken() throws {
        try requireKeychain()
        let owner = "owner-\(UUID().uuidString)"
        let uid = "uid-\(UUID().uuidString)"
        CurrentUserContext.shared.set(owner)
        defer { cleanup(uid: uid, owners: [owner]) }

        let storage = DropboxSecureStorageAccess()
        let account = DropboxSecureStorageAccess.scopedAccount(
            for: owner,
            uid: uid
        )
        try KeychainItemStore.save(
            Data("{\"accessToken\":".utf8),
            account: account
        )

        XCTAssertNil(try storage.loadOwnedAccessToken(for: uid))
        XCTAssertNil(storage.getDropboxAccessToken(for: uid))
    }

    func testPlainStringFallbackHasNoRefreshToken() throws {
        try requireKeychain()
        let owner = "owner-\(UUID().uuidString)"
        let uid = "uid-\(UUID().uuidString)"
        CurrentUserContext.shared.set(owner)
        defer { cleanup(uid: uid, owners: [owner]) }

        let storage = DropboxSecureStorageAccess()
        let account = DropboxSecureStorageAccess.scopedAccount(
            for: owner,
            uid: uid
        )
        try KeychainItemStore.save(
            Data("legacy-access-token".utf8),
            account: account
        )

        let loaded = try storage.loadOwnedAccessToken(for: uid)
        XCTAssertEqual(loaded?.accessToken, "legacy-access-token")
        XCTAssertNil(loaded?.refreshToken)
        XCTAssertNil(loaded?.tokenExpirationTimestamp)
    }

    // MARK: - Legacy owner mapping

    func testLegacyTokenMigratesToScopedAccount() throws {
        try requireKeychain()
        let owner = "owner-\(UUID().uuidString)"
        let otherOwner = "other-\(UUID().uuidString)"
        let uid = "uid-\(UUID().uuidString)"
        let storage = DropboxSecureStorageAccess()
        let token = DropboxAccessToken(
            accessToken: "legacy-access",
            uid: uid,
            refreshToken: "legacy-refresh",
            tokenExpirationTimestamp: 4_000_000_000
        )
        let data = try JSONEncoder().encode(token)
        let legacyAccount = DropboxSecureStorageAccess.legacyTokenAccount(for: uid)
        let ownerAccount = "dropbox-owner|\(uid)"

        // Имитируем формат до scoped-аккаунтов.
        try KeychainItemStore.save(data, account: legacyAccount)
        try KeychainItemStore.save(
            Data(owner.utf8),
            account: ownerAccount
        )
        defer { cleanup(uid: uid, owners: [owner, otherOwner]) }

        CurrentUserContext.shared.set(owner)
        XCTAssertEqual(try storage.ownedUserIds(), [uid])
        let loaded = try storage.loadOwnedAccessToken(for: uid)
        XCTAssertEqual(loaded?.refreshToken, "legacy-refresh")

        // После чтения legacy должен переехать в scoped-аккаунт.
        XCTAssertNil(try KeychainItemStore.loadResult(account: legacyAccount))
        XCTAssertNotNil(
            try KeychainItemStore.loadResult(
                account: DropboxSecureStorageAccess.scopedAccount(
                    for: owner,
                    uid: uid
                )
            )
        )

        CurrentUserContext.shared.set(otherOwner)
        XCTAssertEqual(try storage.ownedUserIds(), [])
        XCTAssertNil(try storage.loadOwnedAccessToken(for: uid))
    }

    // MARK: - Helpers

    private func requireKeychain() throws {
        let account = "dropbox-test|\(UUID().uuidString)"
        do {
            try KeychainItemStore.save(Data([1]), account: account)
            try KeychainItemStore.delete(account: account)
        } catch KeychainStorageError.unexpectedStatus(let status)
                    where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain недоступен без code signing")
        } catch {
            throw XCTSkip("Keychain недоступен: \(error)")
        }
    }

    private func cleanup(uid: String, owners: [String]) {
        for owner in owners {
            try? KeychainItemStore.delete(
                account: DropboxSecureStorageAccess.scopedAccount(
                    for: owner,
                    uid: uid
                )
            )
        }
        try? KeychainItemStore.delete(
            account: DropboxSecureStorageAccess.legacyTokenAccount(for: uid)
        )
        try? KeychainItemStore.delete(account: "dropbox-owner|\(uid)")
    }
}

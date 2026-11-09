import XCTest
import SwiftData
import Security
@testable import ClaudVault
import ClaudVaultDomain

/// Регрессионные тесты изоляции пользовательских данных:
/// после выхода пользователя A и входа пользователя B
/// ни SwiftData-записи, ни Keychain-токены A не должны
/// быть видны B — даже при полном Logout/Login цикле.
@MainActor
final class AccountIsolationTests: XCTestCase {

    private let ownerA = "owner-A-\(UUID().uuidString)"
    private let ownerB = "owner-B-\(UUID().uuidString)"

    override func tearDown() {
        CurrentUserContext.shared.set(nil)
        super.tearDown()
    }

    // MARK: - SwiftData

    func testBackupRecordsAreInvisibleToOtherUser() throws {
        let container = try CloudVaultModelContainer.make(inMemory: true)
        let repository = BackupMetadataRepositoryImpl(
            modelContext: container.mainContext
        )

        // Пользователь A создаёт запись.
        CurrentUserContext.shared.set(ownerA)
        let record = BackupRecord(
            id: UUID(),
            fileName: "secret-a.txt",
            sourceIdentifier: "src-a",
            updatedAt: Date()
        )
        try repository.saveRecord(record)
        XCTAssertEqual(try repository.fetchRecords().count, 1)

        // Logout → Login пользователя B: записи A не видны.
        CurrentUserContext.shared.set(ownerB)
        XCTAssertTrue(try repository.fetchRecords().isEmpty)
        XCTAssertNil(try repository.fetchRecord(id: record.id))
        XCTAssertNil(
            try repository.fetchRecord(bySource: "src-a")
        )

        // Обратный вход A — данные на месте.
        CurrentUserContext.shared.set(ownerA)
        XCTAssertEqual(try repository.fetchRecords().count, 1)
    }

    func testUploadSessionsAreInvisibleToOtherUser() async throws {
        let container = try CloudVaultModelContainer.make(inMemory: true)
        let repository = UploadSessionRepositoryImpl(
            modelContainer: container
        )

        CurrentUserContext.shared.set(ownerA)
        try await repository.save(UploadSession(
            id: UUID(),
            fileName: "a.bin",
            fileURL: URL(fileURLWithPath: "/tmp/a.bin"),
            sessionURL: nil,
            totalBytes: 10,
            uploadedBytes: 0,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        ))
        let sessionsA = try await repository.fetchAll()
        XCTAssertEqual(sessionsA.count, 1)

        CurrentUserContext.shared.set(ownerB)
        let sessionsB = try await repository.fetchAll()
        XCTAssertTrue(sessionsB.isEmpty)
    }

    func testPendingTransferRecordsAreInvisibleToOtherUser() async throws {
        let container = try CloudVaultModelContainer.make(inMemory: true)
        let journal = TransferJournalImpl(modelContainer: container)

        CurrentUserContext.shared.set(ownerA)
        try await journal.begin(TransferRecord(
            kind: .upload,
            targetProvider: "google_drive",
            name: "a.bin",
            mimeType: "application/octet-stream",
            sizeBytes: 10
        ))
        let pendingA = try await journal.pendingRecords()
        XCTAssertEqual(pendingA.count, 1)

        // Пользователь B не должен увидеть и тем более
        // возобновить передачу пользователя A.
        CurrentUserContext.shared.set(ownerB)
        let pendingB = try await journal.pendingRecords()
        XCTAssertTrue(pendingB.isEmpty)
    }

    // MARK: - Keychain

    func testCloudAccountSessionsAreScopedByOwner() async throws {
        let keychain = KeychainStorageService.makeDefault()
        let email = "iso-\(UUID().uuidString)@example.com"

        let session = CloudAccountSession(
            provider: .googleDrive,
            userEmail: email,
            accessToken: "token-a",
            refreshToken: "refresh-a",
            ownerID: ownerA
        )
        do {
            try await keychain.saveSession(session)
        } catch KeychainStorageError.unexpectedStatus(let status)
                    where status == errSecMissingEntitlement {
            // Без подписи (CODE_SIGNING_ALLOWED=NO) Keychain
            // недоступен — проверка пропускается в unsigned-билдах.
            throw XCTSkip("Keychain недоступен без code signing")
        }
        defer {
            Task {
                try? await keychain.deleteSession(
                    for: .googleDrive,
                    email: email,
                    ownerID: ownerA
                )
            }
        }

        // Владелец читает свою сессию.
        let loadedA = await keychain.loadSession(
            for: .googleDrive,
            email: email,
            ownerID: ownerA
        )
        XCTAssertEqual(loadedA?.accessToken, "token-a")

        // Другой пользователь — nil, и в списке его нет.
        let loadedB = await keychain.loadSession(
            for: .googleDrive,
            email: email,
            ownerID: ownerB
        )
        XCTAssertNil(loadedB)

        let sessionsB = await keychain.listAllSessions(ownerID: ownerB)
        XCTAssertFalse(sessionsB.contains { $0.userEmail == email })

        let sessionsA = await keychain.listAllSessions(ownerID: ownerA)
        XCTAssertTrue(sessionsA.contains { $0.userEmail == email })
    }

    func testSessionWithoutOwnerIsRejected() async {
        let keychain = KeychainStorageService.makeDefault()
        let session = CloudAccountSession(
            provider: .dropbox,
            userEmail: "orphan@example.com",
            accessToken: "token",
            ownerID: ""
        )
        do {
            try await keychain.saveSession(session)
            XCTFail("Сессия без владельца не должна сохраняться")
        } catch {
            // Ожидаемо: KeychainStorageError.missingOwnerID
        }
    }
}

import XCTest
import SwiftData
@testable import ClaudVault

@MainActor
final class BackupLifecycleUseCaseTests: XCTestCase {

    // MARK: - Mocks

    private final class MockCloudStorageRepository: CloudStorageRepository {
        var uploadResult: Result<CloudFile, Error> = .success(
            CloudFile(id: "cloud-id", name: "f", mimeType: "text/plain",
                      sizeBytes: 0, modifiedAt: nil)
        )
        var deleteError: Error?
        private(set) var uploadedCount = 0
        private(set) var deletedIDs: [String] = []

        func getStorageUsage() async throws -> CloudStorageUsage {
            CloudStorageUsage(usedBytes: 0, totalBytes: 0, availableBytes: 0)
        }
        func connect() async throws -> CloudStorageAccount {
            throw CloudStorageError.notImplemented
        }
        func restoreConnection() async throws -> CloudStorageAccount? { nil }
        func signOut() async throws {}
        func listFiles(parentFolderID: String?) async throws -> [CloudFile] { [] }
        func fileMetadata(id: String) async throws -> CloudFile {
            throw CloudStorageError.notFound
        }
        func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile {
            throw CloudStorageError.notImplemented
        }
        func uploadFile(
            at fileURL: URL,
            parentFolderID: String?,
            progressHandler: (@Sendable (Double) -> Void)?
        ) async throws -> CloudFile {
            uploadedCount += 1
            progressHandler?(1.0)
            return try uploadResult.get()
        }
        func deleteFile(id: String) async throws {
            deletedIDs.append(id)
            if let deleteError { throw deleteError }
        }
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try CloudVaultModelContainer.make(inMemory: true)
    }

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clv_\(UUID().uuidString).txt")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeReparseUseCase(
        repository: BackupMetadataRepositoryImpl,
        container: ModelContainer,
        cloud: MockCloudStorageRepository
    ) -> ReparseAndBackupUseCase {
        let fileAccess = LocalFileAccess()
        let hasher = SHA256FileHasher()
        let uploadRepository = UploadSessionRepositoryImpl(modelContext: container.mainContext)
        return ReparseAndBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: cloud,
            fileHasher: hasher,
            fileAccessRepository: fileAccess,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: SaveUploadSessionUseCase(repository: uploadRepository),
            updateUploadProgressUseCase: UpdateUploadProgressUseCase(repository: uploadRepository)
        )
    }

    // MARK: - Re-parse: unchanged file must not create a new version

    func testReparseSkipsUnchangedFile() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let cloud = MockCloudStorageRepository()
        let fileURL = try makeTempFile(contents: "hello")

        let record = BackupRecord(
            fileName: "a.txt",
            sourceIdentifier: "test-src"
        )
        try repository.saveRecord(record)

        // Версия с актуальным SHA-256 файла.
        let hasher = SHA256FileHasher()
        let checksum = try hasher.hashFile(at: fileURL)
        let existing = BackupVersion(
            backupRecordID: record.id,
            fileSize: 5,
            checksum: checksum,
            cloudObjectID: "existing-cloud-id"
        )
        try repository.saveVersion(existing, for: record.id)

        let useCase = makeReparseUseCase(
            repository: repository, container: container, cloud: cloud
        )

        let result = try await useCase.execute(
            sourceIdentifier: "test-src",
            fileURL: fileURL,
            parentFolderID: nil
        ) { _ in }

        XCTAssertNil(result, "Файл не изменился — новой версии быть не должно")
        XCTAssertEqual(cloud.uploadedCount, 0, "Загрузка в облако не должна вызываться")

        let versions = try repository.fetchVersions(for: record.id)
        XCTAssertEqual(versions.count, 1)
    }

    // MARK: - Re-parse: changed file creates a new version

    func testReparseCreatesVersionForChangedFile() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let cloud = MockCloudStorageRepository()
        let fileURL = try makeTempFile(contents: "version-1")

        let record = BackupRecord(
            fileName: "a.txt",
            sourceIdentifier: "test-src-2"
        )
        try repository.saveRecord(record)

        let hasher = SHA256FileHasher()
        let oldChecksum = try hasher.hashFile(at: fileURL)
        try repository.saveVersion(
            BackupVersion(
                backupRecordID: record.id,
                fileSize: 9,
                checksum: oldChecksum,
                cloudObjectID: "old-cloud-id"
            ),
            for: record.id
        )

        // Изменяем файл.
        try "version-2-changed".write(to: fileURL, atomically: true, encoding: .utf8)
        
        cloud.uploadResult = .success(
            CloudFile(id: "new-cloud-id", name: "a.txt", mimeType: "text/plain",
                      sizeBytes: 19, modifiedAt: nil)
        )

        let useCase = makeReparseUseCase(
            repository: repository, container: container, cloud: cloud
        )

        let version = try await useCase.execute(
            sourceIdentifier: "test-src-2",
            fileURL: fileURL,
            parentFolderID: nil
        ) { _ in }

        XCTAssertNotNil(version)
        XCTAssertEqual(cloud.uploadedCount, 1)
        XCTAssertEqual(version?.cloudObjectID, "new-cloud-id")

        let versions = try repository.fetchVersions(for: record.id)
        XCTAssertEqual(versions.count, 2)

        // Сессия загрузки завершена.
        let uploadRepository = UploadSessionRepositoryImpl(modelContext: container.mainContext)
        let sessions = try await uploadRepository.fetchAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.status, .completed)
        XCTAssertEqual(sessions.first?.uploadedBytes, sessions.first?.totalBytes)
    }

    // MARK: - Delete: cloud object removed before metadata; 404 tolerated

    func testDeleteVersionDeletesCloudThenMetadata() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let cloud = MockCloudStorageRepository()

        let record = BackupRecord(fileName: "b.txt", sourceIdentifier: "src-del")
        try repository.saveRecord(record)
        let version = BackupVersion(
            backupRecordID: record.id,
            fileSize: 10,
            checksum: "abc",
            cloudObjectID: "cloud-to-delete"
        )
        try repository.saveVersion(version, for: record.id)

        let useCase = DeleteBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: cloud
        )

        try await useCase.execute(version: version)

        XCTAssertEqual(cloud.deletedIDs, ["cloud-to-delete"])
        let remaining = try repository.fetchVersions(for: record.id)
        XCTAssertTrue(remaining.isEmpty, "Метаданные версии должны быть удалены")
    }

    func testDeleteVersionKeepsMetadataWhenCloudFails() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let cloud = MockCloudStorageRepository()
        cloud.deleteError = CloudStorageError.network("offline")

        let record = BackupRecord(fileName: "c.txt", sourceIdentifier: "src-del2")
        try repository.saveRecord(record)
        let version = BackupVersion(
            backupRecordID: record.id,
            fileSize: 10,
            checksum: "abc",
            cloudObjectID: "cloud-still-there"
        )
        try repository.saveVersion(version, for: record.id)

        let useCase = DeleteBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: cloud
        )

        do {
            try await useCase.execute(version: version)
            XCTFail("Ожидалась ошибка удаления из облака")
        } catch {
            // Ожидаемо
        }

        let remaining = try repository.fetchVersions(for: record.id)
        XCTAssertEqual(remaining.count, 1, "Метаданные не должны удаляться при ошибке облака")
    }

    func testDeleteRecordToleratesMissingCloudObject() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let cloud = MockCloudStorageRepository()
        cloud.deleteError = CloudStorageError.notFound

        let record = BackupRecord(fileName: "d.txt", sourceIdentifier: "src-del3")
        try repository.saveRecord(record)
        try repository.saveVersion(
            BackupVersion(
                backupRecordID: record.id,
                fileSize: 10,
                checksum: "abc",
                cloudObjectID: "already-gone"
            ),
            for: record.id
        )

        let useCase = DeleteBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: cloud
        )

        try await useCase.execute(record: record)

        let fetched = try repository.fetchRecord(bySource: "src-del3")
        XCTAssertNil(fetched, "Запись должна быть удалена, если облачный объект уже отсутствует")
    }
}

import XCTest
import SwiftData
@testable import ClaudVault

@MainActor
final class BackupLifecycleUseCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CurrentUserContext.shared.set("test-owner")
    }

    override func tearDown() {
        CurrentUserContext.shared.set(nil)
        super.tearDown()
    }


    // MARK: - Mocks

    private final class MockCloudStorageRepository: CloudStorageRepository {
        var uploadResult: Result<CloudFile, Error> = .success(
            CloudFile(id: "cloud-id", name: "f", mimeType: "text/plain",
                      sizeBytes: 0, modifiedAt: nil)
        )
        var deleteError: Error?
        /// Метаданные для `fileMetadata(id:)` — id → CloudFile.
        var metadataByID: [String: CloudFile] = [:]
        /// Содержимое, которое «скачивается» через `downloadFile`.
        var downloadContents = "hello"
        private(set) var uploadedCount = 0
        private(set) var deletedIDs: [String] = []
        private(set) var downloadedIDs: [String] = []

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
            if let file = metadataByID[id] { return file }
            throw CloudStorageError.notFound
        }
        func downloadFile(
            id: String,
            to destination: URL,
            progressHandler: (@Sendable (Double) -> Void)?
        ) async throws {
            downloadedIDs.append(id)
            try downloadContents.write(
                to: destination, atomically: true, encoding: .utf8
            )
            progressHandler?(1.0)
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
        let uploadRepository = UploadSessionRepositoryImpl(modelContainer: container)
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
        let uploadRepository = UploadSessionRepositoryImpl(modelContainer: container)
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

    // MARK: - Provider routing

    /// Удаление версии должно идти в облако записи
    /// (`record.storageProvider`), а не всегда в Google Drive.
    func testDeleteVersionRoutesToRecordProvider() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let google = MockCloudStorageRepository()
        let dropbox = MockCloudStorageRepository()

        let record = BackupRecord(
            fileName: "e.txt",
            sourceIdentifier: "src-dropbox",
            storageProvider: .dropbox
        )
        try repository.saveRecord(record)
        let version = BackupVersion(
            backupRecordID: record.id,
            fileSize: 10,
            checksum: "abc",
            cloudObjectID: "dropbox-object"
        )
        try repository.saveVersion(version, for: record.id)

        let useCase = DeleteBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: google,
            repositories: [.googleDrive: google, .dropbox: dropbox]
        )

        try await useCase.execute(version: version)

        XCTAssertEqual(dropbox.deletedIDs, ["dropbox-object"])
        XCTAssertTrue(google.deletedIDs.isEmpty)
    }

    /// Создание бэкапа с выбранным облаком: загрузка идёт
    /// в Dropbox, провайдер записи обновляется.
    func testCreateBackupUploadsToSelectedProvider() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let google = MockCloudStorageRepository()
        let dropbox = MockCloudStorageRepository()
        let fileURL = try makeTempFile(contents: "manual-file")

        dropbox.uploadResult = .success(
            CloudFile(id: "dropbox-new", name: "manual-file.txt",
                      mimeType: "text/plain", sizeBytes: 12, modifiedAt: nil)
        )

        let uploadRepository = UploadSessionRepositoryImpl(
            modelContainer: container
        )
        let useCase = CreateBackupWithUploadUseCase(
            backupRepository: repository,
            cloudStorageRepository: google,
            repositories: [.googleDrive: google, .dropbox: dropbox],
            fileHasher: SHA256FileHasher(),
            fileAccessRepository: LocalFileAccess(),
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: SaveUploadSessionUseCase(
                repository: uploadRepository
            ),
            updateUploadProgressUseCase: UpdateUploadProgressUseCase(
                repository: uploadRepository
            )
        )

        let record = try await useCase.execute(
            fileName: "manual-file.txt",
            sourceIdentifier: "src-manual-dropbox",
            fileURL: fileURL,
            parentFolderID: nil,
            storageProvider: .dropbox
        ) { _ in }

        XCTAssertEqual(dropbox.uploadedCount, 1)
        XCTAssertEqual(google.uploadedCount, 0)
        XCTAssertEqual(record.storageProvider, .dropbox)

        let versions = try repository.fetchVersions(for: record.id)
        XCTAssertEqual(versions.first?.cloudObjectID, "dropbox-new")
    }

    /// Повторный анализ загружает новую версию в облако записи.
    func testReparseUploadsToRecordProvider() async throws {
        let container = try makeContainer()
        let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
        let google = MockCloudStorageRepository()
        let dropbox = MockCloudStorageRepository()
        let fileURL = try makeTempFile(contents: "reparse-v2")

        let record = BackupRecord(
            fileName: "r.txt",
            sourceIdentifier: "src-reparse-dropbox",
            storageProvider: .dropbox
        )
        try repository.saveRecord(record)

        dropbox.uploadResult = .success(
            CloudFile(id: "dropbox-v2", name: "r.txt",
                      mimeType: "text/plain", sizeBytes: 11, modifiedAt: nil)
        )

        let uploadRepository = UploadSessionRepositoryImpl(
            modelContainer: container
        )
        let useCase = ReparseAndBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: google,
            repositories: [.googleDrive: google, .dropbox: dropbox],
            fileHasher: SHA256FileHasher(),
            fileAccessRepository: LocalFileAccess(),
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: SaveUploadSessionUseCase(
                repository: uploadRepository
            ),
            updateUploadProgressUseCase: UpdateUploadProgressUseCase(
                repository: uploadRepository
            )
        )

        let version = try await useCase.execute(
            sourceIdentifier: "src-reparse-dropbox",
            fileURL: fileURL,
            parentFolderID: nil
        ) { _ in }

        XCTAssertNotNil(version)
        XCTAssertEqual(version?.cloudObjectID, "dropbox-v2")
        XCTAssertEqual(dropbox.uploadedCount, 1)
        XCTAssertEqual(google.uploadedCount, 0)
    }

    // MARK: - Backup transfer between clouds

    private func makeTransferFixture(
        container: ModelContainer
    ) throws -> (
        repository: BackupMetadataRepositoryImpl,
        google: MockCloudStorageRepository,
        dropbox: MockCloudStorageRepository,
        record: BackupRecord
    ) {
        let repository = BackupMetadataRepositoryImpl(
            modelContext: container.mainContext
        )
        let google = MockCloudStorageRepository()
        let dropbox = MockCloudStorageRepository()

        google.metadataByID["g1"] = CloudFile(
            id: "g1", name: "photo.heic", mimeType: "image/heic",
            sizeBytes: 5, modifiedAt: nil
        )
        dropbox.uploadResult = .success(
            CloudFile(id: "d1", name: "photo.heic", mimeType: "image/heic",
                      sizeBytes: 5, modifiedAt: nil)
        )
        dropbox.metadataByID["d1"] = CloudFile(
            id: "d1", name: "photo.heic", mimeType: "image/heic",
            sizeBytes: 5, modifiedAt: nil
        )
        google.downloadContents = "hello"

        let record = BackupRecord(
            fileName: "photo.heic",
            sourceIdentifier: "src-transfer",
            storageProvider: .googleDrive
        )
        try repository.saveRecord(record)
        try repository.saveVersion(
            BackupVersion(
                backupRecordID: record.id,
                fileSize: 5,
                checksum: "abc",
                cloudObjectID: "g1"
            ),
            for: record.id
        )

        return (repository, google, dropbox, record)
    }

    /// Копирование Google → Dropbox: метаданные версии и
    /// провайдер записи обновляются, источник не удаляется.
    func testTransferBackupCopyGoogleToDropbox() async throws {
        let container = try makeContainer()
        let (repository, google, dropbox, record) =
            try makeTransferFixture(container: container)

        let useCase = TransferBackupToProviderUseCase(
            backupRepository: repository,
            cloudStorageRepository: google,
            repositories: [.googleDrive: google, .dropbox: dropbox],
            transferEngine: nil
        )

        try await useCase.execute(record: record, to: .dropbox, move: false)

        let versions = try repository.fetchVersions(for: record.id)
        XCTAssertEqual(versions.first?.cloudObjectID, "d1")
        XCTAssertEqual(google.downloadedIDs, ["g1"])
        XCTAssertTrue(google.deletedIDs.isEmpty, "copy не удаляет источник")

        let fresh = try repository.fetchRecord(id: record.id)
        XCTAssertEqual(fresh?.storageProvider, .dropbox)
    }

    /// Перемещение Google → Dropbox: источник удаляется
    /// только после успешного копирования и обновления
    /// метаданных.
    func testTransferBackupMoveDeletesSource() async throws {
        let container = try makeContainer()
        let (repository, google, dropbox, record) =
            try makeTransferFixture(container: container)

        let useCase = TransferBackupToProviderUseCase(
            backupRepository: repository,
            cloudStorageRepository: google,
            repositories: [.googleDrive: google, .dropbox: dropbox],
            transferEngine: nil
        )

        try await useCase.execute(record: record, to: .dropbox, move: true)

        XCTAssertEqual(google.deletedIDs, ["g1"])
        let versions = try repository.fetchVersions(for: record.id)
        XCTAssertEqual(versions.first?.cloudObjectID, "d1")
    }
}

import XCTest
@testable import ClaudVault
import ClaudVaultDomain

// MARK: - Mocks

/// Сессия приёмника без сети: принимает чанки, считает
/// подтверждённое смещение, умеет «падать» на выбранном чанке.
private final class MockTransferSession: TransferSession, @unchecked Sendable {
    private(set) var confirmedOffset: Int64
    private let totalSize: Int64
    private let resultHashes: [ContentHash]
    /// Число send-вызовов, после которых сессия «падает».
    var failAfterSends: Int?
    /// Смещение, которое сессия подтверждает за один send
    /// (имитация частичного приёма). nil — принимает весь чанк.
    var partialConfirmTo: Int64?
    /// Каждая отправка «висит» — для теста отмены.
    var delayEachSend = false

    private(set) var sentAbsoluteOffsets: [Int64] = []
    private(set) var sendCount = 0
    private var resultFile: CloudFile?
    private(set) var wasCancelled = false

    init(
        totalSize: Int64,
        confirmedOffset: Int64 = 0,
        resultHashes: [ContentHash] = []
    ) {
        self.totalSize = totalSize
        self.confirmedOffset = confirmedOffset
        self.resultHashes = resultHashes
    }

    var stateValue: String { "mock:\(confirmedOffset)" }

    func send(_ payload: ChunkPayload) async throws {
        sendCount += 1
        if let failAfter = failAfterSends, sendCount > failAfter {
            throw CloudStorageError.rateLimited
        }
        if delayEachSend {
            // Бросает CancellationError при отмене задачи.
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        try Task.checkCancellation()
        sentAbsoluteOffsets.append(payload.absoluteOffset)

        if let partial = partialConfirmTo {
            confirmedOffset = max(confirmedOffset, partial)
        } else {
            confirmedOffset = payload.absoluteOffset + payload.length
        }
        if confirmedOffset >= totalSize {
            resultFile = CloudFile(
                id: "mock-upload",
                name: "uploaded",
                mimeType: "application/octet-stream",
                sizeBytes: totalSize,
                modifiedAt: nil,
                contentHashes: resultHashes
            )
        }
    }

    func finish() async throws -> CloudFile {
        if let resultFile { return resultFile }
        return CloudFile(
            id: "mock-upload",
            name: "uploaded",
            mimeType: "application/octet-stream",
            sizeBytes: totalSize,
            modifiedAt: nil,
            contentHashes: resultHashes
        )
    }

    func cancel() async { wasCancelled = true }
}

/// In-memory журнал передач.
private final class MockJournal: TransferJournal, @unchecked Sendable {
    private var records: [UUID: TransferRecord] = [:]

    func begin(_ record: TransferRecord) async throws {
        records[record.id] = record
    }

    func updateProgress(
        id: UUID,
        offset: Int64?,
        sessionState: String?,
        hashAlgorithm: String?,
        hashValue: String?,
        streamSHA256: String?
    ) async throws {
        guard var record = records[id] else { return }
        if let offset { record.offset = offset }
        if let sessionState { record.sessionState = sessionState }
        records[id] = record
    }

    func setState(
        id: UUID,
        state: TransferRecord.State,
        error: String?
    ) async throws {
        guard var record = records[id] else { return }
        // State — let? проверим TransferRecord: state var?
        record.state = state
        records[id] = record
    }

    func pendingRecords() async throws -> [TransferRecord] {
        records.values.filter {
            [.pending, .uploading, .verifying].contains($0.state)
        }
    }

    func record(id: UUID) async throws -> TransferRecord? {
        records[id]
    }

    func delete(id: UUID) async throws {
        records.removeValue(forKey: id)
    }

    func allRecords() -> [TransferRecord] { Array(records.values) }
}

/// Репозиторий-заглушка: файловые операции не нужны,
/// интересуют только makeUploadSession/fileMetadata/deleteFile.
private final class MockRepository: CloudStorageRepository, @unchecked Sendable {
    var sessionToReturn: (any TransferSession, String)?
    var metadataToReturn: CloudFile?
    var deletedIDs: [String] = []
    var chunkSourceToReturn: (any ChunkSource)?

    func getStorageUsage() async throws -> CloudStorageUsage {
        CloudStorageUsage(usedBytes: 0, totalBytes: 0, availableBytes: 0)
    }
    func connect() async throws -> CloudStorageAccount {
        CloudStorageAccount(id: "acc", email: "t@t", displayName: nil)
    }
    func restoreConnection() async throws -> CloudStorageAccount? { nil }
    func signOut() async throws {}
    func listFiles(parentFolderID: String?) async throws -> [CloudFile] { [] }
    func fileMetadata(id: String) async throws -> CloudFile {
        metadataToReturn ?? CloudFile(
            id: id, name: "f", mimeType: "application/octet-stream",
            sizeBytes: 0, modifiedAt: nil
        )
    }
    func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile {
        CloudFile(id: "dir", name: name, mimeType: CloudFile.folderMimeType, sizeBytes: nil, modifiedAt: nil)
    }
    func uploadFile(
        at fileURL: URL,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        CloudFile(id: "u", name: fileURL.lastPathComponent,
                  mimeType: "application/octet-stream", sizeBytes: 0,
                  modifiedAt: nil)
    }
    func deleteFile(id: String) async throws { deletedIDs.append(id) }

    func makeUploadSession(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64,
        resumeState: String?
    ) async throws -> (session: any TransferSession, state: String)? {
        sessionToReturn
    }

    func makeChunkSource(for file: CloudFile) async throws -> (any ChunkSource)? {
        chunkSourceToReturn
    }
}

// MARK: - Tests

@MainActor
final class TransferEngineTests: XCTestCase {

    private var tempFiles: [URL] = []

    override func tearDown() async throws {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles = []
    }

    // MARK: Helpers

    /// Пишет `size` байт с детерминированным паттерном
    /// (без загрузки всего файла в память).
    private func makeTempFile(size: Int64, fill: UInt8 = 0xAB) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transfer-test-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        tempFiles.append(url)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var remaining = size
        let block = Data(repeating: fill, count: 1024 * 1024)
        while remaining > 0 {
            let chunk = min(Int64(block.count), remaining)
            try handle.write(contentsOf: block.prefix(Int(chunk)))
            remaining -= chunk
        }
        return url
    }

    private func makeEngine(
        journal: MockJournal = MockJournal()
    ) -> (TransferEngine, MockJournal) {
        (TransferEngine(journal: journal, chunkSize: 4 * 1024 * 1024), journal)
    }

    /// CloudFile с корректным размером для верификации.
    private func meta(size: Int64, hashes: [ContentHash] = []) -> CloudFile {
        CloudFile(
            id: "mock-upload",
            name: "f",
            mimeType: "application/octet-stream",
            sizeBytes: size,
            modifiedAt: nil,
            contentHashes: hashes
        )
    }

    // MARK: Tests

    /// Документ/PDF малого размера — регрессия: один чанк,
    /// успешная передача.
    func testSmallFileUpload() async throws {
        let fileURL = try makeTempFile(size: 512 * 1024)
        let session = MockTransferSession(totalSize: 512 * 1024)
        let repo = MockRepository()
        repo.sessionToReturn = (session, "mock:0")
        repo.metadataToReturn = meta(size: 512 * 1024)

        let (engine, journal) = makeEngine()
        let result = try await engine.uploadFile(
            fileURL: fileURL,
            name: "doc.pdf",
            mimeType: "application/pdf",
            targetProvider: "mock",
            target: repo,
            parentFolderID: nil
        )

        XCTAssertEqual(result.id, "mock-upload")
        XCTAssertTrue(journal.allRecords().isEmpty, "Журнал должен очиститься")
        XCTAssertEqual(session.sentAbsoluteOffsets, [0])
    }

    /// Синтетический файл ~200 МБ — много чанков, без загрузки
    /// всего содержимого в память (чанки — временные файлы).
    func testLargeFileUpload() async throws {
        let size: Int64 = 200 * 1024 * 1024
        let fileURL = try makeTempFile(size: size)
        let session = MockTransferSession(totalSize: size)
        let repo = MockRepository()
        repo.sessionToReturn = (session, "mock:0")
        repo.metadataToReturn = meta(size: size)

        let (engine, journal) = makeEngine()
        _ = try await engine.uploadFile(
            fileURL: fileURL,
            name: "video.mov",
            mimeType: "video/quicktime",
            targetProvider: "mock",
            target: repo,
            parentFolderID: nil
        )

        XCTAssertTrue(journal.allRecords().isEmpty)
        // 200 МиБ / 4 МиБ чанк = 50 чанков.
        XCTAssertEqual(session.sendCount, 50)
        XCTAssertEqual(session.confirmedOffset, size)
    }

    /// Обрыв на середине → запись failed → resume с offset:
    /// досылаются только оставшиеся чанки.
    func testInterruptedUploadResumesFromOffset() async throws {
        let size: Int64 = 16 * 1024 * 1024
        let fileURL = try makeTempFile(size: size)

        // Первая попытка: сессия «падает» после 2 чанков.
        let failing = MockTransferSession(totalSize: size)
        failing.failAfterSends = 2
        let repo = MockRepository()
        repo.sessionToReturn = (failing, "mock:0")

        let journal = MockJournal()
        let (engine, _) = makeEngine(journal: journal)

        do {
            _ = try await engine.uploadFile(
                fileURL: fileURL,
                name: "photo.heic",
                mimeType: "image/heic",
                targetProvider: "mock",
                target: repo,
                parentFolderID: nil
            )
            XCTFail("Передача должна была упасть")
        } catch {
            // ожидаемо
        }

        // Журнал хранит offset и sessionState — запись
        // в состоянии failed (не pending, resume пойдёт
        // через повторный uploadFile с resumeState).
        let all = journal.allRecords()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.state, .failed)
        XCTAssertGreaterThan(all.first?.offset ?? 0, 0)

        // Вторая попытка: «восстановленная» сессия с offset.
        let restoredOffset = all.first?.offset ?? 0
        let resumed = MockTransferSession(
            totalSize: size,
            confirmedOffset: restoredOffset
        )
        repo.sessionToReturn = (resumed, "mock:\(restoredOffset)")
        repo.metadataToReturn = meta(size: size)

        _ = try await engine.uploadFile(
            fileURL: fileURL,
            name: "photo.heic",
            mimeType: "image/heic",
            targetProvider: "mock",
            target: repo,
            parentFolderID: nil
        )

        // Досланы только чанки после offset — первый отправленный
        // абсолютный offset не меньше подтверждённого.
        XCTAssertFalse(resumed.sentAbsoluteOffsets.isEmpty)
        XCTAssertGreaterThanOrEqual(
            resumed.sentAbsoluteOffsets.first ?? .max,
            restoredOffset
        )
        // Запись об успешной передаче удалена; в журнале
        // остаётся только старая failed-запись первой попытки.
        let remaining = journal.allRecords()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.state, .failed)
    }

    /// Отмена: задача останавливается, журнал помечает cancelled.
    func testCancellation() async throws {
        let size: Int64 = 64 * 1024 * 1024
        let fileURL = try makeTempFile(size: size)

        // Сессия, которая «вечно» принимает данные —
        // передача не завершится сама, только отмена.
        let session = MockTransferSession(totalSize: size)
        session.delayEachSend = true
        let repo = MockRepository()
        repo.sessionToReturn = (session, "mock:0")

        let journal = MockJournal()
        let (engine, _) = makeEngine(journal: journal)

        let task = Task {
            try await engine.uploadFile(
                fileURL: fileURL,
                name: "big.mp4",
                mimeType: "video/mp4",
                targetProvider: "mock",
                target: repo,
                parentFolderID: nil
            )
        }
        // Даём движку начаться и уйти в цикл.
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Ожидалась отмена")
        } catch is CancellationError {
            // ок
        } catch {
            // CloudStorageError.cancelled тоже допустим
            XCTAssertTrue(
                String(describing: error).contains("cancel")
                    || String(describing: error).contains("отмен")
            )
        }
    }

    /// Несовпадение контрольной суммы — операция НЕ считается
    /// успешной: запись журнала в failed, ошибка проброшена.
    func testHashMismatchFailsTransfer() async throws {
        let size: Int64 = 1024 * 1024
        let fileURL = try makeTempFile(size: size)

        let session = MockTransferSession(totalSize: size)
        let repo = MockRepository()
        repo.sessionToReturn = (session, "mock:0")
        // Приёмник отдаёт чужую контрольную сумму.
        repo.metadataToReturn = meta(
            size: size,
            hashes: [ContentHash(algorithm: .md5, value: "0000deadbeef")]
        )

        let journal = MockJournal()
        let (engine, _) = makeEngine(journal: journal)

        do {
            _ = try await engine.uploadFile(
                fileURL: fileURL,
                name: "photo.heic",
                mimeType: "image/heic",
                targetProvider: "mock",
                target: repo,
                parentFolderID: nil
            )
            XCTFail("Передача с битым хешем должна упасть")
        } catch let error as CloudStorageError {
            guard case .operationFailed = error else {
                return XCTFail("Неожиданная ошибка: \(error)")
            }
        }

        let all = journal.allRecords()
        XCTAssertEqual(all.first?.state, .failed)
    }

    /// Move не удаляет источник, если размер у приёмника
    /// не сошёлся.
    func testMoveDoesNotDeleteSourceOnSizeMismatch() async throws {
        let size: Int64 = 1024 * 1024
        let fileURL = try makeTempFile(size: size)

        let session = MockTransferSession(totalSize: size)
        let target = MockRepository()
        target.sessionToReturn = (session, "mock:0")
        target.metadataToReturn = meta(size: size + 1) // чужой размер

        let source = MockRepository()
        source.chunkSourceToReturn = FileChunkSource(
            fileURL: fileURL,
            totalSize: size
        )

        let journal = MockJournal()
        let (engine, _) = makeEngine(journal: journal)

        let cloudFile = CloudFile(
            id: "src-1",
            name: "video.mov",
            mimeType: "video/quicktime",
            sizeBytes: size,
            modifiedAt: nil
        )

        do {
            _ = try await engine.transferFile(
                cloudFile,
                from: "src",
                source: source,
                to: "dst",
                target: target,
                targetParentID: nil,
                move: true
            )
            XCTFail("Передача с неверным размером должна упасть")
        } catch {
            // ожидаемо
        }

        XCTAssertTrue(
            source.deletedIDs.isEmpty,
            "Источник не должен удаляться при провале верификации"
        )
    }
}

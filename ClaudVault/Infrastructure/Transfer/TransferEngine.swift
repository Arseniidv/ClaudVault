import Foundation

/// Движок chunked-передач: источник чанков → сессия приёмника →
/// журнал → верификация. Используется для загрузки локальных
/// файлов и cloud-to-cloud переноса.
@MainActor
final class TransferEngine {

    private let journal: TransferJournal
    private let chunkSize: Int64

    /// Активная запись журнала текущей передачи (для отмены).
    private(set) var activeRecordID: UUID?
    /// Вызывается при изменении прогресса активной передачи (0...1).
    var onProgress: (@Sendable (Double) -> Void)?

    init(journal: TransferJournal, chunkSize: Int64 = 8 * 1024 * 1024) {
        self.journal = journal
        self.chunkSize = chunkSize
    }

    // MARK: - Upload (device → cloud)

    /// Загружает локальный файл в облако чанками с журналированием.
    /// При `nil` от `makeUploadSession` бросает `.notImplemented` —
    /// вызывающий код откатывается на `repository.uploadFile`.
    func uploadFile(
        fileURL: URL,
        name: String,
        mimeType: String,
        targetProvider: String,
        target: any CloudStorageRepository,
        parentFolderID: String?
    ) async throws -> CloudFile {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: fileURL.path
        ),
              let size = (attributes[.size] as? NSNumber)?.int64Value else {
            throw CloudStorageError.operationFailed("Файл недоступен для чтения.")
        }

        let record = TransferRecord(
            kind: .upload,
            sourceFilePath: fileURL.path,
            targetProvider: targetProvider,
            targetParentID: parentFolderID ?? "",
            name: name,
            mimeType: mimeType,
            sizeBytes: size
        )
        try await journal.begin(record)
        activeRecordID = record.id
        defer { activeRecordID = nil }

        do {
            let file = try await runUpload(
                record: record,
                source: FileChunkSource(fileURL: fileURL, totalSize: size),
                target: target,
                parentFolderID: parentFolderID
            )
            try await journal.delete(id: record.id)
            return file
        } catch {
            try? await journal.setState(
                id: record.id,
                state: Self.isCancellation(error) ? .cancelled : .failed,
                error: error.localizedDescription
            )
            throw error
        }
    }

    // MARK: - Cloud-to-cloud transfer

    /// Переносит файл из одного облака в другое чанками «на лету».
    /// При `move == true` источник удаляется только после
    /// верификации размера у приёмника.
    /// Бросает `.notImplemented`, если провайдеры не поддерживают
    /// chunked-передачу — вызывающий код использует fallback.
    func transferFile(
        _ file: CloudFile,
        from sourceProvider: String,
        source: any CloudStorageRepository,
        to targetProvider: String,
        target: any CloudStorageRepository,
        targetParentID: String?,
        move: Bool
    ) async throws -> CloudFile {
        guard let sizeBytes = file.sizeBytes, sizeBytes >= 0 else {
            throw CloudStorageError.operationFailed(
                "Размер файла неизвестен — передача невозможна."
            )
        }

        guard let chunkSource = try await source.makeChunkSource(for: file) else {
            throw CloudStorageError.notImplemented
        }

        let record = TransferRecord(
            kind: .cloudTransfer,
            sourceProvider: sourceProvider,
            sourceFileID: file.id,
            targetProvider: targetProvider,
            targetParentID: targetParentID ?? "",
            name: file.name,
            mimeType: file.mimeType,
            sizeBytes: sizeBytes,
            moveSource: move
        )
        try await journal.begin(record)
        activeRecordID = record.id
        defer { activeRecordID = nil }

        do {
            let uploaded = try await runUpload(
                record: record,
                source: chunkSource,
                target: target,
                parentFolderID: targetParentID
            )

            // Верификация размера у приёмника — обязательна
            // до удаления источника при move.
            try await journal.setState(id: record.id, state: .verifying)
            let meta = try await target.fileMetadata(id: uploaded.id)
            guard meta.sizeBytes == sizeBytes else {
                throw CloudStorageError.operationFailed(
                    "Размер загруженного файла не совпадает с источником."
                )
            }

            if move {
                try await source.deleteFile(id: file.id)
            }

            try await journal.delete(id: record.id)
            return uploaded
        } catch {
            try? await journal.setState(
                id: record.id,
                state: Self.isCancellation(error) ? .cancelled : .failed,
                error: error.localizedDescription
            )
            throw error
        }
    }

    // MARK: - Resume

    /// Подхватывает незавершённые записи журнала после перезапуска.
    /// `repoFor` возвращает репозиторий по `StorageProviderType.rawValue`.
    /// Записи, которые невозможно продолжить (протухшая сессия,
    /// удалённый локальный файл), помечаются `.failed`.
    func resumePending(
        repoFor: (String) -> (any CloudStorageRepository)?
    ) async {
        guard let records = try? await journal.pendingRecords() else { return }

        for record in records {
            do {
                switch record.kind {
                case .upload:
                    try await resumeUpload(record: record, repoFor: repoFor)
                case .cloudTransfer:
                    try await resumeTransfer(record: record, repoFor: repoFor)
                }
            } catch {
                try? await journal.setState(
                    id: record.id,
                    state: .failed,
                    error: "Не удалось возобновить: \(error.localizedDescription)"
                )
            }
        }
    }

    private func resumeUpload(
        record: TransferRecord,
        repoFor: (String) -> (any CloudStorageRepository)?
    ) async throws {
        guard let target = repoFor(record.targetProvider) else {
            throw CloudStorageError.notConnected
        }
        let fileURL = URL(fileURLWithPath: record.sourceFilePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CloudStorageError.operationFailed("Исходный файл недоступен.")
        }

        let session = try await makeSession(
            record: record,
            target: target,
            parentFolderID: record.targetParentID.isEmpty
                ? nil : record.targetParentID
        )
        let source = FileChunkSource(
            fileURL: fileURL,
            totalSize: record.sizeBytes
        )

        let uploaded = try await runUpload(
            record: record,
            source: source,
            target: target,
            parentFolderID: record.targetParentID.isEmpty
                ? nil : record.targetParentID,
            existingSession: session
        )
        try await journal.setState(id: record.id, state: .verifying)
        let meta = try await target.fileMetadata(id: uploaded.id)
        guard meta.sizeBytes == record.sizeBytes else {
            throw CloudStorageError.operationFailed(
                "Размер загруженного файла не совпадает с источником."
            )
        }
        try await journal.delete(id: record.id)
    }

    private func resumeTransfer(
        record: TransferRecord,
        repoFor: (String) -> (any CloudStorageRepository)?
    ) async throws {
        guard let source = repoFor(record.sourceProvider),
              let target = repoFor(record.targetProvider) else {
            throw CloudStorageError.notConnected
        }

        // Восстанавливаем CloudFile-источник по id.
        let file = try await source.fileMetadata(id: record.sourceFileID)
        guard let chunkSource = try await source.makeChunkSource(for: file) else {
            throw CloudStorageError.notImplemented
        }

        let session = try await makeSession(
            record: record,
            target: target,
            parentFolderID: record.targetParentID.isEmpty
                ? nil : record.targetParentID
        )

        let uploaded = try await runUpload(
            record: record,
            source: chunkSource,
            target: target,
            parentFolderID: record.targetParentID.isEmpty
                ? nil : record.targetParentID,
            existingSession: session
        )
        try await journal.setState(id: record.id, state: .verifying)
        let meta = try await target.fileMetadata(id: uploaded.id)
        guard meta.sizeBytes == record.sizeBytes else {
            throw CloudStorageError.operationFailed(
                "Размер загруженного файла не совпадает с источником."
            )
        }
        if record.moveSource {
            try await source.deleteFile(id: record.sourceFileID)
        }
        try await journal.delete(id: record.id)
    }

    /// Отмена текущей передачи: бросает задачу-цикл через Task
    /// и помечает запись отменённой.
    func cancelActive() async {
        guard let id = activeRecordID else { return }
        try? await journal.setState(id: id, state: .cancelled)
        // Task.checkCancellation в цикле движка завершит передачу.
    }

    // MARK: - Private

    /// Создаёт или восстанавливает сессию приёмника.
    /// При протухшем `sessionState` провайдер возвращает nil —
    /// тогда начинаем сессию заново (offset=0, перезапись файла
    /// идемпотентна благодаря conflictBehavior провайдеров).
    private func makeSession(
        record: TransferRecord,
        target: any CloudStorageRepository,
        parentFolderID: String?
    ) async throws -> (session: any TransferSession, state: String)? {
        if !record.sessionState.isEmpty {
            if let restored = try await target.makeUploadSession(
                name: record.name,
                mimeType: record.mimeType,
                parentFolderID: parentFolderID,
                sizeBytes: record.sizeBytes,
                resumeState: record.sessionState
            ) {
                return restored
            }
            // Сессия протухла — честный рестарт с offset=0.
        }
        return try await target.makeUploadSession(
            name: record.name,
            mimeType: record.mimeType,
            parentFolderID: parentFolderID,
            sizeBytes: record.sizeBytes,
            resumeState: nil
        )
    }

    private func runUpload(
        record: TransferRecord,
        source: any ChunkSource,
        target: any CloudStorageRepository,
        parentFolderID: String?,
        existingSession: (session: any TransferSession, state: String)? = nil
    ) async throws -> CloudFile {
        let made: (session: any TransferSession, state: String)?
        if let existingSession {
            made = existingSession
        } else {
            made = try await makeSession(
                record: record,
                target: target,
                parentFolderID: parentFolderID
            )
        }
        guard let (session, state) = made else {
            throw CloudStorageError.notImplemented
        }

        try await journal.updateSessionState(id: record.id, state: state)
        try await journal.updateOffset(id: record.id, offset: session.confirmedOffset)
        try await journal.setState(id: record.id, state: .uploading)

        let recordID = record.id
        let journal = self.journal
        let chunkSize = self.chunkSize
        let onProgress = self.onProgress

        let uploaded = try await ChunkedUploadRunner.run(
            source: source,
            session: session,
            chunkSize: chunkSize,
            onConfirmedOffset: { offset in
                try await journal.updateProgress(id: recordID, offset: offset)
                onProgress?(Self.progress(uploaded: offset, total: record.sizeBytes))
            }
        )
        return uploaded
    }

    private static func progress(uploaded: Int64, total: Int64) -> Double {
        guard total > 0 else { return uploaded > 0 ? 1 : 0 }
        return min(max(Double(uploaded) / Double(total), 0), 1)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if case .cancelled = error as? CloudStorageError { return true }
        return false
    }
}

/// Общий цикл chunked-загрузки: источник → сессия → подтверждённое
/// смещение → журнал. Не зависит от провайдера.
enum ChunkedUploadRunner {

    /// Запускает передачу до `source.totalSize`. `onConfirmedOffset`
    /// вызывается после каждого принятого провайдером фрагмента.
    static func run(
        source: any ChunkSource,
        session: any TransferSession,
        chunkSize: Int64,
        onConfirmedOffset: (Int64) async throws -> Void = { _ in }
    ) async throws -> CloudFile {
        let total = source.totalSize
        var offset = session.confirmedOffset
        var stalledAttempts = 0

        while offset < total {
            try Task.checkCancellation()

            guard let payload = try await source.chunk(
                at: offset,
                maxLength: chunkSize
            ) else {
                throw CloudStorageError.operationFailed(
                    "Источник оборвал передачу данных."
                )
            }
            guard payload.length > 0 else {
                await source.discard(payload)
                throw CloudStorageError.operationFailed(
                    "Источник вернул пустой чанк."
                )
            }

            do {
                try await session.send(payload)
            } catch {
                await source.discard(payload)
                throw error
            }
            await source.discard(payload)

            let next = session.confirmedOffset
            if next <= offset {
                // Провайдер не продвинул смещение — защищаемся
                // от бесконечного цикла.
                stalledAttempts += 1
                guard stalledAttempts <= 5 else {
                    throw CloudStorageError.operationFailed(
                        "Приёмник не продвигает загрузку."
                    )
                }
            } else {
                stalledAttempts = 0
                offset = next
                try await onConfirmedOffset(offset)
            }
        }

        return try await session.finish()
    }
}

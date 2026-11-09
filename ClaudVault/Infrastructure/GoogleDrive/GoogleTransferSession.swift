import Foundation

/// Resumable-сессия загрузки Google Drive как `TransferSession`.
///
/// Состояние для журнала — URL сессии (`gdrive:<url>`).
/// При resume сессия опрашивается через `queryUploadStatus`:
/// сервер сам сообщает реальное принятое смещение, поэтому
/// заголовок `Range` не нужен хранить.
final class GoogleTransferSession: TransferSession, @unchecked Sendable {

    static let statePrefix = "gdrive:"

    private let service: GoogleDriveService
    private let sessionURL: URL
    let totalSize: Int64
    private let mimeType: String

    private(set) var confirmedOffset: Int64
    private var resultFile: CloudFile?
    private var isComplete = false

    private let maxSendAttempts = 4

    private init(
        service: GoogleDriveService,
        sessionURL: URL,
        totalSize: Int64,
        mimeType: String,
        confirmedOffset: Int64,
        resultFile: CloudFile? = nil
    ) {
        self.service = service
        self.sessionURL = sessionURL
        self.totalSize = totalSize
        self.mimeType = mimeType
        self.confirmedOffset = confirmedOffset
        self.resultFile = resultFile
        self.isComplete = confirmedOffset >= totalSize && totalSize > 0
    }

    /// Сериализованное состояние для журнала передач.
    var stateValue: String {
        Self.statePrefix + sessionURL.absoluteString
    }

    /// Начинает новую resumable-сессию на сервере.
    static func begin(
        service: GoogleDriveService,
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64
    ) async throws -> GoogleTransferSession {
        let sessionURL = try await service.createUploadSession(
            name: name,
            mimeType: mimeType,
            parentFolderID: parentFolderID,
            fileSize: sizeBytes
        )
        return GoogleTransferSession(
            service: service,
            sessionURL: sessionURL,
            totalSize: sizeBytes,
            mimeType: mimeType,
            confirmedOffset: 0
        )
    }

    /// Восстанавливает сессию по состоянию из журнала.
    /// `nil` — состояние не наше или сессия истекла/завершена
    /// без доступа к файлу: вызывающий код начнёт заново.
    static func restore(
        service: GoogleDriveService,
        resumeState: String,
        sizeBytes: Int64,
        mimeType: String
    ) async throws -> GoogleTransferSession? {
        guard resumeState.hasPrefix(statePrefix) else { return nil }
        let raw = String(resumeState.dropFirst(statePrefix.count))
        guard let sessionURL = URL(string: raw) else { return nil }

        do {
            switch try await service.queryUploadStatus(
                sessionURL: sessionURL,
                fileSize: sizeBytes
            ) {
            case .inProgress(let nextByte):
                return GoogleTransferSession(
                    service: service,
                    sessionURL: sessionURL,
                    totalSize: sizeBytes,
                    mimeType: mimeType,
                    confirmedOffset: nextByte
                )
            case .completed(let file):
                return GoogleTransferSession(
                    service: service,
                    sessionURL: sessionURL,
                    totalSize: sizeBytes,
                    mimeType: mimeType,
                    confirmedOffset: sizeBytes,
                    resultFile: file
                )
            }
        } catch {
            // Сессия истекла (404/410) или сеть недоступна —
            // в обоих случаях честнее начать загрузку заново.
            return nil
        }
    }

    // MARK: - TransferSession

    func send(_ payload: ChunkPayload) async throws {
        guard !isComplete else { return }

        var attempt = 0
        // PUT диапазона payload'а. Если сервер уже принял часть
        // (обрыв после отправки), ответ 308 вернёт реальное
        // смещение — подтверждённый offset обновляем и выходим:
        // движок запросит следующий чанк с этого места.
        while confirmedOffset < payload.absoluteOffset + payload.length {
            try Task.checkCancellation()
            let cursor = max(confirmedOffset, payload.absoluteOffset)
            let chunkOffset = payload.fileOffset + (cursor - payload.absoluteOffset)
            let length = Int(payload.absoluteOffset + payload.length - cursor)
            guard length > 0 else { break }

            do {
                switch try await service.sendResumableChunk(
                    sessionURL: sessionURL,
                    chunkFile: payload.fileURL,
                    chunkOffset: chunkOffset,
                    length: length,
                    absoluteOffset: cursor,
                    totalSize: totalSize,
                    mimeType: mimeType
                ) {
                case .progress(let nextByte):
                    confirmedOffset = max(confirmedOffset, nextByte)
                    attempt = 0
                    // Сервер мог принять часть диапазона — выходим,
                    // движок продолжит с confirmedOffset.
                    return
                case .completed(let file):
                    resultFile = file
                    confirmedOffset = totalSize
                    isComplete = true
                    return
                }
            } catch let error as CloudStorageError
                where GoogleDriveService.isRetryable(error) {
                attempt += 1
                guard attempt <= maxSendAttempts else { throw error }
                try await Task.sleep(
                    nanoseconds: GoogleDriveService.backoffNanoseconds(attempt: attempt)
                )
                // Синхронизируемся с сервером: он мог принять
                // часть отправленного диапазона.
                do {
                    switch try await service.queryUploadStatus(
                        sessionURL: sessionURL,
                        fileSize: totalSize
                    ) {
                    case .inProgress(let nextByte):
                        confirmedOffset = max(confirmedOffset, nextByte)
                    case .completed(let file):
                        resultFile = file
                        confirmedOffset = totalSize
                        isComplete = true
                        return
                    }
                } catch {
                    // Не удалось опросить статус — повторяем PUT.
                }
            }
        }
    }

    func finish() async throws -> CloudFile {
        if totalSize == 0, !isComplete {
            // Пустой файл: один PUT без тела.
            switch try await service.sendResumableChunk(
                sessionURL: sessionURL,
                chunkFile: payloadPlaceholder(),
                chunkOffset: 0,
                length: 0,
                absoluteOffset: 0,
                totalSize: 0,
                mimeType: mimeType
            ) {
            case .completed(let file):
                resultFile = file
                isComplete = true
                confirmedOffset = 0
            case .progress:
                throw CloudStorageError.invalidResponse
            }
        }

        if let resultFile {
            return resultFile
        }

        // Файл мог завершиться без финального 2xx в этой сессии
        // (например, resume после обрыва) — опрашиваем статус.
        switch try await service.queryUploadStatus(
            sessionURL: sessionURL,
            fileSize: totalSize
        ) {
        case .completed(let file):
            guard let file else { throw CloudStorageError.invalidResponse }
            return file
        case .inProgress:
            throw CloudStorageError.operationFailed(
                "Загрузка не завершена: сервер не подтвердил все байты."
            )
        }
    }

    private func payloadPlaceholder() -> URL {
        // Для пустого файла FileHandle не открывается (length == 0
        // → readChunk не вызывается), путь может быть любым валидным.
        FileManager.default.temporaryDirectory
    }

    func cancel() async {
        // У resumable-сессий Google нет явного abort —
        // сессия истекает сама через ~1 неделю.
    }
}

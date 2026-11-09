import Foundation
import ClaudVaultDomain

/// Upload-сессия OneDrive (Microsoft Graph `createUploadSession`)
/// как `TransferSession`.
///
/// Состояние для журнала — pre-authenticated `uploadUrl`
/// (`odrive:<url>`). URL живёт ограниченное время: при resume
/// сессия опрашивается пустым PUT (`bytes */total`), а при
/// протухании возвращается `nil` — движок начнёт загрузку
/// заново с offset=0.
final class OneDriveTransferSession: TransferSession, @unchecked Sendable {

    static let statePrefix = "odrive:"

    private let service: OneDriveService
    private var sessionURL: URL
    let totalSize: Int64

    /// Параметры назначения — нужны для повторного создания
    /// сессии, если `uploadUrl` протух посреди передачи,
    /// и для пустого файла в `finish`.
    private let name: String
    private let mimeType: String
    private let parentFolderID: String?

    private(set) var confirmedOffset: Int64
    private var resultFile: CloudFile?
    private var isComplete = false

    private let maxSendAttempts = 4

    /// Microsoft Graph требует, чтобы все фрагменты
    /// upload-сессии, кроме последнего, были кратны 320 КиБ.
    private static let fragmentQuantum = 320 * 1024

    private init(
        service: OneDriveService,
        sessionURL: URL,
        totalSize: Int64,
        name: String,
        mimeType: String,
        parentFolderID: String?,
        confirmedOffset: Int64,
        resultFile: CloudFile? = nil
    ) {
        self.service = service
        self.sessionURL = sessionURL
        self.totalSize = totalSize
        self.name = name
        self.mimeType = mimeType
        self.parentFolderID = parentFolderID
        self.confirmedOffset = confirmedOffset
        self.resultFile = resultFile
        self.isComplete = resultFile != nil
    }

    /// Сериализованное состояние для журнала передач.
    var stateValue: String {
        Self.statePrefix + sessionURL.absoluteString
    }

    /// Новая сессия: `createUploadSession` на сервере.
    static func begin(
        service: OneDriveService,
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64
    ) async throws -> OneDriveTransferSession {
        let sessionURL = try await service.createUploadSession(
            parent: parentFolderID,
            name: name
        )
        return OneDriveTransferSession(
            service: service,
            sessionURL: sessionURL,
            totalSize: sizeBytes,
            name: name,
            mimeType: mimeType,
            parentFolderID: parentFolderID,
            confirmedOffset: 0
        )
    }

    /// Восстановление по состоянию журнала: опрашивает
    /// `uploadUrl` и берёт реально принятое смещение.
    /// `nil` — состояние не наше, URL протух или сессия
    /// уже завершена без файла: загрузка начнётся заново.
    static func restore(
        service: OneDriveService,
        resumeState: String,
        sizeBytes: Int64,
        name: String,
        mimeType: String,
        parentFolderID: String?
    ) async throws -> OneDriveTransferSession? {
        guard resumeState.hasPrefix(statePrefix) else { return nil }
        let raw = String(resumeState.dropFirst(statePrefix.count))
        guard let sessionURL = URL(string: raw) else { return nil }

        do {
            let offset = try await service.queryUploadSession(
                sessionURL: sessionURL,
                totalSize: sizeBytes
            )
            return OneDriveTransferSession(
                service: service,
                sessionURL: sessionURL,
                totalSize: sizeBytes,
                name: name,
                mimeType: mimeType,
                parentFolderID: parentFolderID,
                confirmedOffset: min(offset, sizeBytes)
            )
        } catch {
            // 404/410 — uploadUrl истёк; прочие ошибки тоже
            // честнее трактовать как «начать заново».
            return nil
        }
    }

    // MARK: - TransferSession

    func send(_ payload: ChunkPayload) async throws {
        guard !isComplete else { return }
        let end = payload.absoluteOffset + payload.length

        var attempt = 0
        while confirmedOffset < end {
            try Task.checkCancellation()
            let cursor = max(confirmedOffset, payload.absoluteOffset)
            let chunkFileOffset =
                payload.fileOffset + (cursor - payload.absoluteOffset)
            var length = Int(end - cursor)
            guard length > 0 else { break }

            // Все фрагменты, кроме завершающего файл, обязаны
            // быть кратны 320 КиБ. Если payload доходит до конца
            // файла — остаток уходит одним последним фрагментом
            // любого размера; иначе отправляем только выровненную
            // часть, а хвост < кванта досылает следующий чанк
            // движка (контракт send допускает частичное принятие).
            if end != totalSize {
                length -= length % Self.fragmentQuantum
                if length == 0 { return }
            }

            do {
                let (data, response) = try await service.uploadSessionFragment(
                    sessionURL: sessionURL,
                    chunkFile: payload.fileURL,
                    fileOffset: chunkFileOffset,
                    length: Int64(length),
                    absoluteOffset: cursor,
                    totalSize: totalSize
                )
                let status = response.statusCode

                // 202 Accepted — фрагмент принят, продолжать.
                if status == 202 {
                    confirmedOffset = cursor + Int64(length)
                    if confirmedOffset >= end { return }
                    continue
                }
                // 200/201 — последний фрагмент, файл создан.
                if (200..<300).contains(status) {
                    if let item = try? JSONDecoder().decode(
                        DriveItemDTO.self,
                        from: data
                    ) {
                        resultFile = item.asCloudFile
                    } else {
                        resultFile = nil
                    }
                    confirmedOffset = totalSize
                    isComplete = resultFile != nil
                    return
                }
                throw OneDriveService.mapError(status: status, data: data)
            } catch let error as CloudStorageError
                where OneDriveService.isRetryable(error) {
                attempt += 1
                guard attempt <= maxSendAttempts else { throw error }
                try await Task.sleep(
                    nanoseconds: OneDriveService.backoffNanoseconds(attempt: attempt)
                )
                // Сервер мог принять часть диапазона —
                // синхронизируемся и досылаем остаток.
                do {
                    let offset = try await service.queryUploadSession(
                        sessionURL: sessionURL,
                        totalSize: totalSize
                    )
                    confirmedOffset = max(confirmedOffset, min(offset, end))
                } catch {
                    // Не удалось опросить — повторяем PUT.
                }
            } catch let error as CloudStorageError {
                // uploadUrl — pre-authenticated и не продлевается:
                // при его смерти честно падаем. При resume
                // restore вернёт nil и движок начнёт сессию
                // заново с offset=0.
                throw error
            }
        }
    }

    func finish() async throws -> CloudFile {
        if let resultFile {
            return resultFile
        }
        if isComplete {
            throw CloudStorageError.invalidResponse
        }

        // Пустой файл: upload-сессия не нужна — простой PUT.
        if totalSize == 0 {
            let file = try await service.simpleUpload(
                body: Data(),
                name: name,
                mimeType: mimeType,
                parent: parentFolderID
            )
            resultFile = file
            isComplete = true
            return file
        }

        // Все байты ушли, но финальный фрагмент (200/201)
        // не был получен — файл не считается созданным.
        throw CloudStorageError.operationFailed(
            "Загрузка не завершена: сервер не подтвердил все байты."
        )
    }

    func cancel() async {
        await service.cancelUploadSession(sessionURL: sessionURL)
    }

    // MARK: - Private
}

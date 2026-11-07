import Foundation
import SwiftyDropbox
import UniformTypeIdentifiers

/// Upload-сессия Dropbox как `TransferSession`.
///
/// Состояние для журнала — `dbx:<sessionId>:<offset>`.
/// `sessionId` появляется после первого `send` (start с данными),
/// offset — локально подтверждённый (append не возвращает offset;
/// при расхождении сервер отвечает `incorrectOffset` с
/// `correctOffset`, который мы используем для ресинхронизации).
final class DropboxTransferSession: TransferSession, @unchecked Sendable {

    static let statePrefix = "dbx:"

    private var sessionId: String?
    /// Путь назначения в Dropbox для commit при finish.
    /// При restore заполняется репозиторием через `setCommitPath`.
    private var commitPath: String

    private(set) var confirmedOffset: Int64
    private var resultFile: CloudFile?
    private var isComplete = false

    private let maxAttempts = 4

    private init(
        sessionId: String?,
        commitPath: String,
        confirmedOffset: Int64,
        resultFile: CloudFile? = nil
    ) {
        self.sessionId = sessionId
        self.commitPath = commitPath
        self.confirmedOffset = confirmedOffset
        self.resultFile = resultFile
        self.isComplete = resultFile != nil
    }

    /// Сериализованное состояние для журнала передач.
    var stateValue: String {
        "\(Self.statePrefix)\(sessionId ?? ""):\(confirmedOffset)"
    }

    /// Путь, который будет передан в CommitInfo при finish.
    var resolvedCommitPath: String { commitPath }

    /// Задаёт путь назначения (нужен при restore — в состоянии
    /// журнала его нет, репозиторий восстанавливает его из job).
    func setCommitPath(_ path: String) {
        commitPath = path
    }

    /// Новая сессия: `sessionId` ещё нет — первая порция данных
    /// уйдёт через `uploadSessionStart`.
    static func begin(commitPath: String) -> DropboxTransferSession {
        DropboxTransferSession(
            sessionId: nil,
            commitPath: commitPath,
            confirmedOffset: 0
        )
    }

    /// Восстановление по состоянию журнала.
    /// `nil` — состояние не наше или продолжить нельзя
    /// (нет sessionId при offset > 0): загружаем заново.
    static func restore(
        resumeState: String,
        commitPath: String
    ) -> DropboxTransferSession? {
        guard resumeState.hasPrefix(statePrefix) else { return nil }
        let payload = resumeState.dropFirst(statePrefix.count)
        let parts = payload.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let offset = Int64(parts[1]) else { return nil }

        let sessionId = String(parts[0])
        // Без sessionId продолжить нельзя: upload-сессия Dropbox
        // всегда начинается с байта 0.
        guard !sessionId.isEmpty, offset >= 0 else { return nil }

        return DropboxTransferSession(
            sessionId: sessionId,
            commitPath: commitPath,
            confirmedOffset: offset
        )
    }

    // MARK: - TransferSession

    func send(_ payload: ChunkPayload) async throws {
        guard !isComplete else { return }
        let client = try authorizedClient()

        var cursor = payload.absoluteOffset
        let end = payload.absoluteOffset + payload.length

        while cursor < end {
            try Task.checkCancellation()
            let sliceFileOffset = payload.fileOffset + (cursor - payload.absoluteOffset)
            let sliceLength = Int(end - cursor)
            let data = try Self.readRange(
                from: payload.fileURL,
                offset: sliceFileOffset,
                length: sliceLength
            )

            var offsetCorrected = false
            var attempt = 0
            while true {
                do {
                    if let sessionId {
                        _ = try await client.files
                            .uploadSessionAppendV2(
                                cursor: Files.UploadSessionCursor(
                                    sessionId: sessionId,
                                    offset: UInt64(cursor)
                                ),
                                close: false,
                                input: data
                            )
                            .response()
                        confirmedOffset = end
                        return
                    } else {
                        let started = try await client.files
                            .uploadSessionStart(close: false, input: data)
                            .response()
                        sessionId = started.sessionId
                        confirmedOffset = cursor + Int64(data.count)
                        return
                    }
                } catch let error as CallError<Files.UploadSessionAppendError> {
                    if case .routeError(let box, _, _, _) = error,
                       case .incorrectOffset(let offsetError) = box.unboxed {
                        // Сервер сообщает реальное смещение —
                        // ресинхронизируемся и досылаем остаток.
                        let correct = Int64(offsetError.correctOffset)
                        if correct > cursor, !offsetCorrected {
                            cursor = correct
                            confirmedOffset = correct
                            offsetCorrected = true
                            break // выход во внешний цикл с новым cursor
                        }
                    }
                    let mapped = DropboxAuthManager.mapError(error)
                    guard Self.isRetryable(mapped), attempt < maxAttempts else {
                        throw mapped
                    }
                    attempt += 1
                    try await Task.sleep(nanoseconds: Self.backoff(attempt: attempt))
                } catch let error as CallError<Files.UploadSessionStartError> {
                    let mapped = DropboxAuthManager.mapError(error)
                    guard Self.isRetryable(mapped), attempt < maxAttempts else {
                        throw mapped
                    }
                    attempt += 1
                    try await Task.sleep(nanoseconds: Self.backoff(attempt: attempt))
                }
            }
        }
    }

    func finish() async throws -> CloudFile {
        if let resultFile {
            return resultFile
        }

        let client = try authorizedClient()

        // Сессия могла не начаться (пустой файл) — стартуем
        // и сразу завершаем без данных.
        if sessionId == nil {
            let started = try await client.files
                .uploadSessionStart(close: false, input: Data())
                .response()
            sessionId = started.sessionId
        }

        guard let sessionId, !commitPath.isEmpty else {
            throw CloudStorageError.invalidResponse
        }

        var attempt = 0
        while true {
            do {
                let metadata = try await client.files
                    .uploadSessionFinish(
                        cursor: Files.UploadSessionCursor(
                            sessionId: sessionId,
                            offset: UInt64(confirmedOffset)
                        ),
                        commit: Files.CommitInfo(path: commitPath, mode: .overwrite),
                        input: Data()
                    )
                    .response()
                guard let mapped = Self.mapMetadata(metadata) else {
                    throw CloudStorageError.invalidResponse
                }
                resultFile = mapped
                isComplete = true
                return mapped
            } catch let error as CallError<Files.UploadSessionFinishError> {
                let mapped = DropboxAuthManager.mapError(error)
                guard Self.isRetryable(mapped), attempt < maxAttempts else {
                    throw mapped
                }
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoff(attempt: attempt))
            }
        }
    }

    func cancel() async {
        // У Dropbox нет явного abort для upload-сессии —
        // неиспользованные сессии истекают сами (до 7 дней).
    }

    // MARK: - Private

    private func authorizedClient() throws -> DropboxClient {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw CloudStorageError.notConnected
        }
        return client
    }

    /// Читает `length` байт из `fileURL` начиная с `offset` —
    /// только диапазон, файл целиком в память не грузится.
    private static func readRange(
        from fileURL: URL,
        offset: Int64,
        length: Int
    ) throws -> Data {
        guard length > 0 else { return Data() }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: length),
                  data.count == length else {
                throw CloudStorageError.operationFailed(
                    "Файл изменился во время загрузки или не читается."
                )
            }
            return data
        } catch let error as CloudStorageError {
            throw error
        } catch {
            throw CloudStorageError.operationFailed(
                "Ошибка чтения файла: \(error.localizedDescription)"
            )
        }
    }

    private static func isRetryable(_ error: CloudStorageError) -> Bool {
        switch error {
        case .network, .rateLimited:
            return true
        case .requestFailed(let statusCode, _):
            return statusCode >= 500 || statusCode == 408
        default:
            return false
        }
    }

    private static func backoff(attempt: Int) -> UInt64 {
        let seconds = min(pow(2.0, Double(max(attempt - 1, 0))), 16)
        return UInt64(seconds * 1_000_000_000)
    }

    /// Маппинг Files.Metadata → CloudFile (как в
    /// DropboxRepositoryImpl.mapMetadata).
    private static func mapMetadata(_ metadata: Files.Metadata) -> CloudFile? {
        guard let file = metadata as? Files.FileMetadata else { return nil }
        return CloudFile(
            id: file.pathDisplay ?? file.pathLower ?? file.id,
            name: file.name,
            mimeType: mimeType(for: file.name),
            sizeBytes: Int64(min(file.size, UInt64(Int64.max))),
            modifiedAt: file.serverModified,
            duration: videoDuration(from: file)
        )
    }

    private static func videoDuration(from file: Files.FileMetadata) -> TimeInterval? {
        guard case .metadata(let media) = file.mediaInfo,
              let video = media as? Files.VideoMetadata,
              let ms = video.duration else {
            return nil
        }
        return TimeInterval(ms) / 1000.0
    }

    private static func mimeType(for name: String) -> String {
        let pathExtension = (name as NSString).pathExtension
        guard !pathExtension.isEmpty,
              let type = UTType(filenameExtension: pathExtension),
              let mimeType = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mimeType
    }
}

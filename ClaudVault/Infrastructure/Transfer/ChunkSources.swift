import Foundation

/// Удаление временных файлов чанков (ответы Range-запросов).
enum TransferTempFiles {
    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Читает диапазоны локального файла. Сессии приёмника сами
/// читают `[fileOffset, +length)` из `fileURL`, поэтому чанк
/// отдаётся ссылкой на исходник без копирования — иначе каждый
/// чанк писался бы на диск и читался обратно (двойной I/O).
final class FileChunkSource: ChunkSource, @unchecked Sendable {

    let fileURL: URL
    let totalSize: Int64

    init(fileURL: URL, totalSize: Int64) {
        self.fileURL = fileURL
        self.totalSize = totalSize
    }

    func chunk(at offset: Int64, maxLength: Int64) async throws -> ChunkPayload? {
        guard offset >= 0, offset < totalSize else { return nil }
        let length = min(maxLength, totalSize - offset)
        guard length > 0 else { return nil }

        return ChunkPayload(
            fileURL: fileURL,
            fileOffset: offset,
            absoluteOffset: offset,
            length: length,
            isTemporary: false
        )
    }

    func discard(_ payload: ChunkPayload) async {
        // Чанк — ссылка на файл-источник, удалять нечего.
    }
}

/// Источник чанков из облака: HTTP Range-запросы,
/// ответ стримится сразу в файл (`URLSession.download`),
/// в память попадает только временный URL ответа.
/// Заголовки запрашиваются заново на каждую попытку —
/// токен может истечь посреди долгой передачи.
final class HTTPRangeChunkSource: ChunkSource, @unchecked Sendable {

    let url: URL
    let totalSize: Int64
    private let headersProvider: @Sendable () async throws -> [String: String]
    private let session: URLSession
    private let maxAttempts = 4

    init(
        url: URL,
        totalSize: Int64,
        headersProvider: @escaping @Sendable () async throws -> [String: String],
        session: URLSession = .shared
    ) {
        self.url = url
        self.totalSize = totalSize
        self.headersProvider = headersProvider
        self.session = session
    }

    func chunk(at offset: Int64, maxLength: Int64) async throws -> ChunkPayload? {
        guard offset >= 0, offset < totalSize else { return nil }
        let length = min(maxLength, totalSize - offset)
        guard length > 0 else { return nil }

        var lastError: Error = CloudStorageError.network("Неизвестная ошибка")
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            do {
                return try await fetch(offset: offset, length: length)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                lastError = error
                guard Self.isRetryable(error), attempt < maxAttempts else {
                    throw error
                }
                try await Task.sleep(
                    nanoseconds: Self.backoffNanoseconds(attempt: attempt)
                )
            }
        }
        throw lastError
    }

    func discard(_ payload: ChunkPayload) async {
        if payload.isTemporary {
            TransferTempFiles.remove(payload.fileURL)
        }
    }

    private func fetch(offset: Int64, length: Int64) async throws -> ChunkPayload {
        var request = URLRequest(url: url)
        request.setValue(
            "bytes=\(offset)-\(offset + length - 1)",
            forHTTPHeaderField: "Range"
        )
        for (key, value) in try await headersProvider() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (downloadedURL, response) = try await session.download(for: request)

        // При любой ошибке валидации скачанный файл удаляем —
        // payload его ещё не забрал.
        do {
            guard let http = response as? HTTPURLResponse else {
                throw CloudStorageError.invalidResponse
            }

            // 206 — Range поддержан. 200 на частичном диапазоне означает,
            // что сервер проигнорировал Range и прислал файл с начала —
            // такой чанк нельзя использовать, поток был бы испорчен.
            let isFullFile = offset == 0 && length == totalSize
            if http.statusCode == 200, !isFullFile {
                throw CloudStorageError.operationFailed(
                    "Сервер не поддерживает загрузку по частям."
                )
            }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.mapHTTPError(status: http.statusCode)
            }
            if offset > 0 || length < totalSize {
                guard http.statusCode == 206 else {
                    throw CloudStorageError.operationFailed(
                        "Сервер не поддерживает загрузку по частям."
                    )
                }
            }

            let attributes = try FileManager.default.attributesOfItem(
                atPath: downloadedURL.path
            )
            let received = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard received == length else {
                throw CloudStorageError.operationFailed(
                    "Источник прислал неполный чанк данных."
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw error
        }

        // Файл ответа download-задачи уже содержит ровно этот
        // чанк — отдаём его напрямую (isTemporary → discard
        // удалит), без лишнего перемещения во временную папку.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: downloadedURL.path
        )

        return ChunkPayload(
            fileURL: downloadedURL,
            fileOffset: 0,
            absoluteOffset: offset,
            length: length,
            isTemporary: true
        )
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? CloudStorageError else {
            return true // сетевые ошибки URLError — повторяем
        }
        switch error {
        case .network, .rateLimited:
            return true
        case .requestFailed(let statusCode, _):
            return statusCode >= 500 || statusCode == 408
        case .unauthorized:
            // Токен мог обновиться в headersProvider — одна повторная
            // попытка с новыми заголовками осмысленна.
            return true
        default:
            return false
        }
    }

    private static func mapHTTPError(status: Int) -> CloudStorageError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden("HTTP 403")
        case 404: return .notFound
        case 429: return .rateLimited
        default: return .requestFailed(statusCode: status, message: "HTTP \(status)")
        }
    }

    private static func backoffNanoseconds(attempt: Int) -> UInt64 {
        let seconds = min(pow(2.0, Double(max(attempt - 1, 0))), 16)
        return UInt64(seconds * 1_000_000_000)
    }
}

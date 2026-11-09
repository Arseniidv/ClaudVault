import Foundation

/// Читает HTTP-ресурс диапазонами (Range-запросы) чанками.
/// Используется для cloud-to-cloud переноса «на лету»:
/// источник отдаёт байты по Range, цель принимает их чанками —
/// файл не сохраняется на диск целиком и не грузится в память.
public final class HTTPChunkReader {
    private let url: URL
    private let headers: [String: String]
    private let totalSize: Int64
    private var offset: Int64 = 0
    private let chunkSize: Int64 = 8 * 1024 * 1024
    private let session: URLSession

    public init(
        url: URL,
        headers: [String: String],
        totalSize: Int64,
        session: URLSession = .shared
    ) {
        self.url = url
        self.headers = headers
        self.totalSize = totalSize
        self.session = session
    }

    /// Возвращает следующий чанк или nil, когда поток прочитан.
    public func nextChunk() async throws -> Data? {
        guard offset < totalSize else { return nil }

        let end = min(offset + chunkSize, totalSize) - 1
        var request = URLRequest(url: url)
        request.setValue(
            "bytes=\(offset)-\(end)",
            forHTTPHeaderField: "Range"
        )
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CloudStorageError.invalidResponse
            }
            // 206 — Range поддержан. 200 на offset>0 значит сервер
            // проигнорировал Range и прислал файл с начала —
            // продолжать нельзя, поток был бы испорчен.
            if offset > 0 {
                guard http.statusCode == 206 else {
                    throw CloudStorageError.operationFailed(
                        "Сервер не поддерживает загрузку по частям."
                    )
                }
            } else {
                guard (200..<300).contains(http.statusCode) else {
                    throw CloudStorageError.network("HTTP \(http.statusCode)")
                }
            }
            let expected = Int(end - offset + 1)
            let chunk = data.count > expected
                ? data.prefix(expected)
                : data
            offset += Int64(chunk.count)
            return chunk.isEmpty ? nil : Data(chunk)
        } catch let error as CloudStorageError {
            throw error
        } catch {
            throw CloudStorageError.network(error.localizedDescription)
        }
    }
}

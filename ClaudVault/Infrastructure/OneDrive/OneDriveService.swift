import Foundation

/// Клиент Microsoft Graph API для OneDrive (`/me/drive`).
///
/// Файлы описываются `driveItem`-объектами: папка определяется
/// наличием фасета `folder`, mimeType — `file.mimeType`,
/// длительность медиа — `video`/`audio.duration` (ISO 8601).
final class OneDriveService {

    private let session: URLSession
    private let tokenProvider: () async throws -> String

    private let baseURL = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!
    private let quotaURL = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!

    private static let itemFields =
        "id,name,size,lastModifiedDateTime,file,folder,video,audio,parentReference"

    /// Порог простого PUT-запроса; большие файлы — upload session.
    private let simpleUploadLimit: Int64 = 4 * 1024 * 1024
    /// Размер чанка upload session — обязан быть кратен 320 КиБ.
    private let uploadChunkSize: Int64 = 10 * 1024 * 1024

    private let maxRequestAttempts = 3

    init(
        session: URLSession = .shared,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - Files

    func listFiles(parentFolderID: String?) async throws -> [CloudFile] {
        var url: URL
        if let parentFolderID, !parentFolderID.isEmpty {
            url = itemURL(parentFolderID)
                .appendingPathComponent("children")
        } else {
            url = baseURL.appendingPathComponent("root/children")
        }
        url = try selectQuery(url)

        var result: [CloudFile] = []
        while true {
            let data = try await send(url)
            guard let page = try? JSONDecoder().decode(DriveItemList.self, from: data) else {
                throw CloudStorageError.invalidResponse
            }
            result += page.value.compactMap { $0.asCloudFile }
            guard let next = page.nextLink, let nextURL = URL(string: next) else {
                return result.sorted { lhs, rhs in
                    if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                    return lhs.name.localizedStandardCompare(rhs.name)
                        == .orderedAscending
                }
            }
            url = nextURL
        }
    }

    func fileMetadata(id: String) async throws -> CloudFile {
        var url = itemURL(id)
        url = try selectQuery(url)
        let data = try await send(url)
        guard let item = try? JSONDecoder().decode(DriveItemDTO.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        return item.asCloudFile
    }

    func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile {
        let parent = parentFolderID.flatMap { $0.isEmpty ? nil : $0 }
        let url = parent.map { itemURL($0).appendingPathComponent("children") }
            ?? baseURL.appendingPathComponent("root/children")

        let body: [String: Any] = [
            "name": name,
            "folder": [String: Any](),
            "@microsoft.graph.conflictBehavior": "rename"
        ]

        let data = try await send(
            url,
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body),
            contentType: "application/json"
        )
        guard let item = try? JSONDecoder().decode(DriveItemDTO.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        return item.asCloudFile
    }

    func deleteFile(id: String) async throws {
        _ = try await send(itemURL(id), method: "DELETE")
    }

    func searchFiles(query: String) async throws -> [CloudFile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var url = baseURL.appendingPathComponent("root/search")
        url.appendQueryItem(name: "q", value: "'\(trimmed.replacingOccurrences(of: "'", with: "''"))'")
        url = try selectQuery(url, extraTop: "50")

        let data = try await send(url)
        guard let page = try? JSONDecoder().decode(DriveItemList.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        return page.value.compactMap { $0.asCloudFile }
    }

    // MARK: - Download

    /// `/content` отдаёт 302 на CDN — URLSession следует редиректу сам.
    func downloadFile(
        id: String,
        to destination: URL
    ) async throws {
        let url = itemURL(id).appendingPathComponent("content")
        try await downloadToFile(requestURL: url, destination: destination)
    }

    /// Превью через коллекцию `thumbnails`: Graph возвращает
    /// набор размеров (small/medium/large/c400x400) с
    /// короткоживущими pre-authenticated URL.
    func thumbnailData(for file: CloudFile) async throws -> Data? {
        let thumbnailsURL = itemURL(file.id).appendingPathComponent("thumbnails")
        let data = try await send(thumbnailsURL)

        guard let list = try? JSONDecoder().decode(ThumbnailList.self, from: data),
              let set = list.value.first else {
            return nil
        }

        guard let previewURLString = set.medium?.url
                ?? set.c400x400?.url
                ?? set.large?.url
                ?? set.small?.url,
              let previewURL = URL(string: previewURLString) else {
            return nil
        }

        let (imageData, response) = try await session.data(from: previewURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !imageData.isEmpty else {
            return nil
        }
        return imageData
    }

    /// Прямая ссылка `/content` с Bearer-заголовком:
    /// `AVURLAsset` сам пройдёт 302-редирект на CDN.
    func streamDescriptor(for file: CloudFile) async throws -> CloudMediaStream {
        let url = itemURL(file.id).appendingPathComponent("content")
        let token = try await tokenProvider()
        let header = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
        return CloudMediaStream(url: url, headers: ["Authorization": header])
    }

    // MARK: - Upload

    func uploadFile(
        at fileURL: URL,
        name: String,
        mimeType: String,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> CloudFile {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value else {
            throw CloudStorageError.operationFailed("Файл недоступен для чтения.")
        }

        let parent = parentFolderID.flatMap { $0.isEmpty ? nil : $0 }

        if size <= simpleUploadLimit {
            // Простой PUT /content для небольших файлов.
            let url = try contentURL(parent: parent, name: name)
            var request = try await authorizedRequest(url: url, method: "PUT")
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.setValue("replace", forHTTPHeaderField: "x-ms-file-upload-extra")
            let body = try Data(contentsOf: fileURL)
            let (data, response) = try await perform(request, uploading: body)
            guard (200..<300).contains(response.statusCode) else {
                throw Self.mapError(status: response.statusCode, data: data)
            }
            guard let item = try? JSONDecoder().decode(DriveItemDTO.self, from: data) else {
                throw CloudStorageError.invalidResponse
            }
            progressHandler?(1.0)
            return item.asCloudFile
        }

        // Большие файлы — upload session с чанками.
        let sessionURL = try await createUploadSession(parent: parent, name: name)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var fileEOF = false
        return try await uploadChunks(
            sessionURL: sessionURL,
            totalSize: size,
            readChunk: {
                if fileEOF { return nil }
                do {
                    guard let data = try handle.read(
                        upToCount: Int(self.uploadChunkSize)
                    ), !data.isEmpty else {
                        fileEOF = true
                        return nil
                    }
                    return data
                } catch {
                    throw CloudStorageError.operationFailed(
                        "Ошибка чтения файла: \(error.localizedDescription)"
                    )
                }
            },
            progressHandler: progressHandler
        )
    }

    /// Chunked-загрузка из `readChunk` (например, HTTPChunkReader
    /// с другого облака) — файл не пишется на диск.
    func uploadStreamedFile(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64,
        readChunk: () async throws -> Data?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        guard sizeBytes >= 0 else {
            throw CloudStorageError.operationFailed("Некорректный размер файла.")
        }

        let parent = parentFolderID.flatMap { $0.isEmpty ? nil : $0 }

        if sizeBytes <= simpleUploadLimit {
            var collected = Data()
            while let chunk = try await readChunk(), !chunk.isEmpty {
                collected.append(chunk)
            }
            guard collected.count == Int(sizeBytes) else {
                throw CloudStorageError.operationFailed(
                    "Источник прислал не всё содержимое файла."
                )
            }
            let url = try contentURL(parent: parent, name: name)
            var request = try await authorizedRequest(url: url, method: "PUT")
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            let (data, response) = try await perform(request, uploading: collected)
            guard (200..<300).contains(response.statusCode) else {
                throw Self.mapError(status: response.statusCode, data: data)
            }
            guard let item = try? JSONDecoder().decode(DriveItemDTO.self, from: data) else {
                throw CloudStorageError.invalidResponse
            }
            progressHandler?(1.0)
            return item.asCloudFile
        }

        let sessionURL = try await createUploadSession(parent: parent, name: name)
        return try await uploadChunks(
            sessionURL: sessionURL,
            totalSize: sizeBytes,
            readChunk: readChunk,
            progressHandler: progressHandler
        )
    }

    private func createUploadSession(parent: String?, name: String) async throws -> URL {
        let url = parent.map { itemURL($0).appendingPathComponent("createUploadSession") }
            ?? baseURL.appendingPathComponent("root/createUploadSession")

        let body: [String: Any] = [
            "item": [
                "@microsoft.graph.conflictBehavior": "replace",
                "name": name
            ]
        ]

        let data = try await send(
            url,
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body),
            contentType: "application/json"
        )
        struct SessionResponse: Decodable { let uploadUrl: String }
        guard let decoded = try? JSONDecoder().decode(SessionResponse.self, from: data),
              let uploadURL = URL(string: decoded.uploadUrl) else {
            throw CloudStorageError.invalidResponse
        }
        return uploadURL
    }

    /// `readChunk` возвращает очередной кусок данных из источника
    /// (произвольного размера) или nil в конце. Куски буферизуются
    /// до `uploadChunkSize` (кратно 320 КиБ, как требует Graph),
    /// последний фрагмент может быть любого размера.
    private func uploadChunks(
        sessionURL: URL,
        totalSize: Int64,
        readChunk: () async throws -> Data?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        let quantum: Int64 = 320 * 1024
        var pending = Data()
        var sourceEOF = false
        var uploaded: Int64 = 0
        var lastItem: DriveItemDTO?

        while uploaded < totalSize {
            try Task.checkCancellation()

            while pending.count < Int(uploadChunkSize) && !sourceEOF {
                guard let piece = try await readChunk(), !piece.isEmpty else {
                    sourceEOF = true
                    break
                }
                pending.append(piece)
            }

            guard !pending.isEmpty else {
                throw CloudStorageError.operationFailed(
                    "Источник оборвал передачу данных."
                )
            }

            var fragmentLength = min(
                Int64(pending.count),
                min(uploadChunkSize, totalSize - uploaded)
            )
            let isLastFragment = uploaded + fragmentLength == totalSize
            if !isLastFragment {
                // Все фрагменты, кроме последнего, обязаны быть
                // кратны 320 КиБ.
                fragmentLength -= fragmentLength % quantum
                if fragmentLength == 0 {
                    // В pending меньше кванта и это не конец файла —
                    // ждём ещё данных от источника.
                    if sourceEOF {
                        throw CloudStorageError.operationFailed(
                            "Источник прислал меньше данных, чем ожидалось."
                        )
                    }
                    continue
                }
            }

            let fragment = pending.prefix(Int(fragmentLength))
            pending.removeFirst(Int(fragmentLength))
            let chunkEnd = uploaded + fragmentLength - 1

            var request = URLRequest(url: sessionURL)
            request.httpMethod = "PUT"
            request.setValue(
                "bytes \(uploaded)-\(chunkEnd)/\(totalSize)",
                forHTTPHeaderField: "Content-Range"
            )

            let (data, response) = try await perform(
                request,
                uploading: Data(fragment)
            )
            let status = response.statusCode

            // 202 Accepted — фрагмент принят, загрузка продолжается.
            if status == 202 {
                uploaded = chunkEnd + 1
                progressHandler?(min(1.0, Double(uploaded) / Double(totalSize)))
                continue
            }

            guard (200..<300).contains(status) else {
                throw Self.mapError(status: status, data: data)
            }

            lastItem = try? JSONDecoder().decode(DriveItemDTO.self, from: data)
            uploaded = chunkEnd + 1
            progressHandler?(min(1.0, Double(uploaded) / Double(totalSize)))
        }

        guard let lastItem else {
            throw CloudStorageError.invalidResponse
        }
        progressHandler?(1.0)
        return lastItem.asCloudFile
    }

    // MARK: - Storage usage

    func getStorageUsage() async throws -> CloudStorageUsage {
        var url = quotaURL
        url.appendQueryItem(name: "$select", value: "quota")
        let data = try await send(url)

        struct QuotaResponse: Decodable {
            struct Quota: Decodable {
                let used: Int64?
                let total: Int64?
            }
            let quota: Quota?
        }

        guard let decoded = try? JSONDecoder().decode(QuotaResponse.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        let used = decoded.quota?.used ?? 0
        let total = decoded.quota?.total ?? 0
        return CloudStorageUsage(
            usedBytes: used,
            totalBytes: total,
            availableBytes: max(total - used, 0)
        )
    }

    // MARK: - Download helper

    private func downloadToFile(requestURL: URL, destination: URL) async throws {
        var attempt = 0
        var didRetryAuth = false

        while true {
            let request = try await authorizedRequest(url: requestURL, method: "GET")
            do {
                let (tempURL, response) = try await session.download(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw CloudStorageError.invalidResponse
                }
                let status = http.statusCode
                if (200..<300).contains(status) {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    return
                }

                let data = (try? Data(contentsOf: tempURL)) ?? Data()
                #if DEBUG
                print(
                    "[OneDrive] HTTP \(status) GET \(requestURL.absoluteString)\n"
                        + (String(data: data, encoding: .utf8) ?? "<binary>")
                )
                #endif
                let error = Self.mapError(status: status, data: data)
                if status == 401 && !didRetryAuth {
                    didRetryAuth = true
                    continue
                }
                if Self.isRetryable(error), attempt < maxRequestAttempts - 1 {
                    attempt += 1
                    try await Task.sleep(nanoseconds: Self.backoffNanoseconds(attempt: attempt))
                    continue
                }
                throw error
            } catch let error as CancellationError {
                throw error
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as CloudStorageError {
                throw error
            } catch {
                throw CloudStorageError.network(error.localizedDescription)
            }
        }
    }

    // MARK: - URL helpers

    private func itemURL(_ id: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += "/items/" + Self.encodePathSegment(id)
        return components.url ?? baseURL
    }

    /// URL для PUT `/content`: `items/{parent}:/{name}:/content`
    /// или `root:/{name}:/content` для корня. Литеральные `:`
    /// в path-синтаксисе Graph не кодируются.
    private func contentURL(parent: String?, name: String) throws -> URL {
        let nameEncoded = Self.encodePathSegment(name)
        let path: String
        if let parent {
            path = "/items/\(Self.encodePathSegment(parent)):/\(nameEncoded)"
        } else {
            path = "/root:/\(nameEncoded)"
        }
        let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        guard var result = components else {
            throw CloudStorageError.invalidResponse
        }
        result.percentEncodedPath += path + ":/content"
        return result.url ?? baseURL
    }

    private func selectQuery(_ url: URL, extraTop: String? = nil) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CloudStorageError.invalidResponse
        }
        var items = [
            URLQueryItem(name: "$select", value: Self.itemFields),
            URLQueryItem(name: "$top", value: extraTop ?? "200")
        ]
        if let existing = components.queryItems {
            items += existing.filter { $0.name != "$select" && $0.name != "$top" }
        }
        components.queryItems = items
        guard let result = components.url else {
            throw CloudStorageError.invalidResponse
        }
        return result
    }

    private static func encodePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Networking

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = try await tokenProvider()
        let header = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
        request.setValue(header, forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(
        _ request: URLRequest,
        uploading body: Data? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        do {
            let data: Data
            let response: URLResponse
            if let body {
                (data, response) = try await session.upload(for: request, from: body)
            } else {
                (data, response) = try await session.data(for: request)
            }
            guard let http = response as? HTTPURLResponse else {
                throw CloudStorageError.invalidResponse
            }
            return (data, http)
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as CloudStorageError {
            throw error
        } catch {
            throw CloudStorageError.network(error.localizedDescription)
        }
    }

    /// Единая точка JSON-запросов: Bearer, retry для GET
    /// при 429/5xx, повторная авторизация при 401.
    private func send(
        _ url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        var attempt = 0
        var didRetryAuth = false

        while true {
            var request = try await authorizedRequest(url: url, method: method)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            request.httpBody = body

            let (data, response) = try await perform(request)
            let status = response.statusCode

            if (200..<300).contains(status) {
                return data
            }
            if status == 401 && !didRetryAuth {
                didRetryAuth = true
                continue
            }

            #if DEBUG
            print(
                "[OneDrive] HTTP \(status) \(method) \(url.absoluteString)\n"
                    + (String(data: data, encoding: .utf8) ?? "<binary>")
            )
            #endif
            let error = Self.mapError(status: status, data: data)
            if method == "GET", Self.isRetryable(error), attempt < maxRequestAttempts - 1 {
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoffNanoseconds(attempt: attempt))
                continue
            }
            throw error
        }
    }

    private static func isRetryable(_ error: CloudStorageError) -> Bool {
        switch error {
        case .network, .rateLimited:
            return true
        case .requestFailed(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }

    private static func backoffNanoseconds(attempt: Int) -> UInt64 {
        let seconds = min(pow(2.0, Double(max(attempt - 1, 0))), 16)
        return UInt64(seconds * 1_000_000_000)
    }

    // MARK: - Error mapping

    private static func mapError(status: Int, data: Data) -> CloudStorageError {
        struct GraphErrorBody: Decodable {
            struct Detail: Decodable {
                let code: String?
                let message: String?
            }
            let error: Detail?
        }

        let message = (try? JSONDecoder().decode(GraphErrorBody.self, from: data))?
            .error?.message ?? "HTTP \(status)"

        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message)
        case 404:
            return .notFound
        case 429:
            return .rateLimited
        default:
            return .requestFailed(statusCode: status, message: message)
        }
    }
}

// MARK: - DTOs

private struct DriveItemList: Decodable {
    let value: [DriveItemDTO]

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }

    let nextLink: String?
}

private struct DriveItemDTO: Decodable {
    let id: String
    let name: String
    let size: Int64?
    let lastModifiedDateTime: String?
    let file: FileFacet?
    let folder: FolderFacet?
    let video: MediaFacet?
    let audio: MediaFacet?

    struct FileFacet: Decodable {
        let mimeType: String?
    }
    struct FolderFacet: Decodable {}
    struct MediaFacet: Decodable {
        /// ISO 8601 duration, например "PT3M30.5S".
        let duration: String?
    }

    var asCloudFile: CloudFile {
        if folder != nil {
            return CloudFile(
                id: id,
                name: name,
                mimeType: CloudFile.folderMimeType,
                sizeBytes: nil,
                modifiedAt: Self.date(from: lastModifiedDateTime)
            )
        }

        return CloudFile(
            id: id,
            name: name,
            mimeType: file?.mimeType ?? "application/octet-stream",
            sizeBytes: size,
            modifiedAt: Self.date(from: lastModifiedDateTime),
            duration: Self.durationSeconds(from: video?.duration ?? audio?.duration)
        )
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Парсит ISO 8601 duration ("PT1H2M3.5S") в секунды.
    private static func durationSeconds(from value: String?) -> TimeInterval? {
        guard let value, value.hasPrefix("PT") else { return nil }
        var hours = 0.0, minutes = 0.0, seconds = 0.0
        var number = ""
        for char in value.dropFirst(2) {
            if char.isNumber || char == "." {
                number.append(char)
            } else {
                guard let parsed = Double(number), !number.isEmpty else { return nil }
                number = ""
                switch char {
                case "H": hours = parsed
                case "M": minutes = parsed
                case "S": seconds = parsed
                default: return nil
                }
            }
        }
        guard number.isEmpty else { return nil }
        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? total : nil
    }
}

private struct ThumbnailList: Decodable {
    let value: [ThumbnailSet]
}

private struct ThumbnailSet: Decodable {
    struct Size: Decodable {
        let url: String?
    }
    let id: String?
    let small: Size?
    let medium: Size?
    let large: Size?
    let c400x400: Size?
    let c10000x10000: Size?
}

private extension URL {
    mutating func appendQueryItem(name: String, value: String) {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        self = components.url ?? self
    }
}

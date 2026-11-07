import Foundation

final class GoogleDriveService {
    private let session: URLSession
    private let tokenProvider: () async throws -> String
    private let apiBaseURL = URL(string: "https://www.googleapis.com/drive/v3")!
    private let uploadBaseURL = URL(string: "https://www.googleapis.com/upload/drive/v3")!
    private static let fileFields = "id,name,mimeType,modifiedTime,size,parents,thumbnailLink,videoMediaMetadata"
    private let chunkSize: Int64 = 8 * 1024 * 1024
    private let maxUploadRetries = 5
    private let maxRequestAttempts = 3 
    
    init(
        session: URLSession = .shared,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }
    func listFiles(parentFolderID: String?) async throws -> [CloudFile] {
        let parent = Self.escapeQueryLiteral(parentFolderID ?? "root")
        var result: [CloudFile] = []
        var pageToken: String?
        
        repeat {
            var items = [
                URLQueryItem(name: "q", value: "'\(parent)' in parents and trashed = false"),
                URLQueryItem(name: "pageSize", value: "100"),
                URLQueryItem(name: "orderBy", value: "folder,modifiedTime desc,name_natural"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(\(Self.fileFields))")
            ]
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            
            guard let requestURL = makeURL(path: "files", queryItems: items) else {
                throw CloudStorageError.invalidResponse
            }
            let data = try await send(requestURL)
            guard let page = try? JSONDecoder().decode(FileListResponse.self, from: data) else {
                throw CloudStorageError.invalidResponse
            }
            result += page.files.map { $0.asCloudFile }
            pageToken = page.nextPageToken
        } while pageToken != nil
        
        return result
    }
 
    func getStorageUsage() async throws -> CloudStorageUsage {
        guard let requestURL = makeURL(
            path: "about",
            queryItems: [URLQueryItem(name: "fields", value: "storageQuota")]
        ) else { throw CloudStorageError.invalidResponse }
        
        let data = try await send(requestURL)
        guard let decoded = try? JSONDecoder().decode(AboutResponse.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        let used = decoded.storageQuota.usage?.value ?? 0
        let total = decoded.storageQuota.limit?.value ?? 0
        let available = total > 0 ? max(total - used, 0) : 0
        
        return CloudStorageUsage(
            usedBytes: used,
            totalBytes: total,
            availableBytes: available
        )
    }
    /// Поиск файлов по имени по всему «Моему диску».
    func searchFiles(query: String) async throws -> [CloudFile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let escaped = Self.escapeQueryLiteral(trimmed)
        guard let requestURL = makeURL(
            path: "files",
            queryItems: [
                URLQueryItem(
                    name: "q",
                    value: "name contains '\(escaped)' and trashed = false"
                ),
                URLQueryItem(name: "pageSize", value: "50"),
                URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
                URLQueryItem(name: "fields", value: "files(\(Self.fileFields))")
            ]
        ) else { throw CloudStorageError.invalidResponse }

        let data = try await send(requestURL)
        guard let page = try? JSONDecoder().decode(FileListResponse.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        return page.files.map { $0.asCloudFile }
    }

    func fileMetadata(id: String) async throws -> CloudFile {
        guard let requestURL = makeURL(
            path: "files/\(Self.encodePathSegment(id))",
            queryItems: [URLQueryItem(name: "fields", value: Self.fileFields)]
        ) else { throw CloudStorageError.invalidResponse }

        let data = try await send(requestURL)
        guard let decoded = try? JSONDecoder().decode(FileDTO.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        return decoded.asCloudFile
    }

    func deleteFile(id: String) async throws {
        guard let requestURL = makeURL(
            path: "files/\(Self.encodePathSegment(id))", queryItems: []
        ) else { throw CloudStorageError.invalidResponse }

        let _ = try await send(requestURL, method: "DELETE")
    }

    /// Скачивает JPEG-миниатюру по `thumbnailLink` файла.
    /// Ссылка требует тот же Bearer-токен, что и Drive API.
    func thumbnailData(for file: CloudFile) async throws -> Data? {
        guard let thumbnailString = file.thumbnailURL,
              var thumbnailURL = URL(string: thumbnailString) else {
            return nil
        }
        // Запрашиваем компактный размер 256px независимо от того,
        // что вернул API (обычно =s220 или больше).
        if var components = URLComponents(url: thumbnailURL, resolvingAgainstBaseURL: false) {
            components.percentEncodedPath = components.percentEncodedPath
                .replacingOccurrences(of: #"=s\d+$"#, with: "=s256", options: .regularExpression)
            thumbnailURL = components.url ?? thumbnailURL
        }

        let data = try await send(thumbnailURL)
        // Google может вернуть 200 с пустым телом для файлов без превью.
        return data.isEmpty ? nil : data
    }

    /// Прямая ссылка для потокового воспроизведения (`alt=media`)
    /// с Bearer-заголовком для `AVURLAsset`.
    func streamDescriptor(for file: CloudFile) async throws -> CloudMediaStream {
        guard let url = makeURL(
            path: "files/\(Self.encodePathSegment(file.id))",
            queryItems: [URLQueryItem(name: "alt", value: "media")]
        ) else { throw CloudStorageError.invalidResponse }

        let token = try await tokenProvider()
        let header = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
        return CloudMediaStream(url: url, headers: ["Authorization": header])
    }

    /// Скачивает содержимое файла (`alt=media`) в `destination`.
    /// Используется для переноса файлов между облаками.
    func downloadFile(
        id: String,
        to destination: URL
    ) async throws {
        guard let requestURL = makeURL(
            path: "files/\(Self.encodePathSegment(id))",
            queryItems: [URLQueryItem(name: "alt", value: "media")]
        ) else { throw CloudStorageError.invalidResponse }

        try await downloadToFile(requestURL: requestURL, destination: destination)
    }

    /// Экспортирует Google Workspace файл (Docs/Sheets/Slides/…) в указанный
    /// MIME-формат и скачивает результат в `destination`.
    /// Для обычных файлов вернёт ошибку — используйте `downloadFile`.
    func exportFile(
        id: String,
        exportMimeType: String,
        to destination: URL
    ) async throws {
        guard let requestURL = makeURL(
            path: "files/\(Self.encodePathSegment(id))/export",
            queryItems: [URLQueryItem(name: "mimeType", value: exportMimeType)]
        ) else { throw CloudStorageError.invalidResponse }

        try await downloadToFile(requestURL: requestURL, destination: destination)
    }

    /// Общий цикл скачивания URL → локальный файл с retry и
    /// повторной авторизацией при 401.
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
                    "[GoogleDrive] HTTP \(status) GET \(requestURL.absoluteString)\n"
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

    func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile {
        guard let requestURL = makeURL(
            path: "files",
            queryItems: [URLQueryItem(name: "fields", value: Self.fileFields)]
        ) else { throw CloudStorageError.invalidResponse }
        
        var body: [String: Any] = [
            "name": name,
            "mimeType": CloudFile.folderMimeType
        ]
        if let parentFolderID {
            body["parents"] = [parentFolderID]
        }
        
        let data = try await send(
            requestURL,
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body),
            contentType: "application/json; charset=UTF-8"
        )
        guard let decoded = try? JSONDecoder().decode(FileDTO.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        return decoded.asCloudFile
    }
    
    // MARK: - Upload
    /// `progressHandler` вызывается с долей завершённой загрузки (0...1)
    /// после каждого принятого сервером чанка.
    func uploadFile(
        at fileURL: URL,
        name: String,
        mimeType: String,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> CloudFile {
        // Сначала проверяем файл, и только потом создаём сессию на сервере.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            throw CloudStorageError.operationFailed("Файл недоступен для чтения.")
        }
        let fileSize = sizeNumber.int64Value
        
        let sessionURL = try await createUploadSession(
            name: name,
            mimeType: mimeType,
            parentFolderID: parentFolderID,
            fileSize: fileSize
        )
        
        var uploadedBytes: Int64 = 0
        var failedAttempts = 0
        
        // do/while-семантика: пустой файл (0 байт) тоже должен пройти один запрос.
        while true {
            try Task.checkCancellation()
            do {
                let result = try await uploadChunk(
                    sessionURL: sessionURL,
                    fileURL: fileURL,
                    fileSize: fileSize,
                    uploadedBytes: uploadedBytes,
                    mimeType: mimeType
                )
                
                if result.isComplete, let file = result.file {
                    return file
                }
                
                // Защита от бесконечного цикла, если сервер не продвигает смещение.
                if result.nextByte > uploadedBytes {
                    failedAttempts = 0
                } else {
                    failedAttempts += 1
                    guard failedAttempts <= maxUploadRetries else {
                        throw CloudStorageError.operationFailed("Сервер не принимает данные, загрузка прервана.")
                    }
                }
                uploadedBytes = result.nextByte
                progressHandler?(Self.uploadProgress(uploaded: uploadedBytes, total: fileSize))
            } catch let error as CloudStorageError where Self.isRetryable(error) {
                // Сетевой сбой / 5xx / лимиты: спрашиваем у сервера, сколько байт он реально принял, и продолжаем.
                failedAttempts += 1
                guard failedAttempts <= maxUploadRetries else { throw error }
                try await Task.sleep(nanoseconds: Self.backoffNanoseconds(attempt: failedAttempts))
                
                switch try await queryUploadStatus(sessionURL: sessionURL, fileSize: fileSize) {
                case .completed(let file):
                    guard let file else { throw CloudStorageError.invalidResponse }
                    return file
                case .inProgress(let nextByte):
                    uploadedBytes = nextByte
                    progressHandler?(Self.uploadProgress(uploaded: nextByte, total: fileSize))
                }
            }
        }
    }
    
    func createUploadSession(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        fileSize: Int64? = nil
    ) async throws -> URL {
        var metadata: [String: Any] = [
            "name": name,
            "mimeType": mimeType
        ]
        if let parentFolderID {
            metadata["parents"] = [parentFolderID]
        }
        
        guard let startURL = makeURL(
            path: "files",
            queryItems: [
                URLQueryItem(name: "uploadType", value: "resumable"),
                URLQueryItem(name: "fields", value: Self.fileFields)
            ],
            base: uploadBaseURL
        ) else { throw CloudStorageError.invalidResponse }
        
        var request = try await authorizedRequest(url: startURL, method: "POST")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        if let fileSize {
            request.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        
        let (data, response) = try await perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.mapError(status: response.statusCode, data: data)
        }
        
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: location) else {
            throw CloudStorageError.invalidResponse
        }
        return sessionURL
    }
    
    func uploadChunk(
        sessionURL: URL,
        fileURL: URL,
        fileSize: Int64,
        uploadedBytes: Int64,
        mimeType: String
    ) async throws -> UploadChunkResult {
        
        guard uploadedBytes >= 0,
              uploadedBytes <= fileSize,
              (fileSize == 0 || uploadedBytes < fileSize) else {
            throw CloudStorageError.operationFailed(
                "Некорректное смещение загрузки."
            )
        }
        
        let chunkLength = fileSize == 0 ? 0 : Int(min(chunkSize, fileSize - uploadedBytes))
        
        var request = try await authorizedRequest(url: sessionURL, method: "PUT")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        if fileSize > 0 {
            let chunkEnd = uploadedBytes + Int64(chunkLength) - 1
            request.setValue("bytes \(uploadedBytes)-\(chunkEnd)/\(fileSize)", forHTTPHeaderField: "Content-Range")
        } else {
            request.setValue("bytes */0", forHTTPHeaderField: "Content-Range")
        }
        
        // Читаем только нужный кусок, а не весь файл целиком.
        let chunkData = try readChunk(from: fileURL, offset: uploadedBytes, length: chunkLength)
        
        let (data, response) = try await perform(request, uploading: chunkData)
        let status = response.statusCode
        
        if status == 308 {
            let nextByte = Self.parseRangeHeader(response.value(forHTTPHeaderField: "Range"), totalSize: fileSize)
            return UploadChunkResult(nextByte: nextByte, isComplete: false, file: nil)
        }
        
        guard (200..<300).contains(status) else {
            throw Self.mapError(status: status, data: data)
        }
        
        guard let decoded = try? JSONDecoder().decode(FileDTO.self, from: data) else {
            throw CloudStorageError.invalidResponse
        }
        return UploadChunkResult(nextByte: fileSize, isComplete: true, file: decoded.asCloudFile)
    }
    
    /// Возвращает, сколько байт сервер уже принял (если загрузка завершена — `fileSize`).
    func checkUploadStatus(sessionURL: URL, fileSize: Int64) async throws -> Int64 {
        switch try await queryUploadStatus(sessionURL: sessionURL, fileSize: fileSize) {
        case .inProgress(let nextByte): return nextByte
        case .completed: return fileSize
        }
    }
    
    /// Потоковая загрузка файла: чанки приходят из `readChunk`
    /// (например, HTTPChunkReader с другого облака) — файл не пишется
    /// на диск и не загружается в память целиком.
    /// Использует ту же resumable-сессию, что и обычная загрузка.
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

        let sessionURL = try await createUploadSession(
            name: name,
            mimeType: mimeType,
            parentFolderID: parentFolderID,
            fileSize: sizeBytes
        )

        var uploadedBytes: Int64 = 0

        // Пустой файл: один PUT без тела.
        if sizeBytes == 0 {
            var request = try await authorizedRequest(url: sessionURL, method: "PUT")
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            request.setValue("bytes */0", forHTTPHeaderField: "Content-Range")
            let (data, response) = try await perform(request, uploading: Data())
            guard (200..<300).contains(response.statusCode) else {
                throw Self.mapError(status: response.statusCode, data: data)
            }
            guard let decoded = try? JSONDecoder().decode(FileDTO.self, from: data) else {
                throw CloudStorageError.invalidResponse
            }
            return decoded.asCloudFile
        }

        while uploadedBytes < sizeBytes {
            try Task.checkCancellation()
            guard let chunk = try await readChunk(), !chunk.isEmpty else {
                throw CloudStorageError.operationFailed(
                    "Источник оборвал передачу данных."
                )
            }
            let chunkSize = Int64(chunk.count)
            guard uploadedBytes + chunkSize <= sizeBytes else {
                throw CloudStorageError.operationFailed(
                    "Источник прислал больше данных, чем ожидалось."
                )
            }

            var request = try await authorizedRequest(url: sessionURL, method: "PUT")
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            let chunkEnd = uploadedBytes + chunkSize - 1
            request.setValue(
                "bytes \(uploadedBytes)-\(chunkEnd)/\(sizeBytes)",
                forHTTPHeaderField: "Content-Range"
            )

            let (data, response) = try await perform(request, uploading: chunk)
            let status = response.statusCode

            if status == 308 {
                let nextByte = Self.parseRangeHeader(
                    response.value(forHTTPHeaderField: "Range"),
                    totalSize: sizeBytes
                )
                uploadedBytes = nextByte
                progressHandler?(Self.uploadProgress(uploaded: uploadedBytes, total: sizeBytes))
                continue
            }

            guard (200..<300).contains(status) else {
                throw Self.mapError(status: status, data: data)
            }
            guard let decoded = try? JSONDecoder().decode(FileDTO.self, from: data) else {
                throw CloudStorageError.invalidResponse
            }
            progressHandler?(1.0)
            return decoded.asCloudFile
        }

        throw CloudStorageError.operationFailed(
            "Загрузка завершилась без финального ответа."
        )
    }

    /// Результат опроса resumable-сессии.
    enum UploadProgress {
        case inProgress(nextByte: Int64)
        case completed(CloudFile?)
    }

    /// PUT одного фрагмента resumable-сессии: читает `length` байт
    /// из `chunkFile` начиная с `chunkOffset` и отправляет их как
    /// диапазон `absoluteOffset.../totalSize`. Ответ 308 —
    /// `.progress` с подтверждённым смещением, 2xx — `.completed`.
    func sendResumableChunk(
        sessionURL: URL,
        chunkFile: URL,
        chunkOffset: Int64,
        length: Int,
        absoluteOffset: Int64,
        totalSize: Int64,
        mimeType: String
    ) async throws -> ResumableSendResult {
        var request = try await authorizedRequest(url: sessionURL, method: "PUT")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        if totalSize > 0 {
            let chunkEnd = absoluteOffset + Int64(length) - 1
            request.setValue(
                "bytes \(absoluteOffset)-\(chunkEnd)/\(totalSize)",
                forHTTPHeaderField: "Content-Range"
            )
        } else {
            request.setValue("bytes */0", forHTTPHeaderField: "Content-Range")
        }

        let body = length > 0
            ? try readChunk(from: chunkFile, offset: chunkOffset, length: length)
            : Data()
        let (data, response) = try await perform(request, uploading: body)
        let status = response.statusCode

        if status == 308 {
            let nextByte = Self.parseRangeHeader(
                response.value(forHTTPHeaderField: "Range"),
                totalSize: totalSize
            )
            return .progress(nextByte)
        }
        guard (200..<300).contains(status) else {
            throw Self.mapError(status: status, data: data)
        }
        let file = (try? JSONDecoder().decode(FileDTO.self, from: data))?.asCloudFile
        return .completed(file)
    }

    enum ResumableSendResult {
        case progress(Int64)
        case completed(CloudFile?)
    }

    /// Опрос статуса resumable-сессии (сколько байт принято / завершена).
    func queryUploadStatus(sessionURL: URL, fileSize: Int64) async throws -> UploadProgress {
        var request = try await authorizedRequest(url: sessionURL, method: "PUT")
        request.setValue("bytes */\(fileSize)", forHTTPHeaderField: "Content-Range")

        let (data, response) = try await perform(request, uploading: Data())
        let status = response.statusCode

        if status == 308 {
            let nextByte = Self.parseRangeHeader(response.value(forHTTPHeaderField: "Range"), totalSize: fileSize)
            return .inProgress(nextByte: nextByte)
        }
        if (200..<300).contains(status) {
            // При завершённой загрузке сервер возвращает метаданные файла.
            let file = (try? JSONDecoder().decode(FileDTO.self, from: data))?.asCloudFile
            return .completed(file)
        }
        throw Self.mapError(status: status, data: data)
    }

    /// URL прямого скачивания (`alt=media`) для Range-источника
    /// cloud-to-cloud передачи.
    func mediaDownloadURL(for file: CloudFile) -> URL? {
        makeURL(
            path: "files/\(Self.encodePathSegment(file.id))",
            queryItems: [URLQueryItem(name: "alt", value: "media")]
        )
    }

    /// Провайдер свежих заголовков Authorization для Range-запросов:
    /// вызывается перед каждой попыткой, токен может обновиться.
    func chunkSourceHeadersProvider() -> @Sendable () async throws -> [String: String] {
        { [tokenProvider] in
            let token = try await tokenProvider()
            let header = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
            return ["Authorization": header]
        }
    }

    /// Читает `length` байт из `fileURL` начиная с `offset`.
    /// Диапазонное чтение — файл целиком в память не грузится.
    func readFileRange(from fileURL: URL, offset: Int64, length: Int) throws -> Data {
        try readChunk(from: fileURL, offset: offset, length: length)
    }

    /// Экранирует сегмент пути для Drive API.
    static func encodeID(_ id: String) -> String {
        encodePathSegment(id)
    }

    private func readChunk(from fileURL: URL, offset: Int64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        do {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }
            try fileHandle.seek(toOffset: UInt64(offset))
            guard let data = try fileHandle.read(upToCount: length), data.count == length else {
                throw CloudStorageError.operationFailed("Файл изменился во время загрузки или не читается.")
            }
            return data
        } catch let error as CloudStorageError {
            throw error
        } catch {
            throw CloudStorageError.operationFailed("Ошибка чтения файла: \(error.localizedDescription)")
        }
    }
    
    private static func uploadProgress(uploaded: Int64, total: Int64) -> Double {
        guard total > 0 else { return uploaded > 0 ? 1 : 0 }
        return min(max(Double(uploaded) / Double(total), 0), 1)
    }

    /// Формат заголовка: "bytes=0-524287". Отсутствие заголовка означает «ничего не получено».
    static func parseRangeHeader(_ rangeHeader: String?, totalSize: Int64) -> Int64 {
        guard let rangeHeader,
              let prefix = rangeHeader.range(of: "bytes=") else { return 0 }
        let parts = rangeHeader[prefix.upperBound...].split(separator: "-")
        guard parts.count == 2, let lastUploadedByte = Int64(parts[1]) else { return 0 }
        return min(lastUploadedByte + 1, totalSize)
    }
    
    struct UploadChunkResult {
        let nextByte: Int64
        let isComplete: Bool
        let file: CloudFile?
    }
    
    // MARK: - Networking
    private func makeURL(path: String, queryItems: [URLQueryItem], base: URL? = nil) -> URL? {
        guard var components = URLComponents(url: base ?? apiBaseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // `path` уже должен быть экранирован (см. encodePathSegment).
        components.percentEncodedPath += "/" + path
        components.queryItems = queryItems
        // URLComponents не экранирует "+", а сервер читает его как пробел.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
    
    /// Authorization-заголовок. Работает и если провайдер вернул «голый» токен, и если «Bearer …».
    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = try await tokenProvider()
        let header = token.hasPrefix("Bearer ") ? token : "Bearer \(token)"
        request.setValue(header, forHTTPHeaderField: "Authorization")
        return request
    }
    
    /// Единая точка сетевых вызовов: отмена задачи не маскируется под сетевую ошибку.
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
    
    private func send(
        _ url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        var attempt = 0
        var didRetryAuth = false
        
        while true {
            // Токен запрашиваем заново на каждой попытке — провайдер может его обновить.
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
                "[GoogleDrive] HTTP \(status) \(method) \(url.absoluteString)\n"
                    + (String(data: data, encoding: .utf8) ?? "<binary>")
            )
            #endif
            let error = Self.mapError(status: status, data: data)
            // Повторяем только идемпотентные GET (при лимитах и 5xx) — чтобы не плодить дубликаты папок.
            if method == "GET", Self.isRetryable(error), attempt < maxRequestAttempts - 1 {
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoffNanoseconds(attempt: attempt))
                continue
            }
            throw error
        }
    }
    
    static func isRetryable(_ error: CloudStorageError) -> Bool {
        switch error {
        case .network, .rateLimited:
            return true
        case .requestFailed(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }
    
    static func backoffNanoseconds(attempt: Int) -> UInt64 {
        let seconds = min(pow(2.0, Double(max(attempt - 1, 0))), 16)
        return UInt64(seconds * 1_000_000_000)
    }
    
    // MARK: - Escaping helpers
    /// Экранирование значения внутри кавычек в поисковом запросе Drive (`q`).
    private static func escapeQueryLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
    
    private static func encodePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
    
    // MARK: - Error Mapping
    private static func mapError(status: Int, data: Data) -> CloudStorageError {
        let body = try? JSONDecoder().decode(DriveErrorBody.self, from: data)
        let message = body?.error.message ?? "HTTP \(status)"
        let reasons = body?.error.errors?.compactMap { $0.reason } ?? []
        
        switch status {
        case 401:
            return .unauthorized
        case 403:
            if reasons.contains("rateLimitExceeded")
                || reasons.contains("userRateLimitExceeded")
                || message.lowercased().contains("rate limit") {
                return .rateLimited
            }
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
private struct AboutResponse: Decodable {
    let storageQuota: StorageQuota
}

private struct StorageQuota: Decodable {
    let limit: FlexibleInt64?
    let usage: FlexibleInt64?
    let usageInDrive: FlexibleInt64?
}

private struct FileListResponse: Decodable {
    let files: [FileDTO]
    let nextPageToken: String?
}

private struct FileDTO: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: String?
    let size: FlexibleInt64?
    let thumbnailLink: String?
    let videoMediaMetadata: VideoMediaMetadata?

    var asCloudFile: CloudFile {
        CloudFile(
            id: id,
            name: name,
            mimeType: mimeType,
            sizeBytes: size?.value,
            modifiedAt: Self.date(from: modifiedTime),
            thumbnailURL: thumbnailLink,
            duration: videoMediaMetadata?.durationSeconds
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
}

/// Drive отдаёт `durationMillis` строкой, как и `size`.
private struct VideoMediaMetadata: Decodable {
    let durationMillis: FlexibleInt64?

    var durationSeconds: TimeInterval? {
        guard let millis = durationMillis?.value, millis > 0 else { return nil }
        return TimeInterval(millis) / 1000.0
    }
}

/// Drive отдаёт int64 строкой ("size": "1024"), но на всякий случай поддерживаем и число.
private struct FlexibleInt64: Decodable {
    let value: Int64
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let number = Int64(string) {
            value = number
            return
        }
        if let number = try? container.decode(Int64.self) {
            value = number
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Некорректное числовое значение"
        )
    }
}

private struct DriveErrorBody: Decodable {
    struct Detail: Decodable {
        let reason: String?
    }
    struct APIError: Decodable {
        let code: Int?
        let message: String?
        let errors: [Detail]?
    }
    let error: APIError
}

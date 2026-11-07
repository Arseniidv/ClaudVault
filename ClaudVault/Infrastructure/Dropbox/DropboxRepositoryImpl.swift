import Foundation
import UniformTypeIdentifiers
import SwiftyDropbox

/// Реализация `CloudStorageRepository` поверх SwiftyDropbox.
///
/// В качестве `CloudFile.id` используется `pathLower` Dropbox —
/// он стабилен между запросами и подходит для `getMetadata`/`deleteV2`,
/// в отличие от file id, который требует других эндпоинтов.
final class DropboxRepositoryImpl: CloudStorageRepository {

    private let authManager: DropboxAuthManager

    init(authManager: DropboxAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Connection

    func connect() async throws -> CloudStorageAccount {
        try await authManager.connect()
    }

    func restoreConnection() async throws -> CloudStorageAccount? {
        try await authManager.restoreConnection()
    }

    func signOut() async throws {
        authManager.signOut()
    }

    // MARK: - Files

    func listFiles(parentFolderID: String?) async throws -> [CloudFile] {
        let client = try authorizedClient()
        let path = parentFolderID ?? ""

        do {
            var page = try await client.files
                .listFolder(path: path)
                .response()

            var files = page.entries.compactMap(Self.mapMetadata)

            while page.hasMore {
                page = try await client.files
                    .listFolderContinue(cursor: page.cursor)
                    .response()
                files += page.entries.compactMap(Self.mapMetadata)
            }

            // Папки первыми, затем по имени — как в Google Drive.
            return files.sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } catch let error as CallError<Files.ListFolderError> {
            #if DEBUG
            print("[Dropbox] listFolder(path: \(path)) failed: \(error)")
            #endif
            throw DropboxAuthManager.mapError(error)
        } catch let error as CallError<Files.ListFolderContinueError> {
            #if DEBUG
            print("[Dropbox] listFolderContinue failed: \(error)")
            #endif
            throw DropboxAuthManager.mapError(error)
        }
    }

    func fileMetadata(id: String) async throws -> CloudFile {
        let client = try authorizedClient()

        do {
            let metadata = try await client.files
                .getMetadata(path: id)
                .response()

            guard let file = Self.mapMetadata(metadata) else {
                throw CloudStorageError.invalidResponse
            }
            return file
        } catch let error as CallError<Files.GetMetadataError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    func createFolder(
        name: String,
        parentFolderID: String?
    ) async throws -> CloudFile {
        let client = try authorizedClient()
        let path = Self.joinPath(parent: parentFolderID, name: name)

        do {
            let result = try await client.files
                .createFolderV2(path: path, autorename: true)
                .response()

            return Self.mapFolder(result.metadata)
        } catch let error as CallError<Files.CreateFolderError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    /// Файлы больше этого порога грузятся через upload-сессию:
    /// `/files/upload` имеет жёсткий лимит ~150 МБ (фото ProRAW,
    /// видео), а сессия — до 350 ГБ.
    private static let sessionUploadThreshold: Int64 = 64 * 1024 * 1024

    /// `progressHandler` получает долю завершённой загрузки (0...1)
    /// по мере передачи данных.
    func uploadFile(
        at fileURL: URL,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        let path = Self.joinPath(
            parent: parentFolderID,
            name: fileURL.lastPathComponent
        )

        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: fileURL.path
        ),
              let size = (attributes[.size] as? NSNumber)?.int64Value else {
            throw CloudStorageError.operationFailed("Файл недоступен для чтения.")
        }

        // Большие файлы — только через upload-сессию: простой
        // /files/upload отклоняет всё, что больше ~150 МБ.
        if size > Self.sessionUploadThreshold {
            let session = DropboxTransferSession.begin(commitPath: path)
            let source = FileChunkSource(fileURL: fileURL, totalSize: size)
            return try await ChunkedUploadRunner.run(
                source: source,
                session: session,
                chunkSize: 8 * 1024 * 1024
            ) { offset in
                progressHandler?(min(1.0, Double(offset) / Double(max(size, 1))))
            }
        }

        let client = try authorizedClient()

        do {
            var request = client.files.upload(
                path: path,
                mode: .overwrite,
                input: fileURL
            )

            if let progressHandler {
                request = request.progress { progress in
                    progressHandler(progress.fractionCompleted)
                }
            }

            let metadata = try await request.response()

            guard let file = Self.mapMetadata(metadata) else {
                throw CloudStorageError.invalidResponse
            }
            return file
        } catch let error as CallError<Files.UploadError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    /// Upload-сессия Dropbox для TransferEngine.
    /// Состояние — `dbx:<sessionId>:<offset>`; без sessionId
    /// (сессия ещё не начата) состояние пустое и resume
    /// восстанавливает только offset=0.
    func makeUploadSession(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64,
        resumeState: String?
    ) async throws -> (session: any TransferSession, state: String)? {
        let path = Self.joinPath(parent: parentFolderID, name: name)

        if let resumeState, !resumeState.isEmpty {
            guard var session = DropboxTransferSession.restore(
                resumeState: resumeState,
                commitPath: path
            ) else {
                return nil
            }
            session.setCommitPath(path)
            return (session, session.stateValue)
        }

        let session = DropboxTransferSession.begin(commitPath: path)
        return (session, session.stateValue)
    }

    /// Временная ссылка Dropbox (~4 ч) как Range-источник
    /// cloud-to-cloud передачи. Ссылка без авторизации.
    func makeChunkSource(for file: CloudFile) async throws -> (any ChunkSource)? {
        guard let sizeBytes = file.sizeBytes, sizeBytes >= 0 else {
            return nil
        }
        let client = try authorizedClient()

        do {
            let result = try await client.files
                .getTemporaryLink(path: file.id)
                .response()
            guard let url = URL(string: result.link) else {
                return nil
            }
            return HTTPRangeChunkSource(
                url: url,
                totalSize: sizeBytes,
                headersProvider: { [:] }
            )
        } catch {
            return nil
        }
    }

    /// Глобальный поиск по всему Dropbox через `files/search_v2`.
    func searchFiles(query: String) async throws -> [CloudFile] {
        let client = try authorizedClient()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            let result = try await client.files.searchV2(
                query: trimmed,
                options: Files.SearchOptions(
                    maxResults: 100,
                    filenameOnly: true
                )
            ).response()

            return result.matches.compactMap { match in
                guard case .metadata(let metadata) = match.metadata else {
                    return nil
                }
                return Self.mapMetadata(metadata)
            }
        } catch let error as CallError<Files.SearchError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    /// Скачивает файл по пути в локальный `destination`.
    /// Используется для переноса файлов между облаками.
    func downloadFile(
        id: String,
        to destination: URL,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws {
        let client = try authorizedClient()

        do {
            _ = try await client.files
                .download(path: id, overwrite: true, destination: destination)
                .response()
        } catch let error as CallError<Files.DownloadError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    /// Превью через `files/get_thumbnail` (только для изображений
    /// и некоторых типов файлов — Dropbox вернёт ошибку иначе).
    func thumbnailData(for file: CloudFile) async throws -> Data? {
        let client = try authorizedClient()

        return try await withCheckedThrowingContinuation { continuation in
            client.files
                .getThumbnail(
                    path: file.id,
                    format: .jpeg,
                    size: .w256h256,
                    mode: .fitoneBestfit
                )
                .response { result, error in
                    if let result {
                        // (FileMetadata, Data) — второе значение и есть картинка.
                        continuation.resume(returning: result.1)
                    } else if let error {
                        continuation.resume(
                            throwing: DropboxAuthManager.mapError(error)
                        )
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
        }
    }

    /// Chunked-загрузка через upload session:
    /// start → appendV2 (чанки) → finish (последний чанк).
    /// Файл не пишется на диск — данные идут из `readChunk`.
    func uploadStreamedFile(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64?,
        readChunk: () async throws -> Data?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        let client = try authorizedClient()
        let path = Self.joinPath(parent: parentFolderID, name: name)
        let commit = Files.CommitInfo(path: path, mode: .overwrite)

        do {
            guard let firstChunk = try await readChunk() else {
                // Пустой файл: start + finish без данных.
                let started = try await client.files
                    .uploadSessionStart(close: false, input: Data())
                    .response()
                let metadata = try await client.files
                    .uploadSessionFinish(
                        cursor: Files.UploadSessionCursor(
                            sessionId: started.sessionId,
                            offset: 0
                        ),
                        commit: commit,
                        input: Data()
                    )
                    .response()
                guard let file = Self.mapMetadata(metadata) else {
                    throw CloudStorageError.invalidResponse
                }
                return file
            }

            let started = try await client.files
                .uploadSessionStart(close: false, input: firstChunk)
                .response()
            var offset = UInt64(firstChunk.count)

            // Остальные чанки — через appendV2, коммит — finish
            // с пустым телом (все данные уже в сессии).
            while let chunk = try await readChunk() {
                _ = try await client.files
                    .uploadSessionAppendV2(
                        cursor: Files.UploadSessionCursor(
                            sessionId: started.sessionId,
                            offset: offset
                        ),
                        close: false,
                        input: chunk
                    )
                    .response()
                offset += UInt64(chunk.count)
                let total = max(Int64(sizeBytes ?? 0), 1)
                progressHandler?(min(1.0, Double(offset) / Double(total)))
            }

            let metadata = try await client.files
                .uploadSessionFinish(
                    cursor: Files.UploadSessionCursor(
                        sessionId: started.sessionId,
                        offset: offset
                    ),
                    commit: commit,
                    input: Data()
                )
                .response()

            guard let file = Self.mapMetadata(metadata) else {
                throw CloudStorageError.invalidResponse
            }
            progressHandler?(1.0)
            return file
        } catch let error as CallError<Files.UploadSessionStartError> {
            throw DropboxAuthManager.mapError(error)
        } catch let error as CallError<Files.UploadSessionAppendError> {
            throw DropboxAuthManager.mapError(error)
        } catch let error as CallError<Files.UploadSessionFinishError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    /// Временная прямая ссылка для стриминга (~4 часа).
    func streamDescriptor(
        for file: CloudFile
    ) async throws -> CloudMediaStream {
        let client = try authorizedClient()

        do {
            let result = try await client.files
                .getTemporaryLink(path: file.id)
                .response()

            guard let url = URL(string: result.link) else {
                throw CloudStorageError.invalidResponse
            }
            return CloudMediaStream(url: url, headers: [:])
        } catch let error as CallError<Files.GetTemporaryLinkError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    func deleteFile(id: String) async throws {
        let client = try authorizedClient()

        do {
            _ = try await client.files
                .deleteV2(path: id)
                .response()
        } catch let error as CallError<Files.DeleteError> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    func getStorageUsage() async throws -> CloudStorageUsage {
        let client = try authorizedClient()

        do {
            let usage = try await client.users
                .getSpaceUsage()
                .response()

            let total: UInt64
            switch usage.allocation {
            case .individual(let allocation):
                total = allocation.allocated
            case .team(let allocation):
                total = allocation.allocated
            case .other:
                total = 0
            }

            let used = usage.used
            let available = total > used ? total - used : 0

            return CloudStorageUsage(
                usedBytes: Int64(min(used, UInt64(Int64.max))),
                totalBytes: Int64(min(total, UInt64(Int64.max))),
                availableBytes: Int64(min(available, UInt64(Int64.max)))
            )
        } catch let error as CallError<Void> {
            throw DropboxAuthManager.mapError(error)
        }
    }

    // MARK: - Helpers

    private func authorizedClient() throws -> DropboxClient {
        guard let client = DropboxClientsManager.authorizedClient else {
            throw CloudStorageError.notConnected
        }
        return client
    }

    /// "" или nil → "/name"; "/folder" → "/folder/name".
    private static func joinPath(parent: String?, name: String) -> String {
        guard let parent, !parent.isEmpty else {
            return "/\(name)"
        }
        return parent.hasSuffix("/") ? parent + name : parent + "/" + name
    }

    /// Предпочитаем `pathLower` — он нужен для `joinPath` при загрузке
    /// и создании папок внутри текущей. Если элемент не примонтирован
    /// (папка внутри «чужой» shared/team-папки, видимая только в поиске),
    /// `pathLower`/`pathDisplay` равны nil — тогда берём стабильный `id`
    /// вида `id:…`: Dropbox API принимает его везде, где ожидается `path`
    /// (list_folder, get_metadata, download, delete и т.д.).
    private static func pathID(for metadata: Files.Metadata) -> String {
        // pathDisplay сохраняет регистр и актуальный путь,
        // pathLower — нижний регистр (для общих папок может
        // не совпадать с путём в namespace пользователя).
        metadata.pathDisplay
            ?? metadata.pathLower
            ?? stableID(for: metadata)
            ?? "/\(metadata.name)"
    }

    private static func stableID(for metadata: Files.Metadata) -> String? {
        switch metadata {
        case let file as Files.FileMetadata:
            return file.id
        case let folder as Files.FolderMetadata:
            return folder.id
        default:
            return nil
        }
    }

    private static func mapMetadata(_ metadata: Files.Metadata) -> CloudFile? {
        switch metadata {
        case let file as Files.FileMetadata:
            return CloudFile(
                id: pathID(for: file),
                name: file.name,
                mimeType: mimeType(for: file.name),
                sizeBytes: Int64(min(file.size, UInt64(Int64.max))),
                modifiedAt: file.serverModified,
                duration: videoDuration(from: file)
            )
        case let folder as Files.FolderMetadata:
            return mapFolder(folder)
        default:
            // DeletedMetadata и прочие служебные записи пропускаем.
            return nil
        }
    }

    /// Длительность видео из `media_info` (миллисекунды → секунды).
    /// Аудио-метаданные Dropbox не отдаёт — длительность треков
    /// известна только после открытия в плеере.
    private static func videoDuration(from file: Files.FileMetadata) -> TimeInterval? {
        guard case .metadata(let media) = file.mediaInfo,
              let video = media as? Files.VideoMetadata,
              let ms = video.duration else {
            return nil
        }
        return TimeInterval(ms) / 1000.0
    }

    private static func mapFolder(_ folder: Files.FolderMetadata) -> CloudFile {
        CloudFile(
            id: pathID(for: folder),
            name: folder.name,
            mimeType: CloudFile.folderMimeType,
            sizeBytes: nil,
            modifiedAt: nil
        )
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

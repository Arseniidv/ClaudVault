import Foundation

protocol CloudStorageRepository {
    func getStorageUsage() async throws -> CloudStorageUsage
    func connect() async throws -> CloudStorageAccount
    func restoreConnection() async throws -> CloudStorageAccount?
    func signOut() async throws
    func listFiles(parentFolderID: String?) async throws -> [CloudFile]
    func fileMetadata(id: String) async throws -> CloudFile
    func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile
    /// `progressHandler` получает долю завершённой загрузки (0...1)
    /// по мере передачи чанков.
    func uploadFile(
        at fileURL: URL,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile
    func deleteFile(id: String) async throws

    /// Скачивает файл по `id` в локальный `destination`.
    /// Для папок не поддерживается — используется при переносе
    /// файлов между облаками.
    func downloadFile(
        id: String,
        to destination: URL,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws

    /// Возвращает данные миниатюры файла (JPEG/PNG), если провайдер
    /// поддерживает превью. `nil` — превью нет или тип не поддерживается.
    func thumbnailData(for file: CloudFile) async throws -> Data?

    /// Возвращает прямую ссылку для потокового воспроизведения
    /// аудио/видео без предварительного скачивания.
    func streamDescriptor(
        for file: CloudFile
    ) async throws -> CloudMediaStream

    /// Загружает файл потоком чанков без промежуточного файла на диске.
    /// `readChunk` возвращает очередной чанк данных или nil в конце.
    /// `sizeBytes` нужен для Content-Range/сессий — при nil
    /// реализация может вернуть `.notImplemented`.
    func uploadStreamedFile(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64?,
        readChunk: () async throws -> Data?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile

    /// Создаёт (или восстанавливает по `resumeState`) сессию
    /// chunked-загрузки у провайдера. Возвращает сессию и её
    /// сериализуемое состояние для журнала передач (без токенов).
    /// `nil` — провайдер не поддерживает сессии или `resumeState`
    /// протух: вызывающий код должен повторить с `resumeState: nil`.
    func makeUploadSession(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64,
        resumeState: String?
    ) async throws -> (session: any TransferSession, state: String)?

    /// Возвращает потоковый источник байтов файла (Range-запросы
    /// с обновлением авторизации) для cloud-to-cloud передачи
    /// без промежуточного файла на диске. `nil` — не поддерживается.
    func makeChunkSource(for file: CloudFile) async throws -> (any ChunkSource)?

    /// Поиск файлов по имени по всему хранилищу.
    func searchFiles(query: String) async throws -> [CloudFile]

    /// Скачивает файл для локального просмотра и возвращает URL
    /// созданной копии. Провайдеры с «виртуальными» файлами
    /// (Google Docs/Sheets/Slides) экспортируют их в обычный
    /// формат с корректным расширением для QuickLook.
    /// `directory` — временная папка, созданная вызывающим кодом.
    func downloadPreviewFile(
        id: String,
        name: String,
        mimeType: String,
        into directory: URL
    ) async throws -> URL
}

extension CloudStorageRepository {
    /// Провайдеры без полноценного поиска возвращают пустой результат.
    func searchFiles(query: String) async throws -> [CloudFile] {
        []
    }

    /// Провайдеры без скачивания файлов сообщают `.notImplemented`.
    func downloadFile(
        id: String,
        to destination: URL,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws {
        throw CloudStorageError.notImplemented
    }

    /// Провайдеры без «виртуальных» файлов используют обычное скачивание.
    func downloadPreviewFile(
        id: String,
        name: String,
        mimeType: String,
        into directory: URL
    ) async throws -> URL {
        let destination = directory.appendingPathComponent(name)
        try await downloadFile(
            id: id,
            to: destination,
            progressHandler: nil
        )
        return destination
    }

    /// Провайдеры без миниатюр возвращают nil.
    func thumbnailData(for file: CloudFile) async throws -> Data? {
        nil
    }

    /// Провайдеры без прямых ссылок для стриминга.
    func streamDescriptor(
        for file: CloudFile
    ) async throws -> CloudMediaStream {
        throw CloudStorageError.notImplemented
    }

    /// Провайдеры без chunked-загрузки через TransferSession.
    func makeUploadSession(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64,
        resumeState: String?
    ) async throws -> (session: any TransferSession, state: String)? {
        nil
    }

    /// Провайдеры без потокового источника Range-скачивания.
    func makeChunkSource(for file: CloudFile) async throws -> (any ChunkSource)? {
        nil
    }

    /// Провайдеры без chunked-загрузки — вызывающий код
    /// должен откатиться на загрузку из файла.
    func uploadStreamedFile(
        name: String,
        mimeType: String,
        parentFolderID: String?,
        sizeBytes: Int64?,
        readChunk: () async throws -> Data?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        throw CloudStorageError.notImplemented
    }
}

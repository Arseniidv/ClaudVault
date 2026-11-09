import Foundation

/// Чанк данных для загрузки: `length` байт, лежащие в `fileURL`
/// начиная с `fileOffset`. `absoluteOffset` — позиция этих байт
/// в передаваемом файле целиком (нужна для Content-Range/курсоров).
/// `isTemporary` — файл создан источником чанков и должен быть
/// удалён после отправки; `false` — ссылка на исходник, не трогать.
public struct ChunkPayload: Equatable {
    public let fileURL: URL
    public let fileOffset: Int64
    public let absoluteOffset: Int64
    public let length: Int64
    public let isTemporary: Bool

    public init(
        fileURL: URL,
        fileOffset: Int64,
        absoluteOffset: Int64,
        length: Int64,
        isTemporary: Bool
    ) {
        self.fileURL = fileURL
        self.fileOffset = fileOffset
        self.absoluteOffset = absoluteOffset
        self.length = length
        self.isTemporary = isTemporary
    }
}

/// Источник байтов для chunked-передачи.
/// Реализации: локальный файл (`FileChunkSource`) и облако
/// (`HTTPRangeChunkSource` — Range-запросы с обновлением заголовков).
public protocol ChunkSource: Sendable {
    var totalSize: Int64 { get }

    /// Готовит следующий чанк, начиная с `offset` (байт в общем файле).
    /// `maxLength` — верхняя граница размера чанка; конкретная
    /// реализация может вернуть меньше (последний чанк).
    /// `nil` — смещение вышло за пределы файла.
    func chunk(at offset: Int64, maxLength: Int64) async throws -> ChunkPayload?

    /// Освобождает ресурсы чанка. Для временных файлов удаляет их,
    /// для файлов-источников — no-op.
    func discard(_ payload: ChunkPayload) async
}

/// Сессия загрузки у облачного провайдера (Google resumable,
/// Dropbox upload_session, OneDrive createUploadSession).
/// Контракт:
/// - `confirmedOffset` — сколько байт провайдер гарантированно принял.
/// - `send` может принять чанк частично: тогда `confirmedOffset`
///   отражает реально принятое, движок продолжит с этого места.
/// - `finish` вызывается только при `confirmedOffset == totalSize`.
public protocol TransferSession: Sendable {
    var confirmedOffset: Int64 { get }

    /// Сериализуемое состояние сессии для журнала передач
    /// (без токенов). Может меняться по ходу загрузки —
    /// журнал перечитывает его после каждого чанка.
    var stateValue: String { get }

    /// Отправить чанк. `payload.absoluteOffset` — позиция чанка
    /// в файле, `payload.length` — размер в байтах.
    /// Не должна читать файл целиком в память — только диапазон.
    func send(_ payload: ChunkPayload) async throws

    /// Завершить сессию и вернуть метаданные созданного файла.
    func finish() async throws -> CloudFile

    /// Бросить сессию без `finish` (для провайдеров без явного
    /// abort — просто забыть; сессии истекают сами).
    func cancel() async
}

/// Алгоритм хеша содержимого, который провайдер возвращает
/// в метаданных файла после загрузки.
public enum ContentHashAlgorithm: String, Sendable, Codable {
    /// SHA-1 hex — Google Drive `sha1Checksum`, OneDrive `file.hashes.sha1Hash`.
    case sha1
    /// MD5 hex — Google Drive `md5Checksum`.
    case md5
    /// Dropbox `content_hash` — SHA-256 по 4-МиБ блокам.
    case dropboxContent
}

/// Хеш содержимого в формате конкретного провайдера.
public struct ContentHash: Equatable, Sendable, Codable {
    public let algorithm: ContentHashAlgorithm
    public let value: String

    public init(algorithm: ContentHashAlgorithm, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

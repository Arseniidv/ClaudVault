import Foundation

/// Файл или папка в облачном хранилище.
/// Не зависит от SwiftUI и от конкретного SDK провайдера.
public struct CloudFile: Identifiable, Equatable, Codable {
    public enum Kind: Equatable {
        case folder
        case file
    }

    public let id: String
    public let name: String
    public let mimeType: String
    public let sizeBytes: Int64?
    public let modifiedAt: Date?
    /// Ссылка на миниатюру (Google Drive `thumbnailLink`).
    /// У Dropbox миниатюры отдаются через API и поля нет.
    public var thumbnailURL: String? = nil
    /// Локальный путь к закэшированной на диске миниатюре
    /// (папка Caches/CloudThumbnails).
    public var thumbnailPath: String? = nil
    /// Длительность аудио/видео в секундах, если провайдер её отдаёт.
    public var duration: TimeInterval? = nil
    /// Контрольные суммы содержимого, которые провайдер
    /// возвращает в метаданных (md5/sha1/content_hash).
    /// Используются для верификации передач.
    public var contentHashes: [ContentHash] = []

    public init(
        id: String,
        name: String,
        mimeType: String,
        sizeBytes: Int64?,
        modifiedAt: Date?,
        thumbnailURL: String? = nil,
        thumbnailPath: String? = nil,
        duration: TimeInterval? = nil,
        contentHashes: [ContentHash] = []
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.thumbnailURL = thumbnailURL
        self.thumbnailPath = thumbnailPath
        self.duration = duration
        self.contentHashes = contentHashes
    }

    public var kind: Kind {
        mimeType == CloudFile.folderMimeType ? .folder : .file
    }

    public var isFolder: Bool {
        kind == .folder
    }

    public static let folderMimeType = "application/vnd.google-apps.folder"
}

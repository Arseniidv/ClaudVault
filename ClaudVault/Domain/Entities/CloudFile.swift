import Foundation

/// Файл или папка в облачном хранилище.
/// Не зависит от SwiftUI и от конкретного SDK провайдера.
struct CloudFile: Identifiable, Equatable, Codable {
    enum Kind: Equatable {
        case folder
        case file
    }

    let id: String
    let name: String
    let mimeType: String
    let sizeBytes: Int64?
    let modifiedAt: Date?
    /// Ссылка на миниатюру (Google Drive `thumbnailLink`).
    /// У Dropbox миниатюры отдаются через API и поля нет.
    var thumbnailURL: String? = nil
    /// Локальный путь к закэшированной на диске миниатюре
    /// (папка Caches/CloudThumbnails).
    var thumbnailPath: String? = nil
    /// Длительность аудио/видео в секундах, если провайдер её отдаёт.
    var duration: TimeInterval? = nil
    /// Контрольные суммы содержимого, которые провайдер
    /// возвращает в метаданных (md5/sha1/content_hash).
    /// Используются для верификации передач.
    var contentHashes: [ContentHash] = []

    var kind: Kind {
        mimeType == CloudFile.folderMimeType ? .folder : .file
    }

    var isFolder: Bool {
        kind == .folder
    }

    static let folderMimeType = "application/vnd.google-apps.folder"
}

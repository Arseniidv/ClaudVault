import Foundation
import SwiftData

/// Кэш метаданных облачного файла между запусками.
/// Хранит последний известный листинг папки провайдера,
/// чтобы UI мог показать файлы до ответа сети.
@Model
final class CloudFileModel {

    /// `StorageProviderType.rawValue` (googleDrive, dropbox, oneDrive, …).
    var provider: String
    /// ID файла у провайдера (`CloudFile.id`).
    var remoteID: String
    /// ID родительской папки; пустая строка — корень.
    var parentFolderID: String

    var name: String
    var mimeType: String
    var sizeBytes: Int64?
    var modifiedAt: Date?
    var thumbnailURL: String?
    /// Путь к миниатюре в дисковом кэше (`Caches/CloudThumbnails`).
    var thumbnailPath: String?
    /// Длительность аудио/видео в секундах.
    var duration: Double?

    var updatedAt: Date

    init(
        provider: String,
        remoteID: String,
        parentFolderID: String,
        name: String,
        mimeType: String,
        sizeBytes: Int64? = nil,
        modifiedAt: Date? = nil,
        thumbnailURL: String? = nil,
        thumbnailPath: String? = nil,
        duration: Double? = nil,
        updatedAt: Date = .now
    ) {
        self.provider = provider
        self.remoteID = remoteID
        self.parentFolderID = parentFolderID
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.thumbnailURL = thumbnailURL
        self.thumbnailPath = thumbnailPath
        self.duration = duration
        self.updatedAt = updatedAt
    }

    func asCloudFile() -> CloudFile {
        CloudFile(
            id: remoteID,
            name: name,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            thumbnailURL: thumbnailURL,
            thumbnailPath: thumbnailPath,
            duration: duration
        )
    }

    static func make(
        from file: CloudFile,
        provider: String,
        parentFolderID: String
    ) -> CloudFileModel {
        CloudFileModel(
            provider: provider,
            remoteID: file.id,
            parentFolderID: parentFolderID,
            name: file.name,
            mimeType: file.mimeType,
            sizeBytes: file.sizeBytes,
            modifiedAt: file.modifiedAt,
            thumbnailURL: file.thumbnailURL,
            thumbnailPath: file.thumbnailPath,
            duration: file.duration
        )
    }
}

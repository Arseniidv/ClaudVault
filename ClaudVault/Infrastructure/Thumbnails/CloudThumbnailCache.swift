import Foundation
import ClaudVaultDomain

/// Дисковый кэш миниатюр облачных файлов.
///
/// Ключ — `"<provider>:<fileID>"`. Файлы лежат в
/// `Caches/CloudThumbnails/` и переиспользуются между запусками,
/// чтобы списки файлов не тянули тяжёлые исходники из облака.
/// Поверх этого кэша Kingfisher держит декодированные изображения.
nonisolated final class CloudThumbnailCache {

    static let shared = CloudThumbnailCache()

    private let directory: URL
    private let fileExtension = "jpg"

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.directory = caches
                .appendingPathComponent("CloudThumbnails", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    /// Детерминированный URL кэша для ключа — используется и как
    /// `CloudFile.thumbnailPath`, и как цель записи при загрузке.
    func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent(Self.safeFileName(for: key))
            .appendingPathExtension(fileExtension)
    }

    func data(forKey key: String) -> Data? {
        try? Data(contentsOf: fileURL(forKey: key))
    }

    func store(_ data: Data, forKey key: String) throws {
        try data.write(to: fileURL(forKey: key), options: .atomic)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func safeFileName(for key: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-._")
        )
        var result = ""
        for scalar in key.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }
        return result.isEmpty ? "thumb" : result
    }
}

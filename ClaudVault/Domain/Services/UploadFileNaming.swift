import Foundation

/// Помощник имени загружаемого файла. Провайдеры берут имя
/// облачного объекта из `lastPathComponent` URL, поэтому когда
/// пользователь задаёт своё имя (например, для скана
/// `scan_<UUID>.pdf`), подкладывается hard link или копия
/// во временной директории с нужным именем.
public enum UploadFileNaming {

    /// Возвращает URL, у которого `lastPathComponent` совпадает с
    /// заданным именем: исходный файл, либо hard link (fallback —
    /// копия) во временной директории. При любой ошибке возвращает
    /// исходный URL — загрузка под исходным именем всё ещё возможна.
    public static func url(for fileURL: URL, desiredName: String) -> URL {
        // "/" и ".." внутри имени не должны выводить hard link
        // за пределы временной директории.
        let safeName = SafeFileName.sanitized(desiredName) ?? ""
        guard !safeName.isEmpty, fileURL.lastPathComponent != safeName else {
            return fileURL
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cv_\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let destination = directory.appendingPathComponent(safeName)
            do {
                try FileManager.default.linkItem(at: fileURL, to: destination)
            } catch {
                try FileManager.default.copyItem(at: fileURL, to: destination)
            }
            return destination
        } catch {
            return fileURL
        }
    }
}

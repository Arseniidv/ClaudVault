import Foundation

/// Проверяет URL выделения: только file:// , существующие
/// объекты, доступные для чтения. Отфильтровывает «мусор»
/// (http-ссылки, удалённые файлы, пути без прав).
struct FileAccessValidator: Sendable {

    /// Возвращает валидные `SelectedFile`. Если ни один URL
    /// не прошёл проверку — пустой массив.
    func validate(_ urls: [URL], source: SelectionSource) -> FileSelection {
        let files = urls.compactMap { url -> SelectedFile? in
            guard url.isFileURL else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ) else { return nil }
            guard FileManager.default.isReadableFile(atPath: url.path)
            else { return nil }
            return SelectedFile(url: url, source: source)
        }
        return FileSelection(files: files, source: source)
    }
}

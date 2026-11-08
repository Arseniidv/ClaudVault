#if os(macOS)
import Cocoa

/// Читает файловые URL из буфера обмена. Используется только
/// как явный fallback — содержимое pasteboard не считается
/// «текущим выделением», там может быть текст или старые файлы.
struct ClipboardSelectionResolver: FileSelectionResolving {

    let source: SelectionSource = .clipboard

    func resolve() async -> FileSelection? {
        let pasteboard = NSPasteboard.general
        var urls: [URL] = []

        // Современный тип public.file-url / fileURL.
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            urls.append(contentsOf: fileURLs)
        }

        // Legacy NSFilenamesPboardType — массив POSIX-путей.
        if urls.isEmpty,
           let paths = pasteboard.propertyList(
               forType: NSPasteboard.PasteboardType(
                   "NSFilenamesPboardType"
               )
           ) as? [String] {
            urls.append(contentsOf: paths.map {
                URL(fileURLWithPath: $0)
            })
        }

        // Дедупликация с сохранением порядка.
        var seen = Set<URL>()
        urls = urls.filter { seen.insert($0.standardizedFileURL).inserted }

        let selection = FileAccessValidator().validate(urls, source: source)
        return selection.isEmpty ? nil : selection
    }
}
#endif

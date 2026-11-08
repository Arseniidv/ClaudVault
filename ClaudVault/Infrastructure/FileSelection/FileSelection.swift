import Foundation

/// Нормализованная модель выделения файлов для Radial Menu.
/// Резолверы только возвращают эту модель — действия с файлами
/// выполняют обработчики `FileActionHandling`, а не резолверы.
struct FileSelection: Equatable, Sendable {
    let files: [SelectedFile]
    let source: SelectionSource
    let timestamp: Date

    init(files: [SelectedFile], source: SelectionSource) {
        self.files = files
        self.source = source
        self.timestamp = .now
    }

    /// Удобный конструктор из «сырых» URL.
    init(urls: [URL], source: SelectionSource) {
        self.init(
            files: urls.map { SelectedFile(url: $0, source: source) },
            source: source
        )
    }

    var isEmpty: Bool { files.isEmpty }

    var urls: [URL] { files.map(\.url) }
}

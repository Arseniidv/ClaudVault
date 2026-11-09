import Foundation

/// Один файл, входящий в текущее выделение Radial Menu.
struct SelectedFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let source: SelectionSource

    init(url: URL, source: SelectionSource) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.source = source
    }
}

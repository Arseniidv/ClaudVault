import Foundation

/// Снимок доступности действия для текущего выделения.
struct FileActionDescriptor: Identifiable, Equatable, Sendable {
    let kind: FileActionKind
    let isEnabled: Bool
    /// Пояснение для disabled-состояния или дополнительный контекст.
    let statusText: String?

    var id: String { kind.rawValue }
}

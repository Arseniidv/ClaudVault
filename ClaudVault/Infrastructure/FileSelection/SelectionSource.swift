import Foundation

/// Источник, из которого Radial Menu получил выделенные файлы.
/// Приоритет источников определяется способом вызова меню,
/// а не этой очередью: контекстное меню Finder → finderSync,
/// Services → services, drop → dragAndDrop, хоткей → accessibility,
/// явный fallback → clipboard.
enum SelectionSource: String, Codable, Sendable {
    case finderSync
    case accessibility
    case services
    case dragAndDrop
    case clipboard
    /// Файлы, добавленные вручную через кнопку «+» в меню
    /// (NSOpenPanel внутри приложения).
    case filePicker

    var displayName: String {
        switch self {
        case .finderSync: return "Finder"
        case .accessibility: return "Текущее приложение"
        case .services: return "Служба macOS"
        case .dragAndDrop: return "Перетаскивание"
        case .clipboard: return "Буфер обмена"
        case .filePicker: return "Выбор файлов"
        }
    }
}

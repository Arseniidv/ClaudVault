import Foundation

/// Действия Radial Menu над выделенными файлами.
enum FileActionKind: String, CaseIterable, Identifiable, Sendable {
    case upload
    case download
    case transfer
    case share
    case information

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload: return "Загрузить"
        case .download: return "Скачать"
        case .transfer: return "Перенести"
        case .share: return "Поделиться"
        case .information: return "Информация"
        }
    }

    var systemImage: String {
        switch self {
        case .upload: return "icloud.and.arrow.up"
        case .download: return "icloud.and.arrow.down"
        case .transfer: return "arrow.left.arrow.right"
        case .share: return "square.and.arrow.up"
        case .information: return "info.circle"
        }
    }

    var detail: String {
        switch self {
        case .upload:
            return "Создать резервную копию в облаке"
        case .download:
            return "Скачать последнюю версию из облака"
        case .transfer:
            return "Скопировать версии в другое облако"
        case .share:
            return "Поделиться файлами через macOS"
        case .information:
            return "Свойства файла и статус копии"
        }
    }

    /// Действия, требующие выбора облака-провайдера
    /// перед выполнением.
    var requiresProvider: Bool {
        self == .upload || self == .transfer
    }
}


import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {

    case files
    case storages
    case synchronization
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .files:
            return "Файлы"
        case .storages:
            return "Хранилища"
        case .synchronization:
            return "Синхр."
        case .settings:
            return "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .files:
            return "arrow.up.folder"
        case .storages:
            return "cloud"
        case .synchronization:
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill"
        case .settings:
            return "slider.horizontal.2.arrow.trianglehead.counterclockwise"
        }
    }

    var selectedIcon: String {
        switch self {
        case .files:
            return "arrow.up.folder.fill"
        case .storages:
            return "cloud.fill"
        case .synchronization:
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill"
        case .settings:
            return "slider.horizontal.2.arrow.trianglehead.counterclockwise"
        }
    }
}


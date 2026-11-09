import SwiftUI

/// Единая палитра цветов облачных провайдеров.
///
/// Файл компилируется в оба таргета (приложение и CloudVaultWidgetExtension)
/// через synchronized group `Shared`, поэтому маппинг
/// `StorageProviderType.rawValue` → цвет доступен и в UI приложения,
/// и в расширении виджета без дублирования.
enum ProviderPalette {

    /// Фирменный цвет провайдера по его `rawValue`
    /// ("googleDrive", "dropbox", "oneDrive", "iCloud", ...).
    /// Неизвестные провайдеры получают нейтральный серый.
    static func color(for provider: String) -> Color {
        switch provider {
        case "googleDrive": return .green
        case "dropbox": return .purple
        case "oneDrive": return .blue
        case "iCloud": return .cyan
        case "local": return .gray
        case "unknown": return .secondary
        default: return .gray
        }
    }

    /// Цвет по человекочитаемому имени провайдера
    /// (`StorageProviderType.name`: "Google Drive", "Dropbox", ...).
    /// Используется там, где доступно только имя, а не rawValue —
    /// например, в Live Activity.
    static func color(forProviderName name: String) -> Color {
        switch name {
        case "Google Drive": return .green
        case "Dropbox": return .purple
        case "OneDrive": return .blue
        case "iCloud Drive": return .cyan
        case "Локальное хранилище": return .gray
        default: return .gray
        }
    }
}

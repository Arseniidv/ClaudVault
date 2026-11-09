import Foundation

/// Тип облачного провайдера. Вынесен из Presentation-слоя:
/// используется доменными сущностями и должен оставаться
/// платформенно-нейтральным (без SwiftUI-зависимостей).
public enum StorageProviderType: String, CaseIterable, Identifiable, Codable {
    case local
    case oneDrive
    case iCloud
    case googleDrive
    case dropbox
    case unknown

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .local: return "Локальное хранилище"
        case .oneDrive: return "OneDrive"
        case .iCloud: return "iCloud Drive"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        case .unknown: return "Неизвестный источник"
        }
    }

    /// SF Symbol-имя иконки провайдера. На Android маппится
    /// на Compose-эквивалент при портировании UI.
    public var icon: String {
        switch self {
        case .local: return "folder"
        case .oneDrive: return "cloud"
        case .iCloud: return "icloud"
        case .googleDrive: return "externaldrive"
        case .dropbox: return "shippingbox"
        case .unknown: return "questionmark.folder"
        }
    }
}

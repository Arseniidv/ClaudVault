
import SwiftUI

struct StorageProvider: Identifiable {
    let id: UUID
    let provider: StorageProviderType
    let name: String
    let email: String

    let usedStorage: Double
    let totalStorage: Double

    let syncTime: Date
    let usageAvailable: Bool

    init(
        id: UUID = UUID(),
        provider: StorageProviderType,
        name: String,
        email: String,
        usedStorage: Double,
        totalStorage: Double,
        syncTime: Date,
        usageAvailable: Bool = true
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.email = email
        self.usedStorage = usedStorage
        self.totalStorage = totalStorage
        self.syncTime = syncTime
        self.usageAvailable = usageAvailable
    }

    var icon: String {
        provider.icon
    }

    var tint: Color {
        provider.tint
    }

    var usagePercentage: Int {
        guard totalStorage > 0 else { return 0 }
        return Int((usedStorage / totalStorage) * 100)
    }

    var progress: Double {
        guard totalStorage > 0 else { return 0 }
        return min(max(usedStorage / totalStorage, 0), 1)
    }
}

enum StorageProviderType: String, CaseIterable, Identifiable, Codable {
    case local
    case oneDrive
    case iCloud
    case googleDrive
    case dropbox
    case unknown

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .local: return "Локальное хранилище"
        case .oneDrive: return "OneDrive"
        case .iCloud: return "iCloud Drive"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        case .unknown: return "Неизвестный источник"
        }
    }

    var icon: String {
        switch self {
        case .local: return "folder"
        case .oneDrive: return "cloud"
        case .iCloud: return "icloud"
        case .googleDrive: return "externaldrive"
        case .dropbox: return "shippingbox"
        case .unknown: return "questionmark.folder"
        }
    }

    var tint: Color {
        switch self {
        case .local: return .gray
        case .oneDrive: return .blue
        case .iCloud: return .cyan
        case .googleDrive: return .green
        case .dropbox: return .purple
        case .unknown: return .secondary
        }
    }
}

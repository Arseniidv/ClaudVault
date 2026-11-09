import Foundation
import ClaudVaultDomain

/// Модель данных виджета хранилищ.
///
/// Файл компилируется в оба таргета (приложение и CloudVaultWidgetExtension)
/// через synchronized group `Shared`. Приложение кодирует `MultiStorageWidgetData`
/// в JSON и пишет в App Group `UserDefaults`, виджет читает и декодирует.
///
/// ВАЖНО: при изменении полей менять файл нужно синхронно — типы должны
/// совпадать по Codable-ключам в обоих таргетах.

/// Один подключённый аккаунт облачного хранилища.
struct WidgetAccountInfo: Codable, Identifiable, Equatable {
    /// Значение `StorageProviderType.rawValue` ("googleDrive", "dropbox", "oneDrive").
    let provider: String
    let email: String
    let usedBytes: Int64
    let totalBytes: Int64

    var id: String { "\(provider)|\(email)" }

    /// Десятичные гигабайты — как в `CloudStorageUsage` основного приложения.
    var usedGB: Double { Double(usedBytes) / 1_000_000_000 }
    var totalGB: Double { Double(totalBytes) / 1_000_000_000 }
    var availableGB: Double { max(totalGB - usedGB, 0) }
    var usageFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

/// Ключи канала обмена через App Group.
/// Значения должны совпадать в приложении и расширении виджета.
enum WidgetStorage {
    static let appGroupID = "group.com.Arseniidv.ClaudVault"
    static let dataKey = "latest_storage_widget_data"
}

/// Снимок состояния всех облачных хранилищ для виджета.
struct MultiStorageWidgetData: Codable, Equatable {
    let lastUpdatedAt: Date
    let accounts: [WidgetAccountInfo]

    var totalUsedBytes: Int64 {
        accounts.reduce(0) { $0 + $1.usedBytes }
    }
    var totalMaxBytes: Int64 {
        accounts.reduce(0) { $0 + $1.totalBytes }
    }
    var totalUsedGB: Double {
        Double(totalUsedBytes) / 1_000_000_000
    }
    var totalMaxGB: Double {
        Double(totalMaxBytes) / 1_000_000_000
    }
    var totalAvailableGB: Double {
        max(totalMaxGB - totalUsedGB, 0)
    }
    var totalUsageFraction: Double {
        totalMaxBytes > 0 ? Double(totalUsedBytes) / Double(totalMaxBytes) : 0
    }
}

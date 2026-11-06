import Foundation

/// Облачный файл, который пользователь открывал в приложении.
/// Используется в разделе «Все файлы» для показа последних открытых
/// файлов с учётом фильтра по провайдеру.
struct OpenedCloudFile: Identifiable, Equatable, Codable {
    let provider: StorageProviderType
    let file: CloudFile
    let openedAt: Date

    var id: String {
        "\(provider.rawValue)|\(file.id)"
    }
}

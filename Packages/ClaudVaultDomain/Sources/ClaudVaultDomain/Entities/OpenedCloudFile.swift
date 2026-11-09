import Foundation

/// Облачный файл, который пользователь открывал в приложении.
/// Используется в разделе «Все файлы» для показа последних открытых
/// файлов с учётом фильтра по провайдеру.
public struct OpenedCloudFile: Identifiable, Equatable, Codable {
    public let provider: StorageProviderType
    public let file: CloudFile
    public let openedAt: Date

    public init(provider: StorageProviderType, file: CloudFile, openedAt: Date) {
        self.provider = provider
        self.file = file
        self.openedAt = openedAt
    }

    public var id: String {
        "\(provider.rawValue)|\(file.id)"
    }
}

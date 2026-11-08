import Foundation

/// Зависимости, доступные обработчикам действий.
/// Собирается один раз при старте приложения из AppDependencies.
@MainActor
struct FileActionContext {
    let backupMetadataRepository: BackupMetadataRepository
    /// Репозитории облаков, ключ — StorageProviderType.
    let repositories: [StorageProviderType: CloudStorageRepository]
    let createBackupWithUpload: CreateBackupWithUploadUseCase
    let transferBackupToProvider: TransferBackupToProviderUseCase
    /// Провайдеры, поддерживаемые приложением (gdrive/dropbox/oneDrive).
    let supportedProviders: [StorageProviderType]
    /// ~/Downloads — каталог для скачивания облачных версий.
    let downloadsDirectory: URL
}

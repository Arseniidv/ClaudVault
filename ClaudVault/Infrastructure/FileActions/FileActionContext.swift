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
    /// Общий VM хранилищ: обработчики обновляют списки
    /// файлов и кэш после операций, меняющих облака
    /// (загрузка, перенос). nil — в тестах и превью.
    let storagesViewModel: StoragesViewModel?
}

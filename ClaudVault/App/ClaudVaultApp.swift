import SwiftUI
import SwiftData
import FirebaseCore
import SwiftyDropbox
import ClaudVaultDomain

@main
@MainActor
struct ClaudVaultApp: App {

    private let dependencies: AppDependencies

    init() {
        // 1. Инициализируем Firebase
        FirebaseApp.configure()
        
        // 2. Инициализируем Dropbox App Key (совпадает с URL-схемой db-… в Info.plist).
        // Токены Dropbox храним в едином Keychain-сервисе приложения
        // через DropboxSecureStorageAccess вместо легаси-хранилища SDK.
        let dropboxStorage = DropboxSecureStorageAccess()
        #if os(iOS)
        DropboxClientsManager.setupWithAppKey(
            DropboxAuthManager.appKey,
            secureStorageAccess: dropboxStorage
        )
        #elseif os(macOS)
        DropboxClientsManager.setupWithAppKeyDesktop(
            DropboxAuthManager.appKey,
            secureStorageAccess: dropboxStorage
        )
        #endif

        do {
            // 3. Создаём SwiftData Container
            let container = try CloudVaultModelContainer.make(
                inMemory: false
            )

            // 4. Создаём репозитории
            let repository = BackupMetadataRepositoryImpl(
                modelContext: container.mainContext
            )

            let fileAccessRepository = LocalFileAccess()
            let fileHasher = SHA256FileHasher()

            // 5. Собираем зависимости приложения
            self.dependencies = AppDependencies(
                modelContainer: container,
                fetchBackupRecords: FetchBackupRecordsUseCase(
                    repository: repository
                ),
                deleteBackupRecord: DeleteBackupRecordUseCase(
                    repository: repository
                ),
                fileAccessRepository: fileAccessRepository,
                fileHasher: fileHasher,
                backupMetadataRepository: repository
            )

        } catch {
            fatalError(
                "Не удалось инициализировать зависимости: \(error)"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .modelContainer(dependencies.modelContainer)
                // Live Activities для фоновых загрузок:
                // монитор сверяет UploadSession с ActivityKit.
                .task {
                    LiveActivityManager.shared.startMonitoring(
                        fetchSessions: dependencies.fetchUpSession
                    )
                }
                // 6. Перехватываем URL от Dropbox при возврате в приложение после авторизации
                .onOpenURL { url in
                    dependencies.dropboxAuthManager.handleRedirectURL(url)
                }
        }
    }
}

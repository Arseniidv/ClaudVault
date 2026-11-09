import Foundation
import SwiftData

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let fetchBackupRecords: FetchBackupRecordsUseCase
    let fileAccessRepository: FileAccessRepository
    let fileHasher: FileHashing
    let backupMetadataRepository: BackupMetadataRepository
    let authRepository: AuthRepository
    let signInUseCase: SignInUseCase
    let signUpUseCase: SignUpUseCase
    let signOutUseCase: SignOutUseCase
    let resetPassword: ResetPasswordUseCase
    let getCurrentUserUseCase: GetCurrentUserUseCase
    let googleOAuthManager: GoogleOAuthManager
    let cloudStorageRepository: CloudStorageRepository
    let dropboxAuthManager: DropboxAuthManager
    let dropboxRepository: DropboxRepositoryImpl
    let oneDriveAuthManager: OneDriveAuthManager
    let oneDriveRepository: OneDriveRepositoryImpl
    let fileCache: CloudFileCacheRepository
    let biometricAuthService: BiometricAuthService
    let otpService: OTPService
    let passwordResetService: PasswordResetService
    let calculateStorageUsage: CalculateStorageUsageUseCase
    let transferJournal: TransferJournalImpl
    let transferEngine: TransferEngine

    // QR-перенос подключений между устройствами
    let qrVerificationService: QRVerificationService
    let cloudTokenStore: CloudTokenStore
    let deviceTransferCoordinator: DeviceTransferCoordinator

    /// Единый экземпляр AuthViewModel на процесс приложения.
    /// Firebase-сессия одна (`Auth.auth()` — синглтон), поэтому
    /// наблюдатель auth-состояния тоже должен быть один: RootView
    /// находится в WindowGroup и каждое новое окно macOS создаёт
    /// свой экземпляр view — без общего VM каждое окно поднимало
    /// бы собственный поток `authStateChanges` и дублировало
    /// `UserSessionCoordinator.handleUserChange`.
    let authViewModel: AuthViewModel
    /// Единый экземпляр StoragesViewModel: облачные SDK
    /// (GIDSignIn, SwiftyDropbox, OneDrive) — синглтоны, поэтому
    /// независимые VM в разных окнах могли бы показать
    /// противоречивое состояние подключений или запустить
    /// параллельные OAuth-флоу.
    let storagesViewModel: StoragesViewModel

    /// Единый аудиоплеер приложения (singleton): один AVPlayer
    /// на процесс, состояние транслируется в виджет,
    /// Live Activity и системные элементы управления.
    let audioPlayerService = AudioPlayerService.shared

    /// Роутер навигации по вкладкам приложения. Общий для
    /// Menu Bar и других внешних точек входа: запрос
    /// исполняет `RootView`, пока окно открыто или будет
    /// открыто через `openWindow`.
    let navigationRouter = AppNavigationRouter()

    /// Роутер действий создания бэкапа (deep link из виджета,
    /// Menu Bar). Общий экземпляр — раньше создавался
    /// локально в `RootView`, что не давало доступа
    /// из Menu Bar.
    let backupActionRouter = BackupActionRouter()

    /// Координирует изоляцию пользовательских данных при смене
    /// аккаунта CloudVault (экспорт сессий, сброс SDK, контекст).
    let userSessionCoordinator: UserSessionCoordinator

    let uploadSessionRepository: UploadSessionRepositoryImpl
    let updateProgress: UpdateUploadProgressUseCase
    let fetchUpSession: FetchUploadSessionsUseCase
    let saveSessionRepository: SaveUploadSessionUseCase

    let createBackupWithUpload: CreateBackupWithUploadUseCase
    let reparseAndBackup: ReparseAndBackupUseCase
    let deleteBackup: DeleteBackupUseCase
    let transferBackupToProvider: TransferBackupToProviderUseCase
    let renameBackup: RenameBackupUseCase
    let fetchBackupVersions: FetchBackupVersionsUseCase

    init(
        modelContainer: ModelContainer,
        fetchBackupRecords: FetchBackupRecordsUseCase,
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        backupMetadataRepository: BackupMetadataRepository
    ) {
        self.modelContainer = modelContainer
        self.fetchBackupRecords = fetchBackupRecords
        self.fileAccessRepository = fileAccessRepository
        self.fileHasher = fileHasher
        self.backupMetadataRepository = backupMetadataRepository
        self.calculateStorageUsage = CalculateStorageUsageUseCase(repository: backupMetadataRepository)

        // Upload sessions — отдельный фоновый ModelContext,
        // чтобы частые записи прогресса не грузили mainContext.
        let uploadRepository = UploadSessionRepositoryImpl(modelContainer: modelContainer)
        uploadRepository.onSessionChange = {
            Task { @MainActor in
                LiveActivityManager.shared.sessionDidChange()
            }
        }
        self.uploadSessionRepository = uploadRepository
        self.updateProgress = UpdateUploadProgressUseCase(repository: uploadRepository)
        self.fetchUpSession = FetchUploadSessionsUseCase(repository: uploadRepository)
        self.saveSessionRepository = SaveUploadSessionUseCase(repository: uploadRepository)

        // Auth
        let repository = FirebaseAuthRepository()
        self.authRepository = repository
        self.signInUseCase = SignInUseCase(repository: repository)
        self.signUpUseCase = SignUpUseCase(repository: repository)
        self.signOutUseCase = SignOutUseCase(repository: repository)
        self.resetPassword = ResetPasswordUseCase(repository: repository)
        self.getCurrentUserUseCase = GetCurrentUserUseCase(repository: repository)

        // Google Sign-In + Google Drive
        let oauthManager = GoogleOAuthManager()
        let cloudRepository = GoogleDriveRepositoryImpl(oauthManager: oauthManager)
        self.googleOAuthManager = oauthManager
        self.cloudStorageRepository = cloudRepository

        // Dropbox
        let dropboxAuth = DropboxAuthManager()
        self.dropboxAuthManager = dropboxAuth
        self.dropboxRepository = DropboxRepositoryImpl(authManager: dropboxAuth)

        // OneDrive (Microsoft Graph + OAuth PKCE)
        let oneDriveAuth = OneDriveAuthManager()
        self.oneDriveAuthManager = oneDriveAuth
        self.oneDriveRepository = OneDriveRepositoryImpl(authManager: oneDriveAuth)

        // Журнал и движок chunked-передач (upload + cloud-to-cloud).
        // Журнал — на отдельном фоновом ModelContext: updateProgress
        // пишется после каждого чанка и не должен грузить mainContext.
        self.transferJournal = TransferJournalImpl(
            modelContainer: modelContainer
        )
        self.transferEngine = TransferEngine(journal: transferJournal)

        // Кэш метаданных файлов между запусками
        self.fileCache = CloudFileCacheRepository(
            modelContext: modelContainer.mainContext
        )
        self.biometricAuthService = BiometricAuthService()
        self.otpService = OTPService()
        self.passwordResetService = PasswordResetService()

        // QR-перенос подключений между устройствами
        self.qrVerificationService = QRVerificationService()
        self.cloudTokenStore = CloudTokenStore()
        self.deviceTransferCoordinator = DeviceTransferCoordinator()

        // Изоляция данных между пользователями CloudVault
        self.userSessionCoordinator = UserSessionCoordinator(
            googleOAuthManager: oauthManager,
            dropboxAuthManager: dropboxAuth,
            transferEngine: transferEngine
        )

        // Единые VM на всё приложение — см. комментарии у свойств.
        // Создаются здесь, чтобы все окна WindowGroup делили
        // одну и ту же пользовательскую сессию и её наблюдателя.
        self.authViewModel = AuthViewModel(
            signInUseCase: signInUseCase,
            signUpUseCase: signUpUseCase,
            signOutUseCase: signOutUseCase,
            resetPasswordUseCase: resetPassword,
            getCurrentUserUseCase: getCurrentUserUseCase,
            authRepository: repository,
            otpService: otpService,
            passwordResetService: passwordResetService,
            sessionCoordinator: userSessionCoordinator
        )
        self.storagesViewModel = StoragesViewModel(
            repositories: [
                .googleDrive: cloudRepository,
                .dropbox: dropboxRepository,
                .oneDrive: oneDriveRepository
            ],
            biometricAuth: biometricAuthService,
            otpService: otpService,
            fileCache: fileCache,
            transferEngine: transferEngine
        )

        // QR-импорт подключений: после записи токенов в Keychain
        // переигрываем восстановление сессий провайдеров.
        deviceTransferCoordinator.onConnectionsRestored = {
            [storagesViewModel] in
            Task { await storagesViewModel.reconnectAfterTokenImport() }
        }

        // Backup use cases — все облака, чтобы бэкапы
        // можно было создавать и удалять в любом из них.
        let allRepositories: [StorageProviderType: CloudStorageRepository] = [
            .googleDrive: cloudRepository,
            .dropbox: dropboxRepository,
            .oneDrive: oneDriveRepository
        ]

        // Плеер резолвит облачные аудиоисточники через те же
        // репозитории: кэш → streamDescriptor → скачивание.
        audioPlayerService.resolver = AudioSourceResolver(
            repositories: allRepositories
        )
        self.createBackupWithUpload = CreateBackupWithUploadUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository,
            repositories: allRepositories,
            fileHasher: fileHasher,
            fileAccessRepository: fileAccessRepository,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: saveSessionRepository,
            updateUploadProgressUseCase: updateProgress
        )
        self.reparseAndBackup = ReparseAndBackupUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository,
            repositories: allRepositories,
            fileHasher: fileHasher,
            fileAccessRepository: fileAccessRepository,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: saveSessionRepository,
            updateUploadProgressUseCase: updateProgress
        )
        self.deleteBackup = DeleteBackupUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository,
            repositories: allRepositories
        )
        self.transferBackupToProvider = TransferBackupToProviderUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository,
            repositories: allRepositories,
            transferEngine: transferEngine
        )
        self.renameBackup = RenameBackupUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository,
            repositories: allRepositories
        )
        self.fetchBackupVersions = FetchBackupVersionsUseCase(
            repository: backupMetadataRepository
        )
    }

    func makeStorageOverviewViewModel() -> StorageOverviewViewModel {
        StorageOverviewViewModel(
            calculateStorageUsage: calculateStorageUsage
        )
        
    }

    /// Возвращает общий экземпляр — новый AuthViewModel
    /// на каждый экран/окно создавал бы дублирующие
    /// слушатели Firebase auth state.
    func makeAuthViewModel() -> AuthViewModel {
        authViewModel
    }

    /// Возвращает общий экземпляр — облачные подключения
    /// должны быть едиными для всего приложения.
    func makeStoragesViewModel() -> StoragesViewModel {
        storagesViewModel
    }

    func makeDeviceTransferViewModel() -> DeviceTransferViewModel {
        DeviceTransferViewModel(
            qrService: qrVerificationService,
            tokenStore: cloudTokenStore,
            biometricAuth: biometricAuthService,
            coordinator: deviceTransferCoordinator
        )
    }

    /// Единый экземпляр Menu Bar VM (только macOS): читает
    /// общие `storagesViewModel`/сессии, действия делегирует
    /// существующим use-case'ам.
    func makeMenuBarViewModel() -> MenuBarViewModel {
        MenuBarViewModel(dependencies: self)
    }

    func makeSynchronizationViewModel() -> SynchronizationViewModel {
        SynchronizationViewModel(
            fetchUploadSessions: fetchUpSession,
            updateUploadProgress: updateProgress,
            backupMetadataRepository: backupMetadataRepository,
            reparseAndBackup: reparseAndBackup
        )
    }
}

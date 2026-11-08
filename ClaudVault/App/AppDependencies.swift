import Foundation
import SwiftData

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let fetchBackupRecords: FetchBackupRecordsUseCase
    let deleteBackupRecord: DeleteBackupRecordUseCase
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

    let uploadSessionRepository: UploadSessionRepositoryImpl
    let updateProgress: UpdateUploadProgressUseCase
    let fetchUpSession: FetchUploadSessionsUseCase
    let saveSessionRepository: SaveUploadSessionUseCase

    let createBackupWithUpload: CreateBackupWithUploadUseCase
    let reparseAndBackup: ReparseAndBackupUseCase
    let deleteBackup: DeleteBackupUseCase
    let transferBackupToProvider: TransferBackupToProviderUseCase
    let fetchBackupVersions: FetchBackupVersionsUseCase

    init(
        modelContainer: ModelContainer,
        fetchBackupRecords: FetchBackupRecordsUseCase,
        deleteBackupRecord: DeleteBackupRecordUseCase,
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        backupMetadataRepository: BackupMetadataRepository
    ) {
        self.modelContainer = modelContainer
        self.fetchBackupRecords = fetchBackupRecords
        self.deleteBackupRecord = deleteBackupRecord
        self.fileAccessRepository = fileAccessRepository
        self.fileHasher = fileHasher
        self.backupMetadataRepository = backupMetadataRepository
        self.calculateStorageUsage = CalculateStorageUsageUseCase(repository: backupMetadataRepository)

        // Upload sessions
        // mainContext есть у ModelContainer, а не у ModelContext.
        let uploadRepository = UploadSessionRepositoryImpl(modelContext: modelContainer.mainContext)
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

        // Журнал и движок chunked-передач (upload + cloud-to-cloud)
        self.transferJournal = TransferJournalImpl(
            modelContext: modelContainer.mainContext
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

        // Backup use cases — все облака, чтобы бэкапы
        // можно было создавать и удалять в любом из них.
        let allRepositories: [StorageProviderType: CloudStorageRepository] = [
            .googleDrive: cloudRepository,
            .dropbox: dropboxRepository,
            .oneDrive: oneDriveRepository
        ]
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
        self.fetchBackupVersions = FetchBackupVersionsUseCase(
            repository: backupMetadataRepository
        )
    }

    func makeStorageOverviewViewModel() -> StorageOverviewViewModel {
        StorageOverviewViewModel(
            calculateStorageUsage: calculateStorageUsage
        )
        
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(
            signInUseCase: signInUseCase,
            signUpUseCase: signUpUseCase,
            signOutUseCase: signOutUseCase,
            resetPasswordUseCase: resetPassword,
            getCurrentUserUseCase: getCurrentUserUseCase,
            authRepository: authRepository,
            otpService: otpService,
            passwordResetService: passwordResetService
        )
    }

    func makeStoragesViewModel() -> StoragesViewModel {
        StoragesViewModel(
            repositories: [
                .googleDrive: cloudStorageRepository,
                .dropbox: dropboxRepository,
                .oneDrive: oneDriveRepository
            ],
            biometricAuth: biometricAuthService,
            otpService: otpService,
            fileCache: fileCache,
            transferEngine: transferEngine
        )
    }

    func makeDeviceTransferViewModel() -> DeviceTransferViewModel {
        DeviceTransferViewModel(
            qrService: qrVerificationService,
            tokenStore: cloudTokenStore,
            biometricAuth: biometricAuthService,
            coordinator: deviceTransferCoordinator
        )
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

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
    let calculateStorageUsage: CalculateStorageUsageUseCase

    let uploadSessionRepository: UploadSessionRepositoryImpl
    let updateProgress: UpdateUploadProgressUseCase
    let fetchUpSession: FetchUploadSessionsUseCase
    let saveSessionRepository: SaveUploadSessionUseCase

    let createBackupWithUpload: CreateBackupWithUploadUseCase
    let reparseAndBackup: ReparseAndBackupUseCase
    let deleteBackup: DeleteBackupUseCase
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

        // Кэш метаданных файлов между запусками
        self.fileCache = CloudFileCacheRepository(
            modelContext: modelContainer.mainContext
        )
        self.biometricAuthService = BiometricAuthService()
        self.otpService = OTPService()

        // Backup use cases
        self.createBackupWithUpload = CreateBackupWithUploadUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository,
            fileHasher: fileHasher,
            fileAccessRepository: fileAccessRepository,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: saveSessionRepository,
            updateUploadProgressUseCase: updateProgress
        )
        self.reparseAndBackup = ReparseAndBackupUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository,
            fileHasher: fileHasher,
            fileAccessRepository: fileAccessRepository,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: saveSessionRepository,
            updateUploadProgressUseCase: updateProgress
        )
        self.deleteBackup = DeleteBackupUseCase(
            backupRepository: backupMetadataRepository,
            cloudStorageRepository: cloudRepository
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
            otpService: otpService
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
            fileCache: fileCache
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

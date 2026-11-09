import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class StoragesViewModel {

    // MARK: - Provider State

    /// Результат глобального поиска: файл + провайдер, в котором он найден.
    struct CloudSearchResult: Identifiable, Equatable {
        let provider: StorageProviderType
        let file: CloudFile

        var id: String {
            "\(provider.rawValue)|\(file.id)"
        }
    }

    /// Аудиофайл, открытый в потоковом плеере.
    struct ActiveAudioStream: Identifiable, Equatable {
        let file: CloudFile
        let provider: StorageProviderType
        let stream: CloudMediaStream

        var id: String {
            "\(provider.rawValue)|\(file.id)"
        }
    }

    /// Состояние одного подключённого облачного провайдера.
    struct ProviderState {
        var account: CloudStorageAccount?
        var files: [CloudFile] = []
        var folderStack: [CloudFile] = []
        var storageUsage: CloudStorageUsage?
        var isBusy = false
        var errorMessage: String?
        var successMessage: String?
        var selectedFile: CloudFile?
        var didRestore = false

        var currentFolder: CloudFile? {
            folderStack.last
        }
    }

    /// Провайдеры, доступные для подключения.
    static let supportedProviders: [StorageProviderType] = [
        .googleDrive,
        .dropbox,
        .oneDrive
    ]

    // MARK: - Dependencies

    private let repositories: [StorageProviderType: CloudStorageRepository]
    private let biometricAuth: BiometricAuthService?
    private let otpService: OTPService?
    /// Кэш листингов папок в SwiftData. nil — кэш отключён (превью).
    private let fileCache: CloudFileCacheRepository?
    /// Движок chunked-передач с журналом. nil — только
    /// legacy-пути (превью, тесты).
    private let transferEngine: TransferEngine?
    private var states: [StorageProviderType: ProviderState] = [:]

    /// Задача текущего переноса — для отмены пользователем.
    private var transferTask: Task<Void, Never>?
    /// Задача текущей загрузки — для отмены пользователем.
    private var uploadTask: Task<Void, Never>?

    /// Провайдер, выбранный в шите «Добавить хранилище».
    var selectedProvider: StorageProviderType = .googleDrive

    /// Результаты глобального поиска по всем подключённым облакам.
    var cloudSearchResults: [CloudSearchResult] = []
    var isCloudSearchRunning = false

    /// Провайдер, для которого ожидается ввод OTP-кода перед подключением.
    /// Non-nil → UI должен показать шит ввода кода.
    var otpChallengeProvider: StorageProviderType?
    /// Идёт ли запрос OTP-кода на email.
    var isOTPRequestRunning = false

    /// Идёт ли перенос файла/папки между облаками.
    var isTransferRunning = false
    /// Прогресс текущего файла (0...1).
    var transferProgress: Double = 0
    /// Имя файла, который сейчас переносится.
    var transferFileName: String?

    /// Активный аудио-поток для плеера (nil — плеер закрыт).
    var activeAudioStream: ActiveAudioStream?

    /// Недавно открытые облачные файлы (персистятся между запусками).
    /// Используется в разделе «Все файлы» для фильтра по провайдеру.
    private(set) var recentlyOpenedFiles: [OpenedCloudFile] = []

    // MARK: - State (для совместимости с FilesView)

    /// Аккаунт Google Drive — используется в FilesView.
    var account: CloudStorageAccount? {
        states[.googleDrive]?.account
    }

    /// Использование хранилища Google Drive — используется в FilesView.
    var storageUsage: CloudStorageUsage? {
        states[.googleDrive]?.storageUsage
    }

    // MARK: - State (выбранный провайдер)

    var activeAccount: CloudStorageAccount? {
        states[selectedProvider]?.account
    }

    var activeFiles: [CloudFile] {
        states[selectedProvider]?.files ?? []
    }

    var activeFolderStack: [CloudFile] {
        states[selectedProvider]?.folderStack ?? []
    }

    var activeCurrentFolder: CloudFile? {
        states[selectedProvider]?.currentFolder
    }

    var activeIsBusy: Bool {
        states[selectedProvider]?.isBusy ?? false
    }

    var activeErrorMessage: String? {
        states[selectedProvider]?.errorMessage
    }

    var activeSuccessMessage: String? {
        states[selectedProvider]?.successMessage
    }

    var activeSelectedFile: CloudFile? {
        get { states[selectedProvider]?.selectedFile }
        set { states[selectedProvider]?.selectedFile = newValue }
    }

    // MARK: - Initialization

    init(
        repositories: [StorageProviderType: CloudStorageRepository],
        biometricAuth: BiometricAuthService? = nil,
        otpService: OTPService? = nil,
        fileCache: CloudFileCacheRepository? = nil,
        transferEngine: TransferEngine? = nil
    ) {
        self.repositories = repositories
        self.biometricAuth = biometricAuth
        self.otpService = otpService
        self.fileCache = fileCache
        self.transferEngine = transferEngine
        self.transferEngine?.onProgress = { [weak self] fraction in
            Task { @MainActor in
                self?.transferProgress = fraction
            }
        }
        loadRecentlyOpenedFiles()
        for kind in Self.supportedProviders where repositories[kind] != nil {
            states[kind] = ProviderState()
        }
    }

    /// Удобный init для одного провайдера (используется в превью).
    convenience init(
        repository: CloudStorageRepository,
        provider: StorageProviderType = .googleDrive
    ) {
        self.init(repositories: [provider: repository])
    }

    // MARK: - State Access

    func state(for provider: StorageProviderType) -> ProviderState {
        states[provider] ?? ProviderState()
    }

    var availableProviders: [StorageProviderType] {
        Self.supportedProviders.filter { repositories[$0] != nil }
    }

    /// Провайдеры с активным подключением (аккаунт восстановлен/подключён).
    var connectedProviders: [StorageProviderType] {
        availableProviders.filter { states[$0]?.account != nil }
    }

    /// Подключённые провайдеры с данными об использовании —
    /// используется на экранах «Хранилища» и «Все файлы».
    var connectedStorageProviders: [StorageProvider] {
        connectedProviders.compactMap { kind in
            guard let state = states[kind],
                  let account = state.account,
                  let usage = state.storageUsage else {
                return nil
            }

            return StorageProvider(
                provider: kind,
                name: kind.name,
                email: account.email,
                usedStorage: usage.usedGB,
                totalStorage: usage.totalGB,
                syncTime: Date()
            )
        }
    }

    // MARK: - Connection

    /// Восстанавливает сессии всех провайдеров без показа UI.
    func restoreConnection() async {
        for kind in Self.supportedProviders {
            await restoreConnection(for: kind)
        }
        // Публикуем итоговый снимок: если ни один аккаунт не подключён,
        // виджет получит пустой список и перестанет показывать старые данные.
        publishWidgetData()

        // Подхватываем незавершённые передачи из журнала —
        // только после восстановления сессий провайдеров,
        // иначе запросы упадут с unauthorized.
        if let transferEngine {
            let repos = repositories
            await transferEngine.resumePending { raw in
                guard let kind = StorageProviderType(rawValue: raw) else {
                    return nil
                }
                return repos[kind]
            }
        }
    }

    private func restoreConnection(for kind: StorageProviderType) async {
        guard let repository = repositories[kind] else { return }

        guard var state = states[kind], !state.didRestore else { return }
        state.didRestore = true
        states[kind] = state

        do {
            if let restored = try await repository.restoreConnection() {
                states[kind]?.account = restored
                await refreshFiles(for: kind)
                await loadStorageUsage(for: kind)
            }
        } catch let error as CloudStorageError {
            if case .notConfigured = error {
                states[kind]?.errorMessage = error.localizedDescription
            }
        } catch {
            states[kind]?.errorMessage = error.localizedDescription
        }
    }

    /// Подключение нового облака — критическая операция,
    /// требует биометрического подтверждения, если оно включено.
    func connect() async {
        let kind = selectedProvider

        guard await requireBiometricForSensitiveAction(for: kind) else { return }
        guard await requireOTPForConnect(for: kind) else { return }

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            let account = try await repository.connect()
            states[kind]?.account = account
            states[kind]?.folderStack = []
            let files = try await repository.listFiles(parentFolderID: nil)
            states[kind]?.files = files
            saveCachedFiles(files, for: kind, parentFolderID: nil)
        }

        await loadStorageUsage(for: kind)
    }

    func signOut() async {
        let kind = selectedProvider

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            try await repository.signOut()
            fileCache?.clear(provider: kind)
            states[kind]?.account = nil
            states[kind]?.files = []
            states[kind]?.folderStack = []
            states[kind]?.storageUsage = nil
        }

        publishWidgetData()
    }

    // MARK: - Files

    /// Ключ папки в кэше: корень — пустая строка.
    private func cacheKey(for parentFolderID: String?) -> String {
        parentFolderID ?? ""
    }

    /// Мгновенно подставляет закэшированный листинг папки,
    /// пока идёт сетевой запрос.
    private func applyCachedFiles(
        for kind: StorageProviderType,
        parentFolderID: String?
    ) {
        guard let fileCache else { return }
        states[kind]?.files = fileCache.fetch(
            provider: kind,
            parentFolderID: cacheKey(for: parentFolderID)
        )
    }

    private func saveCachedFiles(
        _ files: [CloudFile],
        for kind: StorageProviderType,
        parentFolderID: String?
    ) {
        fileCache?.save(
            files: files,
            provider: kind,
            parentFolderID: cacheKey(for: parentFolderID)
        )
    }

    func refreshFiles() async {
        await refreshFiles(for: selectedProvider)
    }

    private func refreshFiles(for kind: StorageProviderType) async {
        guard states[kind]?.account != nil else { return }

        let parentID = states[kind]?.currentFolder?.id
        applyCachedFiles(for: kind, parentFolderID: parentID)

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            let files = try await repository.listFiles(parentFolderID: parentID)
            states[kind]?.files = files
            saveCachedFiles(files, for: kind, parentFolderID: parentID)
        }
    }

    func openFolder(_ folder: CloudFile) async {
        let kind = selectedProvider

        guard folder.isFolder else { return }

        applyCachedFiles(for: kind, parentFolderID: folder.id)

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            states[kind]?.folderStack.append(folder)
            let files = try await repository.listFiles(parentFolderID: folder.id)
            states[kind]?.files = files
            saveCachedFiles(files, for: kind, parentFolderID: folder.id)
        }
    }

    func goBack() async {
        let kind = selectedProvider

        guard states[kind]?.folderStack.isEmpty == false else { return }

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            states[kind]?.folderStack.removeLast()
            let parentID = states[kind]?.currentFolder?.id
            applyCachedFiles(for: kind, parentFolderID: parentID)
            let files = try await repository.listFiles(parentFolderID: parentID)
            states[kind]?.files = files
            saveCachedFiles(files, for: kind, parentFolderID: parentID)
        }
    }

    func showMetadata(for file: CloudFile) async {
        let kind = selectedProvider

        guard !file.isFolder else { return }

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            let metadata = try await repository.fileMetadata(id: file.id)
            states[kind]?.selectedFile = metadata
            markFileOpened(metadata, provider: kind)
        }
    }

    // MARK: - Storage Usage

    /// Обновляет usage для всех подключённых провайдеров.
    func loadStorageUsage() async {
        for kind in availableProviders {
            await loadStorageUsage(for: kind)
        }
    }

    private func loadStorageUsage(for kind: StorageProviderType) async {
        guard states[kind]?.account != nil,
              let repository = repositories[kind] else { return }

        do {
            let usage = try await repository.getStorageUsage()
            states[kind]?.storageUsage = usage
        } catch {
            states[kind]?.storageUsage = nil
        }

        publishWidgetData()
    }

    // MARK: - Widget Snapshot

    /// Собирает актуальный снимок подключённых хранилищ и публикует
    /// его в App Group для виджета, затем перезагружает таймлайн.
    /// Вызывается после каждой загрузки usage, connect/signOut
    /// и завершения restoreConnection.
    private func publishWidgetData() {
        let accounts = Self.supportedProviders.compactMap { kind -> WidgetAccountInfo? in
            guard let state = states[kind],
                  let account = state.account else {
                return nil
            }
            return WidgetAccountInfo(
                provider: kind.rawValue,
                email: account.email,
                usedBytes: state.storageUsage?.usedBytes ?? 0,
                totalBytes: state.storageUsage?.totalBytes ?? 0
            )
        }
        WidgetDataPublisher.publish(accounts: accounts)
    }

    // MARK: - Create Folder

    func createFolder(named rawName: String) async {
        let kind = selectedProvider
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            states[kind]?.errorMessage = "Введите название папки."
            return
        }

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            _ = try await repository.createFolder(
                name: name,
                parentFolderID: states[kind]?.currentFolder?.id
            )

            states[kind]?.successMessage = "Папка «\(name)» создана."
            let parentID = states[kind]?.currentFolder?.id
            let files = try await repository.listFiles(parentFolderID: parentID)
            states[kind]?.files = files
        }
    }

    // MARK: - Upload

    /// MIME-тип файла по расширению (UTType → preferredMIMEType).
    private static func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension),
              let mimeType = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mimeType
    }

    func upload(fileURL: URL) async {
        let task = Task { await self.performUpload(fileURL: fileURL) }
        uploadTask = task
        await task.value
        uploadTask = nil
    }

    private func performUpload(fileURL: URL) async {
        let kind = selectedProvider

        // URL из fileImporter может быть security-scoped.
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        isTransferRunning = true
        transferFileName = fileURL.lastPathComponent
        transferProgress = 0
        defer {
            isTransferRunning = false
            transferProgress = 0
            transferFileName = nil
        }

        await perform(for: kind) { [self] in
            guard let repository = repositories[kind] else { return }
            let parentID = states[kind]?.currentFolder?.id

            var uploaded: CloudFile?
            // Сначала chunked-загрузка через TransferEngine:
            // resumable-сессия + журнал + возобновление.
            if let engine = transferEngine {
                do {
                    uploaded = try await engine.uploadFile(
                        fileURL: fileURL,
                        name: fileURL.lastPathComponent,
                        mimeType: Self.mimeType(for: fileURL),
                        targetProvider: kind.rawValue,
                        target: repository,
                        parentFolderID: parentID
                    )
                } catch CloudStorageError.notImplemented {
                    uploaded = nil
                }
            }
            if uploaded == nil {
                uploaded = try await repository.uploadFile(
                    at: fileURL,
                    parentFolderID: parentID,
                    progressHandler: nil
                )
            }

            guard let uploaded else { return }
            states[kind]?.successMessage = "Файл «\(uploaded.name)» загружен."
            let files = try await repository.listFiles(parentFolderID: parentID)
            states[kind]?.files = files
            await loadStorageUsage(for: kind)
        }
    }

    /// Пробрасывает ошибку fileImporter в состояние активного провайдера.
    func reportFilePickerError(_ error: Error) {
        states[selectedProvider]?.errorMessage = error.localizedDescription
    }

    // MARK: - Global Search

    /// Ищет файлы одновременно во всех подключённых облачных хранилищах.
    /// Ошибки отдельного провайдера не прерывают остальные запросы.
    func searchCloudFiles(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cloudSearchResults = []
            return
        }

        isCloudSearchRunning = true
        defer { isCloudSearchRunning = false }

        let targets = connectedProviders.compactMap { kind in
            repositories[kind].map { (kind, $0) }
        }

        var results: [CloudSearchResult] = []

        await withTaskGroup(of: [CloudSearchResult].self) { group in
            for (kind, repository) in targets {
                group.addTask {
                    guard let files = try? await repository.searchFiles(query: trimmed) else {
                        return []
                    }
                    return files.map { CloudSearchResult(provider: kind, file: $0) }
                }
            }

            for await batch in group {
                results += batch
            }
        }

        cloudSearchResults = results.sorted {
            $0.file.name.localizedCaseInsensitiveCompare($1.file.name)
                == .orderedAscending
        }
    }

    func clearCloudSearch() {
        cloudSearchResults = []
        isCloudSearchRunning = false
    }

    // MARK: - Recently Opened Files

    private static let recentlyOpenedKey = "recentlyOpenedCloudFiles.v1"
    private static let recentlyOpenedLimit = 30

    /// Открытые пользователем облачные файлы с учётом фильтра
    /// по провайдеру. nil — все провайдеры.
    /// Сортировка: сначала самые недавно открытые.
    func openedFiles(for provider: StorageProviderType?) -> [OpenedCloudFile] {
        recentlyOpenedFiles
            .filter { provider == nil || $0.provider == provider }
            .sorted { $0.openedAt > $1.openedAt }
    }

    /// Запоминает открытие облачного файла и сохраняет историю.
    func markFileOpened(_ file: CloudFile, provider: StorageProviderType) {
        guard !file.isFolder else { return }

        recentlyOpenedFiles.removeAll {
            $0.provider == provider && $0.file.id == file.id
        }
        recentlyOpenedFiles.insert(
            OpenedCloudFile(provider: provider, file: file, openedAt: Date()),
            at: 0
        )
        if recentlyOpenedFiles.count > Self.recentlyOpenedLimit {
            recentlyOpenedFiles = Array(
                recentlyOpenedFiles.prefix(Self.recentlyOpenedLimit)
            )
        }
        persistRecentlyOpenedFiles()
    }

    private func loadRecentlyOpenedFiles() {
        guard let data = UserDefaults.standard.data(
            forKey: Self.recentlyOpenedKey
        ),
        let decoded = try? JSONDecoder().decode(
            [OpenedCloudFile].self,
            from: data
        ) else {
            recentlyOpenedFiles = []
            return
        }
        recentlyOpenedFiles = decoded
    }

    private func persistRecentlyOpenedFiles() {
        guard let data = try? JSONEncoder().encode(recentlyOpenedFiles) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.recentlyOpenedKey)
    }

    // MARK: - Helpers

    /// Биометрическое подтверждение критических операций
    /// (подключение нового облака). Если биометрия выключена
    /// в настройках или недоступна на устройстве — пропускает.
    private func requireBiometricForSensitiveAction(
        for kind: StorageProviderType
    ) async -> Bool {
        guard let biometricAuth,
              UserDefaults.standard.bool(forKey: "biometricLockEnabled"),
              biometricAuth.isAvailable() else {
            return true
        }

        do {
            _ = try await biometricAuth.authenticateDeviceOwner(
                reason: "Подтвердите подключение облака"
            )
            return true
        } catch {
            states[kind]?.errorMessage = error.localizedDescription
            return false
        }
    }

    /// 2FA-гейт: если включена двухфакторная защита и доверенное окно
    /// истекло — запрашивает OTP-код и просит UI показать ввод.
    /// Возвращает false, когда подключение нужно отложить до ввода кода.
    private func requireOTPForConnect(
        for kind: StorageProviderType
    ) async -> Bool {
        guard let otpService,
              otpService.isTwoFactorEnabled,
              !otpService.isRecentlyVerified else {
            return true
        }

        states[kind]?.errorMessage = nil
        otpChallengeProvider = kind
        isOTPRequestRunning = true
        defer { isOTPRequestRunning = false }

        do {
            try await otpService.requestCode()
            return false
        } catch {
            otpChallengeProvider = nil
            states[kind]?.errorMessage = error.localizedDescription
            return false
        }
    }

    /// Вызывается UI после ввода кода в OTP-шите.
    /// При успехе продолжает отложенное подключение.
    func submitOTPCodeForPendingConnect(_ code: String) async {
        guard let kind = otpChallengeProvider,
              let otpService else { return }

        let trimmed = code.trimmingCharacters(in: .whitespaces)
        do {
            try await otpService.verifyCode(trimmed)
            otpChallengeProvider = nil
            await connect()
        } catch {
            states[kind]?.errorMessage = error.localizedDescription
        }
    }

    /// Повторная отправка OTP-кода для отложенного подключения.
    func resendOTPCode() async {
        guard let kind = otpChallengeProvider,
              let otpService else { return }
        isOTPRequestRunning = true
        defer { isOTPRequestRunning = false }
        do {
            try await otpService.requestCode()
            states[kind]?.successMessage = "Код отправлен повторно."
        } catch {
            states[kind]?.errorMessage = error.localizedDescription
        }
    }

    func cancelOTPChallenge() {
        otpChallengeProvider = nil
    }

    // MARK: - Thumbnails & Media Streaming

    /// Провайдер миниатюры для файла активного провайдера.
    /// Дисковый кэш `CloudThumbnailCache` отдаёт уже скачанные
    /// превью без обращения к облаку, Kingfisher кэширует
    /// декодированные изображения поверх.
    func thumbnailProvider(for file: CloudFile) -> CloudThumbnailProvider? {
        let kind = selectedProvider
        guard let repository = repositories[kind], !file.isFolder else {
            return nil
        }

        let cacheKey = "\(kind.rawValue):\(file.id)"
        let cacheURL = CloudThumbnailCache.shared.fileURL(forKey: cacheKey)

        var file = file
        file.thumbnailPath = cacheURL.path
        let fileForLoad = file

        return CloudThumbnailProvider(cacheKey: cacheKey) {
            if let cached = CloudThumbnailCache.shared.data(forKey: cacheKey) {
                return cached
            }
            guard let data = try await repository.thumbnailData(for: fileForLoad),
                  !data.isEmpty else {
                return nil
            }
            try? CloudThumbnailCache.shared.store(data, forKey: cacheKey)
            return data
        }
    }

    /// Загружает содержимое папки указанного провайдера без изменения
    /// общего состояния файлового менеджера — используется браузером
    /// папок из результатов поиска во вкладке «Файлы».
    func listCloudFiles(
        provider: StorageProviderType,
        parentFolderID: String?
    ) async throws -> [CloudFile] {
        guard let repository = repositories[provider] else {
            throw CloudStorageError.notConnected
        }
        return try await repository.listFiles(parentFolderID: parentFolderID)
    }

    /// Скачивает файл из указанного провайдера во временную папку
    /// для встроенного просмотра (QuickLook).
    /// Возвращает URL локальной копии — вызывающий код отвечает за удаление.
    func downloadForPreview(
        _ file: CloudFile,
        provider: StorageProviderType
    ) async throws -> URL {
        guard let repository = repositories[provider] else {
            throw CloudStorageError.notConnected
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        let fileURL = try await repository.downloadPreviewFile(
            id: file.id,
            name: file.name,
            mimeType: file.mimeType,
            into: tempDir
        )
        markFileOpened(file, provider: provider)
        return fileURL
    }

    /// Аудиофайл по mimeType или расширению.
    func isAudioFile(_ file: CloudFile) -> Bool {
        if file.mimeType.hasPrefix("audio/") { return true }
        let ext = file.name.split(separator: ".").last?
            .lowercased() ?? ""
        return ["mp3", "m4a", "aac", "wav", "ogg", "oga", "opus", "flac"]
            .contains(ext)
    }

    /// Открывает аудиофайл в потоковом плеере (без скачивания).
    func playAudio(_ file: CloudFile) async {
        let kind = selectedProvider
        guard let repository = repositories[kind] else { return }

        do {
            let stream = try await repository.streamDescriptor(for: file)
            activeAudioStream = ActiveAudioStream(
                file: file,
                provider: kind,
                stream: stream
            )
            markFileOpened(file, provider: kind)
        } catch let error as CloudStorageError {
            states[kind]?.errorMessage = error.localizedDescription
        } catch {
            states[kind]?.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Cloud-to-Cloud Transfer

    /// Копирует или перемещает файл/папку из одного подключённого
    /// облака в другое. Для папок перенос рекурсивный.
    /// Цель — текущая открытая папка целевого провайдера
    /// (или корень, если там ничего не открыто).
    func transferItem(
        _ file: CloudFile,
        from source: StorageProviderType,
        to target: StorageProviderType,
        move: Bool
    ) async {
        let task = Task {
            await self.performTransferItem(
                file,
                from: source,
                to: target,
                move: move
            )
        }
        transferTask = task
        await task.value
        transferTask = nil
    }

    /// Отменяет текущий перенос/загрузку: задача останавливается
    /// через `Task.checkCancellation` в цикле движка, запись
    /// журнала помечается `.cancelled`.
    func cancelTransfer() {
        transferTask?.cancel()
        uploadTask?.cancel()
        Task { await transferEngine?.cancelActive() }
    }

    private func performTransferItem(
        _ file: CloudFile,
        from source: StorageProviderType,
        to target: StorageProviderType,
        move: Bool
    ) async {
        guard source != target,
              let sourceRepo = repositories[source],
              let targetRepo = repositories[target],
              states[source]?.account != nil,
              states[target]?.account != nil,
              !isTransferRunning else {
            return
        }

        let targetParentID = states[target]?.currentFolder?.id
        isTransferRunning = true
        transferProgress = 0
        transferFileName = file.name
        states[source]?.errorMessage = nil
        states[source]?.successMessage = nil
        defer {
            isTransferRunning = false
            transferProgress = 0
            transferFileName = nil
        }

        do {
            try await transferItemRecursive(
                file,
                sourceRepo: sourceRepo,
                targetRepo: targetRepo,
                source: source,
                target: target,
                move: move,
                targetParentID: targetParentID
            )
            states[source]?.successMessage = move
                ? "«\(file.name)» перемещён в \(target.name)."
                : "«\(file.name)» скопирован в \(target.name)."
        } catch let error as CloudStorageError {
            if case .cancelled = error { return }
            states[source]?.errorMessage = error.localizedDescription
        } catch {
            states[source]?.errorMessage = error.localizedDescription
        }

        await refreshFiles(for: source)
        await refreshFiles(for: target)
        await loadStorageUsage(for: source)
        await loadStorageUsage(for: target)
    }

    private func transferItemRecursive(
        _ file: CloudFile,
        sourceRepo: CloudStorageRepository,
        targetRepo: CloudStorageRepository,
        source: StorageProviderType,
        target: StorageProviderType,
        move: Bool,
        targetParentID: String?
    ) async throws {
        if file.isFolder {
            let created = try await targetRepo.createFolder(
                name: file.name,
                parentFolderID: targetParentID
            )

            let children = try await sourceRepo.listFiles(parentFolderID: file.id)
            for child in children {
                try await transferItemRecursive(
                    child,
                    sourceRepo: sourceRepo,
                    targetRepo: targetRepo,
                    source: source,
                    target: target,
                    move: move,
                    targetParentID: created.id
                )
            }

            if move {
                try await sourceRepo.deleteFile(id: file.id)
            }
            return
        }

        // Файл: основной путь — TransferEngine (Range-скачивание
        // в temp-файлы → resumable-сессия приёмника → журнал,
        // верификация размера и безопасный move). Если провайдер
        // не поддерживает сессии — legacy-путь через temp-файл.
        transferFileName = file.name
        transferProgress = 0

        if let engine = transferEngine {
            do {
                _ = try await engine.transferFile(
                    file,
                    from: source.rawValue,
                    source: sourceRepo,
                    to: target.rawValue,
                    target: targetRepo,
                    targetParentID: targetParentID,
                    move: move
                )
                return
            } catch CloudStorageError.notImplemented {
                // Нет makeChunkSource/makeUploadSession —
                // переходим на fallback ниже.
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let localURL = tempDir.appendingPathComponent(file.name)

        try await sourceRepo.downloadFile(id: file.id, to: localURL, progressHandler: nil)
        transferProgress = 0

        let uploaded = try await targetRepo.uploadFile(
            at: localURL,
            parentFolderID: targetParentID
        ) { [weak self] fraction in
            guard let self else { return }
            Task { @MainActor in
                self.transferProgress = fraction
            }
        }

        if move {
            // Источник удаляем только после проверки размера
            // у приёмника.
            let meta = try await targetRepo.fileMetadata(id: uploaded.id)
            guard meta.sizeBytes == file.sizeBytes else {
                throw CloudStorageError.operationFailed(
                    "Размер загруженного файла не совпадает с источником."
                )
            }
            try await sourceRepo.deleteFile(id: file.id)
        }
    }

    private func perform(
        for kind: StorageProviderType,
        _ operation: @escaping () async throws -> Void
    ) async {
        guard repositories[kind] != nil else { return }
        guard states[kind]?.isBusy != true else { return }

        states[kind]?.isBusy = true
        states[kind]?.errorMessage = nil
        states[kind]?.successMessage = nil

        defer { states[kind]?.isBusy = false }

        do {
            try await operation()
        } catch let error as CloudStorageError {
            if case .cancelled = error {
                // Пользователь сам закрыл окно авторизации.
                return
            }

            if case .notConnected = error {
                states[kind]?.account = nil
                states[kind]?.files = []
                states[kind]?.folderStack = []
            }

            states[kind]?.errorMessage = error.localizedDescription
        } catch {
            states[kind]?.errorMessage = error.localizedDescription
        }
    }
}

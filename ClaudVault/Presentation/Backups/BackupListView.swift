import SwiftUI
import SwiftData

@MainActor
struct BackupListView: View {
    // MARK: - Properties
    @State private var viewModel: BackupListViewModel
    @State private var storagesViewModel: StoragesViewModel
    @State private var searchText = ""
    @State private var selectedSort: RecentFilesView.SortOption = .latest
    @State private var selectedProvider: StorageProviderType? = nil
    @State private var selectedRecord: BackupRecord?
    @State private var previewFileURL: URL?
    @State private var isDownloadingPreview = false

    private let fileAccessRepository: FileAccessRepository
    private let fileHasher: FileHashing
    private let backupMetadataRepository: BackupMetadataRepository
    private let createBackupWithUpload: CreateBackupWithUploadUseCase
    private let deleteBackupUseCase: DeleteBackupUseCase
    private let reparseAndBackupUseCase: ReparseAndBackupUseCase
    private let transferBackupToProvider: TransferBackupToProviderUseCase?
    private let fetchBackupVersions: FetchBackupVersionsUseCase
    /// Роутер deep link'ов виджета (`claudvault://backup/new?mode=…`).
    private let actionRouter: BackupActionRouter?

    @State private var isCreateBackupPresented = false
    @State private var isScannerPresented = false
    /// URL PDF, сгенерированного сканером документов. Передаётся
    /// в `CreateBackupView` как предвыбранный файл.
    @State private var pendingScannedPDFURL: URL?
    /// Обёртка для `sheet(item:)`: гарантирует, что `CreateBackupView`
    /// строится с уже готовым URL скана.
    @State private var scannedDocument: ScannedDocument?
    /// Флаг авто-открытия fileImporter — взводится deep link'ом
    /// `?mode=file`, sheet читает его один раз.
    @State private var pendingAutoOpenImporter = false

    // MARK: - Initializer
    init(
        fetchBackupRecords: FetchBackupRecordsUseCase,
        fileAccessRepository: FileAccessRepository,
        fileHasher: FileHashing,
        backupMetadataRepository: BackupMetadataRepository,
        storagesViewModel: StoragesViewModel,
        createBackupWithUpload: CreateBackupWithUploadUseCase,
        deleteBackupUseCase: DeleteBackupUseCase,
        reparseAndBackupUseCase: ReparseAndBackupUseCase,
        transferBackupToProvider: TransferBackupToProviderUseCase? = nil,
        fetchBackupVersions: FetchBackupVersionsUseCase,
        actionRouter: BackupActionRouter? = nil
    ) {
        let listViewModel = BackupListViewModel(
            fetchBackupRecords: fetchBackupRecords,
            deleteBackupUseCase: deleteBackupUseCase,
            calculateStorageUsage: CalculateStorageUsageUseCase(
                repository: backupMetadataRepository
            ),
            backupMetadataRepository: backupMetadataRepository
        )
        _viewModel = State(initialValue: listViewModel)
        _storagesViewModel = State(wrappedValue: storagesViewModel)
        self.fileAccessRepository = fileAccessRepository
        self.fileHasher = fileHasher
        self.backupMetadataRepository = backupMetadataRepository
        self.createBackupWithUpload = createBackupWithUpload
        self.deleteBackupUseCase = deleteBackupUseCase
        self.reparseAndBackupUseCase = reparseAndBackupUseCase
        self.transferBackupToProvider = transferBackupToProvider
        self.fetchBackupVersions = fetchBackupVersions
        self.actionRouter = actionRouter
    }

    // MARK: - Computed Properties

    /// Подключённые облачные провайдеры с реальным usage — как на экране «Хранилища».
    private var providers: [StorageProvider] {
        storagesViewModel.connectedStorageProviders
    }

    /// Провайдеры, попадающие под текущий фильтр чипсов.
    private var visibleProviders: [StorageProvider] {
        providers.filter {
            selectedProvider == nil || $0.provider == selectedProvider
        }
    }

    /// Суммарно занятое место по видимым провайдерам, GB.
    private var usedStorage: Double {
        visibleProviders.reduce(0) { $0 + $1.usedStorage }
    }

    /// Суммарная ёмкость по видимым провайдерам, GB.
    private var totalStorage: Double {
        visibleProviders.reduce(0) { $0 + $1.totalStorage }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color(red: 0.035, green: 0.047, blue: 0.075)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        FilesHeaderView(selectedSort: $selectedSort)

                        SearchSectionView(searchText: $searchText)

                        FilterSelectorView(
                            selectedProvider: $selectedProvider,
                            providers: storagesViewModel.connectedProviders
                        )

                        if !searchText.isEmpty {
                            cloudSearchSection
                        }

                        StorageOverviewView(
                            providers: providers,
                            usedStorage: usedStorage,
                            totalStorage: totalStorage,
                            backupVersionsBytes: viewModel.usedStorageBytes,
                            localFilesBytes: viewModel.localFilesBytes,
                            localFilesCount: viewModel.localFilesCount
                        )

                        recentlyOpenedSection

                        RecentFilesView(
                            records: viewModel.records,
                            searchText: searchText,
                            selectedSort: selectedSort,
                            providerFilter: selectedProvider,
                            onFileTap: { record in
                                selectedRecord = record
                            },
                            onDelete: { record in
                                Task {
                                    await viewModel.deleteRecord(record: record)
                                }
                            }
                        )

                        FooterSectionView(
                            connectedClouds: providers.count,
                            totalFiles: viewModel.records.count
                        )
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.screenVertical)
                }

                AddBackupButton(
                    action: { isCreateBackupPresented = true },
                    scanAction: { isScannerPresented = true }
                )
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .task {
                viewModel.onDataChanged = { [storagesViewModel, viewModel] in
                    viewModel.loadRecords()
                    Task { await storagesViewModel.loadStorageUsage() }
                }
                viewModel.loadRecords()
                Task { await storagesViewModel.loadStorageUsage() }
                consumePendingBackupRequest()
            }
            // Deep link из виджета может прийти и после появления view.
            .onChange(of: actionRouter?.pendingRequest) { _, _ in
                consumePendingBackupRequest()
            }
            // Глобальный поиск по всем подключённым облакам с дебаунсом.
            .task(id: searchText) {
                let query = searchText
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    storagesViewModel.clearCloudSearch()
                    return
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await storagesViewModel.searchCloudFiles(query: query)
            }
            .navigationDestination(for: CloudFolderRoute.self) { route in
                CloudFolderBrowserView(
                    provider: route.provider,
                    route: route,
                    storagesViewModel: storagesViewModel
                )
            }
            #if os(iOS)
            .sheet(isPresented: $isScannerPresented, onDismiss: {
                // После закрытия сканера открываем создание бэкапа
                // с готовым PDF-сканом.
                if let url = pendingScannedPDFURL {
                    pendingScannedPDFURL = nil
                    scannedDocument = ScannedDocument(fileURL: url)
                }
            }) {
                DocumentScannerView(
                    onScanComplete: { url in
                        pendingScannedPDFURL = url
                        isScannerPresented = false
                    },
                    onCancel: {
                        isScannerPresented = false
                    },
                    onError: { error in
                        viewModel.errorMessage = error.localizedDescription
                        isScannerPresented = false
                    }
                )
            }
            #endif
            .sheet(isPresented: $isCreateBackupPresented, onDismiss: {
                pendingAutoOpenImporter = false
            }) {
                createBackupView(
                    initialFileURL: nil,
                    autoOpenImporter: pendingAutoOpenImporter
                )
            }
            .sheet(item: $scannedDocument) { document in
                createBackupView(initialFileURL: document.fileURL)
            }
            .sheet(item: $selectedRecord) { record in
                BackupRecordDetailView(
                    viewModel: makeDetailViewModel(for: record)
                )
            }
            .sheet(isPresented: Binding(
                get: { previewFileURL != nil },
                set: { isPresented in
                    if !isPresented {
                        // Удаляем временную копию после закрытия просмотра.
                        if let url = previewFileURL {
                            try? FileManager.default.removeItem(
                                at: url.deletingLastPathComponent()
                            )
                        }
                        previewFileURL = nil
                    }
                }
            )) {
                if let url = previewFileURL {
                    QuickLookPreview(url: url)
                }
            }
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    /// Выполняет запрос на создание бэкапа, пришедший из виджета
    /// через deep link. Запрос снимается только здесь — если view
    /// ещё не создан (пользователь не авторизован), он дождётся
    /// появления этого экрана после входа.
    private func consumePendingBackupRequest() {
        guard let request = actionRouter?.pendingRequest else { return }
        actionRouter?.pendingRequest = nil

        switch request {
        case .pickFile:
            pendingAutoOpenImporter = true
            isCreateBackupPresented = true
        case .scanDocument:
            isScannerPresented = true
        }
    }

    /// Идентифицируемая обёртка для PDF из сканера — нужна для
    /// `sheet(item:)`, чтобы content-геттер всегда получал актуальный URL.
    private struct ScannedDocument: Identifiable {
        let id = UUID()
        let fileURL: URL
    }

    @ViewBuilder
    private func createBackupView(
        initialFileURL: URL?,
        autoOpenImporter: Bool = false
    ) -> some View {
        CreateBackupView(
            fileAccessRepository: fileAccessRepository,
            fileHasher: fileHasher,
            createBackupWithUpload: createBackupWithUpload,
            availableProviders: storagesViewModel.connectedProviders,
            initialFileURL: initialFileURL,
            autoOpenImporter: autoOpenImporter,
            onCreated: {
                viewModel.loadRecords()
                Task { await storagesViewModel.loadStorageUsage() }
            }
        )
    }

    private func makeDetailViewModel(for record: BackupRecord) -> BackupVersionsViewModel {
        let detailViewModel = BackupVersionsViewModel(
            record: record,
            fetchBackupVersions: fetchBackupVersions,
            deleteBackupUseCase: deleteBackupUseCase,
            reparseAndBackupUseCase: reparseAndBackupUseCase,
            transferBackupToProvider: transferBackupToProvider,
            transferTargets: storagesViewModel.connectedProviders,
            backupMetadataRepository: backupMetadataRepository
        )
        detailViewModel.onDataChanged = { [storagesViewModel] in
            viewModel.loadRecords()
            Task { await storagesViewModel.loadStorageUsage() }
        }
        return detailViewModel
    }

    // MARK: - Cloud Search

    /// Секция результатов глобального поиска по всем подключённым дискам.
    @ViewBuilder
    private var cloudSearchSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 8) {
                Text("Файлы в облаке")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if storagesViewModel.isCloudSearchRunning {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                }
            }

            if storagesViewModel.cloudSearchResults.isEmpty
                && !storagesViewModel.isCloudSearchRunning {
                Text("Ничего не найдено в подключённых хранилищах.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(storagesViewModel.cloudSearchResults) { result in
                    cloudResultRow(result)
                }
            }
        }
    }

    /// Строка результата поиска: папка → push-навигация в браузер
    /// папки, файл → скачивание + QuickLook-просмотр.
    @ViewBuilder
    private func cloudResultRow(_ result: StoragesViewModel.CloudSearchResult) -> some View {
        if result.file.isFolder {
            NavigationLink(value: CloudFolderRoute(
                provider: result.provider,
                folderID: result.file.id,
                folderName: result.file.name
            )) {
                cloudResultRowContent(result, icon: "folder.fill", tint: .orange)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await handleCloudFileTap(result) }
            } label: {
                cloudResultRowContent(result, icon: "doc.fill", tint: result.provider.tint)
            }
            .buttonStyle(.plain)
        }
    }

    private func cloudResultRowContent(
        _ result: StoragesViewModel.CloudSearchResult,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.file.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(result.provider.tint)
                            .frame(width: 6, height: 6)

                        Text(result.provider.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Spacer()

                if let size = result.file.sizeBytes {
                    Text(Self.cloudByteFormatter.string(fromByteCount: size))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Тап по файлу из результатов поиска: скачивание во временный
    /// кэш и QuickLook-просмотр.
    private func handleCloudFileTap(
        _ result: StoragesViewModel.CloudSearchResult
    ) async {
        guard !isDownloadingPreview else { return }
        isDownloadingPreview = true
        defer { isDownloadingPreview = false }

        do {
            let url = try await storagesViewModel.downloadForPreview(
                result.file,
                provider: result.provider
            )
            previewFileURL = url
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recently Opened Cloud Files

    /// Секция «Последние открытые»: облачные файлы, которые пользователь
    /// открывал (превью/плеер/свойства). При выбранном фильтре-чипе
    /// показываются только файлы этого провайдера.
    @ViewBuilder
    private var recentlyOpenedSection: some View {
        let items = storagesViewModel.openedFiles(for: selectedProvider)

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Последние открытые")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                ForEach(items) { opened in
                    openedFileRow(opened)
                }
            }
        }
    }

    private func openedFileRow(_ opened: OpenedCloudFile) -> some View {
        Button {
            Task { await handleOpenedFileTap(opened) }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(opened.provider.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(opened.file.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(opened.provider.tint)
                            .frame(width: 6, height: 6)

                        Text(opened.provider.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))

                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))

                        Text(opened.openedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                    }
                }

                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Тап по файлу из «Последних открытых»: скачивание
    /// во временный кэш и QuickLook-просмотр.
    private func handleOpenedFileTap(_ opened: OpenedCloudFile) async {
        guard !isDownloadingPreview else { return }
        isDownloadingPreview = true
        defer { isDownloadingPreview = false }

        do {
            let url = try await storagesViewModel.downloadForPreview(
                opened.file,
                provider: opened.provider
            )
            previewFileURL = url
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private static let cloudByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    // MARK: - Backup List
    private var backupList: some View {
        List {
            ForEach(viewModel.records) { record in
                HStack(spacing: AppSpacing.sm) {
                    NavigationLink {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("История версий")
                                .font(.title)
                            Text("Файл: \(record.fileName)")
                            Text("ID записи: \(record.id.uuidString)")
                        }
                        .padding()
                    } label: {
                        backupRowContent(record)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }

    // MARK: - Backup Row Content
    private func backupRowContent(_ record: BackupRecord) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(record.fileName)
                    .font(AppTypography.bodyMedium)

                Text(
                    "Обновлено: \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Empty State
    private var emptyState: some View {
        ContentUnavailableView(
            "Нет резервных копий",
            systemImage: "externaldrive",
            description: Text(
                "Создайте первую резервную копию, чтобы она появилась здесь."
            )
        )
    }
}

// MARK: - Preview
private struct PreviewCloudStorageRepository: CloudStorageRepository {
    func getStorageUsage() async throws -> CloudStorageUsage {
        CloudStorageUsage(usedBytes: 0, totalBytes: 0, availableBytes: 0)
    }
    func connect() async throws -> CloudStorageAccount {
        throw CloudStorageError.notImplemented
    }
    func restoreConnection() async throws -> CloudStorageAccount? {
        nil
    }
    func signOut() async throws {}
    func listFiles(parentFolderID: String?) async throws -> [CloudFile] {
        []
    }
    func fileMetadata(id: String) async throws -> CloudFile {
        throw CloudStorageError.notFound
    }
    func createFolder(name: String, parentFolderID: String?) async throws -> CloudFile {
        throw CloudStorageError.notImplemented
    }
    func uploadFile(
        at fileURL: URL,
        parentFolderID: String?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> CloudFile {
        throw CloudStorageError.notImplemented
    }
    func deleteFile(id: String) async throws {
        throw CloudStorageError.notImplemented
    }
}

#Preview {
    let container = try! ModelContainer(
        for: BackupRecordModel.self, BackupVersionModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let repository = BackupMetadataRepositoryImpl(modelContext: container.mainContext)
    let mockStorageRepository = PreviewCloudStorageRepository()
    let fileAccess = LocalFileAccess()
    let hasher = SHA256FileHasher()
    let uploadRepository = UploadSessionRepositoryImpl(modelContext: container.mainContext)

    BackupListView(
        fetchBackupRecords: FetchBackupRecordsUseCase(repository: repository),
        fileAccessRepository: fileAccess,
        fileHasher: hasher,
        backupMetadataRepository: repository,
        storagesViewModel: StoragesViewModel(
            repository: mockStorageRepository
        ),
        createBackupWithUpload: CreateBackupWithUploadUseCase(
            backupRepository: repository,
            cloudStorageRepository: mockStorageRepository,
            fileHasher: hasher,
            fileAccessRepository: fileAccess,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: SaveUploadSessionUseCase(repository: uploadRepository),
            updateUploadProgressUseCase: UpdateUploadProgressUseCase(repository: uploadRepository)
        ),
        deleteBackupUseCase: DeleteBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: mockStorageRepository
        ),
        reparseAndBackupUseCase: ReparseAndBackupUseCase(
            backupRepository: repository,
            cloudStorageRepository: mockStorageRepository,
            fileHasher: hasher,
            fileAccessRepository: fileAccess,
            uploadSessionRepository: uploadRepository,
            saveUploadSessionUseCase: SaveUploadSessionUseCase(repository: uploadRepository),
            updateUploadProgressUseCase: UpdateUploadProgressUseCase(repository: uploadRepository)
        ),
        fetchBackupVersions: FetchBackupVersionsUseCase(repository: repository)
    )
    .modelContainer(container)
}

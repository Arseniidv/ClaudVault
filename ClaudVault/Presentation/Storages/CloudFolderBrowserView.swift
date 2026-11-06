import SwiftUI

/// Маршрут для push-навигации внутри стека «Файлы»:
/// папка из облака, открытая из результатов поиска.
struct CloudFolderRoute: Hashable {
    let provider: StorageProviderType
    let folderID: String
    let folderName: String
}

/// Браузер содержимого облачной папки внутри вкладки «Файлы».
/// Каждый уровень — отдельный push в NavigationStack текущей вкладки,
/// поэтому кнопка «Назад» работает нативно.
struct CloudFolderBrowserView: View {
    let provider: StorageProviderType
    let route: CloudFolderRoute
    let storagesViewModel: StoragesViewModel

    @State private var files: [CloudFile] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var previewFileURL: URL?
    @State private var isDownloadingPreview = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.047, blue: 0.075)
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let loadError {
                ContentUnavailableView(
                    "Не удалось загрузить папку",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if files.isEmpty {
                ContentUnavailableView(
                    "Папка пуста",
                    systemImage: "folder",
                    description: Text("В этой папке нет файлов.")
                )
            } else {
                List(files) { file in
                    row(for: file)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(route.folderName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .toolbarBackground(
            Color(red: 0.035, green: 0.047, blue: 0.075),
            for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .navigationDestination(for: CloudFolderRoute.self) { childRoute in
            CloudFolderBrowserView(
                provider: childRoute.provider,
                route: childRoute,
                storagesViewModel: storagesViewModel
            )
        }
        .task(id: route) {
            await load()
        }
        .sheet(isPresented: Binding(
            get: { previewFileURL != nil },
            set: { isPresented in
                if !isPresented {
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
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for file: CloudFile) -> some View {
        if file.isFolder {
            NavigationLink(value: CloudFolderRoute(
                provider: provider,
                folderID: file.id,
                folderName: file.name
            )) {
                fileRowContent(file, icon: "folder.fill", tint: .orange)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 0) {
                Button {
                    Task { await openPreview(file) }
                } label: {
                    fileRowContent(file, icon: "doc.fill", tint: provider.tint)
                }
                .buttonStyle(.plain)

                transferMenu(for: file)
            }
        }
    }

    private func fileRowContent(_ file: CloudFile, icon: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let size = file.sizeBytes {
                    Text(Self.byteFormatter.string(fromByteCount: size))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Меню cloud-to-cloud переноса — только если подключено >1 хранилища.
    @ViewBuilder
    private func transferMenu(for file: CloudFile) -> some View {
        let targets = storagesViewModel.connectedStorageProviders
            .map(\.provider)
            .filter { $0 != provider }

        if !targets.isEmpty {
            Menu {
                ForEach(targets, id: \.self) { target in
                    Button("Копировать в \(target.name)") {
                        Task {
                            await storagesViewModel.transferItem(
                                file, from: provider, to: target, move: false
                            )
                            await load()
                        }
                    }
                    Button("Переместить в \(target.name)") {
                        Task {
                            await storagesViewModel.transferItem(
                                file, from: provider, to: target, move: true
                            )
                            await load()
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            files = try await storagesViewModel.listCloudFiles(
                provider: provider,
                parentFolderID: route.folderID
            )
        } catch {
            #if DEBUG
            print(
                "[CloudFolderBrowser] listFiles failed — "
                    + "provider=\(provider.rawValue) "
                    + "folderID=\(route.folderID) "
                    + "folderName=\(route.folderName) "
                    + "error=\(error)"
            )
            #endif
            loadError = "\(provider.name): \(error.localizedDescription)"
        }
    }

    private func openPreview(_ file: CloudFile) async {
        guard !isDownloadingPreview else { return }
        isDownloadingPreview = true
        defer { isDownloadingPreview = false }

        do {
            let url = try await storagesViewModel.downloadForPreview(
                file,
                provider: provider
            )
            previewFileURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

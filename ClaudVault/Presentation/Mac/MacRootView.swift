#if os(macOS)
import SwiftUI
import ClaudVaultDomain

/// Корневой layout для macOS: NavigationSplitView с боковой
/// панелью разделов и подключённых облаков. Настройки живут
/// в отдельном окне (⌘,) через сцену `Settings` в ClaudVaultApp.
struct MacRootView: View {

    @Binding var selection: AppTab

    let dependencies: AppDependencies
    let storagesViewModel: StoragesViewModel

    /// Фильтр облака на экране «Файлы»: nil — все облака.
    /// Выбирается строками раздела «Облака» в боковой панели
    /// и дублируется чипами-фильтрами над таблицей.
    @State private var filesProviderFilter: StorageProviderType? = nil

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 200,
                    ideal: 230,
                    max: 300
                )
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    AppColors.background
                        .ignoresSafeArea()
                )
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                sidebarSection(title: "Разделы") {
                    sidebarRow(
                        title: AppTab.files.title,
                        icon: AppTab.files.icon,
                        isSelected: selection == .files
                    ) {
                        selection = .files
                    }

                    sidebarRow(
                        title: AppTab.storages.title,
                        icon: AppTab.storages.icon,
                        isSelected: selection == .storages
                    ) {
                        selection = .storages
                    }

                    sidebarRow(
                        title: "Синхронизация",
                        icon: AppTab.synchronization.icon,
                        isSelected: selection == .synchronization
                    ) {
                        selection = .synchronization
                    }
                }

                sidebarSection(title: "Облака") {
                    ForEach(storagesViewModel.connectedStorageProviders) { provider in
                        cloudRow(provider)
                    }

                    Button {
                        storagesViewModel.requestConnect()
                        selection = .storages
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 15))
                                .frame(width: 24)
                                .foregroundStyle(.primary.opacity(0.55))

                            Text("Добавить облако…")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary.opacity(0.65))
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                sidebarSection(title: "Приложение") {
                    Button {
                        openSettings()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: AppTab.settings.icon)
                                .font(.system(size: 15))
                                .frame(width: 24)
                                .foregroundStyle(.primary.opacity(0.65))

                            Text("Настройки")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary.opacity(0.65))
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background)
    }

    /// Строка подключённого облака: выбор переводит на «Файлы»
    /// с фильтром по этому провайдеру.
    private func cloudRow(_ provider: StorageProvider) -> some View {
        let isSelected = selection == .files
            && filesProviderFilter == provider.provider

        return Button {
            filesProviderFilter = provider.provider
            selection = .files
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(provider.tint)
                    .frame(width: 8, height: 8)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : .primary.opacity(0.7))
                        .lineLimit(1)

                    if !provider.email.isEmpty {
                        Text(provider.email)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(isSelected
                          ? Color.blue.opacity(0.28)
                          : Color.clear)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sidebarSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.primary.opacity(0.45))
                .padding(.horizontal, AppSpacing.sm)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, 2)

            content()
        }
    }

    private func sidebarRow(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.65))

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.65))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(isSelected
                          ? Color.blue.opacity(0.28)
                          : Color.clear)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .files, .settings:
            // `.settings` — fallback: на macOS настройки живут
            // в отдельном окне (⌘,), вкладка сюда не ведёт.
            filesView

        case .storages:
            NavigationStack {
                StoragesView(viewModel: storagesViewModel)
            }

        case .synchronization:
            NavigationStack {
                SynchronizationView(
                    viewModel: dependencies.makeSynchronizationViewModel()
                )
            }
        }
    }

    private var filesView: some View {
        BackupListView(
            fetchBackupRecords: dependencies.fetchBackupRecords,
            fileAccessRepository: dependencies.fileAccessRepository,
            fileHasher: dependencies.fileHasher,
            backupMetadataRepository: dependencies.backupMetadataRepository,
            storagesViewModel: storagesViewModel,
            createBackupWithUpload: dependencies.createBackupWithUpload,
            deleteBackupUseCase: dependencies.deleteBackup,
            reparseAndBackupUseCase: dependencies.reparseAndBackup,
            transferBackupToProvider: dependencies.transferBackupToProvider,
            renameBackupUseCase: dependencies.renameBackup,
            fetchBackupVersions: dependencies.fetchBackupVersions,
            actionRouter: dependencies.backupActionRouter,
            providerFilter: $filesProviderFilter,
            navigationRouter: dependencies.navigationRouter
        )
    }
}
#endif

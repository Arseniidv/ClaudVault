#if os(iOS)
import SwiftUI

/// Разделы боковой панели iPad-интерфейса.
/// Зеркалируют существующие вкладки `AppTab` плюс «Обзор»
/// (DashboardView уже существует в проекте, но не был подключён).
enum IPadSection: String, CaseIterable, Identifiable {
    case dashboard
    case files
    case storages
    case synchronization
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Обзор"
        case .files: return "Файлы"
        case .storages: return "Хранилища"
        case .synchronization: return "Синхронизация"
        case .settings: return "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .files: return "arrow.up.folder.fill"
        case .storages: return "cloud.fill"
        case .synchronization:
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill"
        case .settings:
            return "slider.horizontal.2.arrow.trianglehead.counterclockwise"
        }
    }

}

/// Корневой layout для iPadOS: NavigationSplitView с сайдбаром,
/// основной областью контента и (для «Файлов») инспектором.
/// Все экраны и ViewModel'и переиспользуются из существующей
/// архитектуры — здесь только навигационная обвязка.
struct IPadRootView: View {

    @Binding var selection: IPadSection

    let dependencies: AppDependencies
    let authViewModel: AuthViewModel
    let storagesViewModel: StoragesViewModel
    let backupActionRouter: BackupActionRouter

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: 240,
                    max: 320
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
                sidebarSection(title: "Обзор") {
                    sidebarRow(.dashboard)
                }
                sidebarSection(title: "Файлы") {
                    sidebarRow(.files)
                }
                sidebarSection(title: "Облака") {
                    sidebarRow(.storages)
                    sidebarRow(.synchronization)
                }
                sidebarSection(title: "Приложение") {
                    sidebarRow(.settings)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background)
        .navigationTitle("CloudVault")
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

    private func sidebarRow(_ section: IPadSection) -> some View {
        let isSelected = selection == section

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = section
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)

                Text(section.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer()
            }
            .foregroundStyle(isSelected ? .white : .primary.opacity(0.65))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 10)
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
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard:
            DashboardView(
                fetchBackupRecords: dependencies.fetchBackupRecords
            )

        case .files:
            IPadFilesView(
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
                actionRouter: backupActionRouter
            )

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

        case .settings:
            NavigationStack {
                SettingsView(
                    authViewModel: authViewModel,
                    deviceTransferCoordinator: dependencies.deviceTransferCoordinator
                )
            }
        }
    }
}

#endif

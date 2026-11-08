#if os(macOS)
import SwiftUI
import AppKit

/// Содержимое Menu Bar Extra (.window style): статус, облачные
/// провайдеры, быстрые действия, последняя активность и футер.
/// Данные — из общего `MenuBarViewModel`, без дублирования сервисов.
struct MenuBarView: View {
    @State private var viewModel: MenuBarViewModel

    @Environment(\.openWindow) private var openWindow

    init(viewModel: MenuBarViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            providersSection
            Divider().padding(.vertical, 8)
            actionsSection
            if !viewModel.recentSessions.isEmpty {
                Divider().padding(.vertical, 8)
                activitySection
            }
            Divider().padding(.vertical, 8)
            footer
        }
        .padding(12)
        .frame(width: 320)
        .background(AppColors.background)
        .preferredColorScheme(.dark)
        .task {
            viewModel.startMonitoring()
            await viewModel.refresh()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 32, height: 32)
                .background(AppColors.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text("CloudVault")
                    .font(.system(size: 14, weight: .semibold))

                HStack(spacing: 5) {
                    if viewModel.isSyncing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(viewModel.statusTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .idle: return AppColors.success
        case .syncing: return AppColors.warning
        case .error: return AppColors.error
        case .disconnected: return Color.secondary
        }
    }

    // MARK: - Providers

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Хранилища")

            ForEach(viewModel.providerRows) { row in
                MenuBarProviderRow(row: row) {
                    viewModel.openProvider(row.provider)
                    openMainWindow()
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("Действия")

            actionRow(
                title: "Открыть CloudVault",
                systemImage: "macwindow",
                action: openMainWindow
            )

            actionRow(
                title: "Новая резервная копия",
                systemImage: "arrow.up.doc",
                action: {
                    viewModel.requestNewBackup()
                    openMainWindow()
                }
            )

            actionRow(
                title: "Возобновить передачи",
                systemImage: "arrow.triangle.2.circlepath",
                disabled: !viewModel.canResumeTransfers,
                action: viewModel.resumePendingTransfers
            )

            actionRow(
                title: "Настройки",
                systemImage: "gearshape",
                action: {
                    viewModel.openSettings()
                    openMainWindow()
                }
            )
        }
    }

    private func actionRow(
        title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .primary)
        .disabled(disabled)
        .padding(.vertical, 3)
    }

    // MARK: - Recent Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Активность")

            ForEach(viewModel.recentSessions) { session in
                HStack(spacing: 8) {
                    Image(systemName: sessionIcon(session.status))
                        .font(.system(size: 11))
                        .foregroundStyle(sessionColor(session.status))
                        .frame(width: 14)

                    Text(session.fileName)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    Spacer()

                    Text(session.updatedAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func sessionIcon(_ status: SessionStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .pending, .paused: return "pause.circle.fill"
        case .uploading: return "arrow.up.circle.fill"
        }
    }

    private func sessionColor(_ status: SessionStatus) -> Color {
        switch status {
        case .completed: return AppColors.success
        case .failed: return AppColors.error
        case .pending, .paused, .uploading: return AppColors.warning
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Открыть") { openMainWindow() }
            Spacer()
            Button("Настройки") {
                viewModel.openSettings()
                openMainWindow()
            }
            Button("Выйти") {
                NSApp.terminate(nil)
            }
        }
        .font(.system(size: 12))
        .buttonStyle(.borderless)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    /// Открывает/активирует основное окно. `Window`-сцена с id "main"
    /// гарантирует единственный экземпляр: `openWindow` переиспользует
    /// закрытое окно вместо создания дубля.
    private func openMainWindow() {
        openWindow(id: "main")
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

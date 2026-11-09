import SwiftUI
import ClaudVaultDomain

struct SynchronizationView: View {

    let viewModel: SynchronizationViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statusSection
                    activeTransfersSection
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))

            failedTransfersSection

            completedTransfersSection

            Section {
                footer
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 32, trailing: 24))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle("Синхронизация")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .alert(
            "Ошибка",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLOUDVAULT")
                .font(.system(size: 11, weight: .bold))
                .tracking(3)
                .foregroundStyle(Color.blue.opacity(0.9))

            Text("Синхронизация")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Состояние передачи и резервного копирования")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 5) {
                Text("Состояние системы")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(viewModel.hasActiveTransfers ? "Идёт передача файлов" : "Нет активных передач")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.5))
            }

            Spacer()

            Circle()
                .fill(viewModel.hasActiveTransfers ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
        }
        .padding(18)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Active transfers

    private var activeTransfersSection: some View {
        ActiveTransfersSectionView(
            tasks: viewModel.activeTasks,
            onCancel: { viewModel.cancelTransfer(id: $0.id) },
            onDelete: { viewModel.deleteSession(id: $0.id) }
        )
    }

    // MARK: - Failed transfers

    @ViewBuilder
    private var failedTransfersSection: some View {
        if !viewModel.failedSessions.isEmpty {
            Section {
                ForEach(viewModel.failedSessions) { session in
                    FailedTransferView(
                        fileName: session.fileName,
                        errorDescription: session.errorMessage ?? "Ошибка передачи",
                        onRetry: { viewModel.retry(session) },
                        onDelete: { viewModel.deleteSession(id: session.id) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteSession(id: session.id)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            viewModel.retry(session)
                        } label: {
                            Label("Повторить", systemImage: "arrow.clockwise")
                        }
                        .tint(.blue)
                    }
                }
            } header: {
                HStack {
                    Text("Ошибки передачи")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text("\(viewModel.failedSessions.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
                .textCase(nil)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
        }
    }

    // MARK: - Completed transfers

    private var completedTransfersSection: some View {
        Section {
            if viewModel.completedTasks.isEmpty {
                Text("Нет завершённых операций")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.completedTasks) { task in
                    SyncTaskCardView(
                        task: task,
                        onDelete: { viewModel.deleteSession(id: task.id) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteSession(id: task.id)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Завершённые операции")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text("\(viewModel.completedTasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
            .textCase(nil)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Прогресс отображается по данным реальных сессий загрузки.")
            .font(.system(size: 11))
            .foregroundStyle(.primary.opacity(0.35))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

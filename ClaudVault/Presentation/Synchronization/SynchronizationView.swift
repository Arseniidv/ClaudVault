import SwiftUI

struct SynchronizationView: View {

    let viewModel: SynchronizationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                statusSection

                activeTransfersSection

                failedTransfersSection

                completedTransfersSection

                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(red: 0.035, green: 0.04, blue: 0.055))
        .navigationTitle("Синхронизация")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(.white)

            Text("Состояние передачи и резервного копирования")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
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
                    .foregroundStyle(.white)

                Text(viewModel.hasActiveTransfers ? "Идёт передача файлов" : "Нет активных передач")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Circle()
                .fill(viewModel.hasActiveTransfers ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
        }
        .padding(18)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Active transfers

    private var activeTransfersSection: some View {
        ActiveTransfersSectionView(tasks: viewModel.activeTasks)
    }

    // MARK: - Failed transfers

    @ViewBuilder
    private var failedTransfersSection: some View {
        if !viewModel.failedSessions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Ошибки передачи")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(viewModel.failedSessions.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }

                ForEach(viewModel.failedSessions) { session in
                    FailedTransferView(
                        fileName: session.fileName,
                        errorDescription: session.errorMessage ?? "Ошибка передачи",
                        onRetry: { viewModel.retry(session) }
                    )
                }
            }
        }
    }

    // MARK: - Completed transfers

    private var completedTransfersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Завершённые операции")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(viewModel.completedTasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }

            if viewModel.completedTasks.isEmpty {
                Text("Нет завершённых операций")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(viewModel.completedTasks) { task in
                    SyncTaskCardView(task: task)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Прогресс отображается по данным реальных сессий загрузки.")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

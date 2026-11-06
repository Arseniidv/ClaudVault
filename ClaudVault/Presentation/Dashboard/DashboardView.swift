import SwiftUI

@MainActor
struct DashboardView: View {

    @State private var viewModel: DashboardViewModel

    init(fetchBackupRecords: FetchBackupRecordsUseCase) {
        _viewModel = State(
            initialValue: DashboardViewModel(
                fetchBackupRecords: fetchBackupRecords
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sectionSpacing) {
                    headerSection
                    statisticsSection
                    recentBackupsSection
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.screenVertical)
            }
            .navigationTitle("Обзор")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.loadDashboard()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Обновить")
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Загрузка...")
                }
            }
            .alert(
                "Ошибка",
                isPresented: errorAlertPresented
            ) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "Неизвестная ошибка")
            }
        }
        .task {
            viewModel.loadDashboard()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("CloudVault")
                .font(AppTypography.screenTitle)

            Text("Состояние резервного копирования")
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Статистика")
                .font(AppTypography.sectionTitle)

            HStack(spacing: AppSpacing.md) {
                statisticCard(
                    title: "Резервные копии",
                    value: "\(viewModel.backupCount)",
                    symbol: "externaldrive"
                )

                statisticCard(
                    title: "Последняя операция",
                    value: lastBackupText,
                    symbol: "clock"
                )
            }
        }
    }

    private func statisticCard(
        title: String,
        value: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(AppTypography.metric)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(AppSpacing.cardPadding)
        .background(.secondary.opacity(0.06))
        .clipShape(
            RoundedRectangle(cornerRadius: AppRadius.card)
        )
    }

    private var recentBackupsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Последние резервные копии")
                .font(AppTypography.sectionTitle)

            if viewModel.recentRecords.isEmpty {
                ContentUnavailableView(
                    "Пока нет копий",
                    systemImage: "externaldrive",
                    description: Text("Созданные резервные копии появятся здесь.")
                )
            } else {
                ForEach(viewModel.recentRecords) { record in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "doc.zipper")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(record.fileName)
                                .font(AppTypography.bodyMedium)
                                .lineLimit(1)

                            Text(
                                record.updatedAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xs)

                    if record.id != viewModel.recentRecords.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var lastBackupText: String {
        guard let date = viewModel.lastBackupDate else {
            return "Нет данных"
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

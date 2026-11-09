import SwiftUI
import ClaudVaultDomain

struct RecentFilesView: View {

    // MARK: - Properties

    let records: [BackupRecord]
    let searchText: String
    let selectedSort: SortOption
    var providerFilter: StorageProviderType? = nil

    var onFileTap: (BackupRecord) -> Void = { _ in }
    var onDelete: (BackupRecord) -> Void = { _ in }

    enum SortOption: String, CaseIterable, Identifiable {
        case latest = "Последние"
        case oldest = "Сначала старые"
        case name = "По имени"

        var id: String {
            rawValue
        }
    }

    // MARK: - Filtering and Sorting

    private var displayedRecords: [BackupRecord] {

        let filteredRecords = records.filter { record in
            (providerFilter == nil || record.storageProvider == providerFilter) &&
            (searchText.isEmpty ||
             record.fileName.localizedCaseInsensitiveContains(searchText))
        }

        switch selectedSort {

        case .latest:
            return filteredRecords.sorted(by: {
                $0.updatedAt > $1.updatedAt
            })

        case .oldest:
            return filteredRecords.sorted(by: {
                $0.updatedAt < $1.updatedAt
            })

        case .name:
            return filteredRecords.sorted(by: {
                $0.fileName.localizedCaseInsensitiveCompare($1.fileName)
                    == .orderedAscending
            })
        }
    }

    // MARK: - Body

    var body: some View {

        Group {

            if displayedRecords.isEmpty {

                ContentUnavailableView(
                    "Файлы не найдены",
                    systemImage: "doc",
                    description: Text(
                        "Попробуйте изменить поисковый запрос."
                    )
                )

            } else {

                LazyVStack(spacing: AppSpacing.sm) {

                    ForEach(displayedRecords) { record in

                        Button {
                            onFileTap(record)
                        } label: {
                            RecentFileRowView(record: record)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Контекстное меню для удаления файла без выноса кнопок наружу
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(record)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

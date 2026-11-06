import SwiftUI

struct FilesView: View {

    @State private var selectedSort: RecentFilesView.SortOption = .latest
    @State private var searchText = ""

    let records: [BackupRecord]
    let storagesViewModel: StoragesViewModel

    var onFileTap: (BackupRecord) -> Void = { _ in }
    var onAddBackup: () -> Void = {}

    // MARK: - Computed Properties

    private var providers: [StorageProvider] {
        guard let usage = storagesViewModel.storageUsage else {
            return []
        }

        return [
            StorageProvider(
                provider: .oneDrive,
                name: "OneDrive",
                email: storagesViewModel.account?.email ?? "",
                usedStorage: usage.usedBytesInGB,
                totalStorage: usage.totalBytesInGB,
                syncTime: Date()
            )
        ]
    }

    private var usedStorage: Double {
        storagesViewModel.storageUsage?.usedBytesInGB ?? 0
    }

    private var totalStorage: Double {
        storagesViewModel.storageUsage?.totalBytesInGB ?? 0
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {

                    FilesHeaderView(
                        selectedSort: $selectedSort
                    )

                    SearchBarView(
                        searchText: $searchText
                    )

                    StorageOverviewView(
                        providers: providers,
                        usedStorage: usedStorage,
                        totalStorage: totalStorage,
                        backupVersionsBytes: nil,
                        localFilesBytes: nil,
                        localFilesCount: nil
                    )

                    RecentFilesView(
                        records: records,
                        searchText: searchText,
                        selectedSort: selectedSort,
                        onFileTap: onFileTap
                    )

                    FooterSectionView(
                        connectedClouds: providers.count,
                        totalFiles: records.count
                    )
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.screenVertical)
            }

            AddBackupButton(action: onAddBackup)
            .padding(.trailing, AppSpacing.screenHorizontal)
            .padding(.bottom, AppSpacing.xl)
        }
    }
}

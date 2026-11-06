import SwiftUI

struct StorageOverviewView: View {

    let providers: [StorageProvider]
    let usedStorage: Double
    let totalStorage: Double

    /// Объём всех версий резервных копий в облаке, байт.
    var backupVersionsBytes: Int64? = nil
    /// Суммарный размер отслеживаемых локальных файлов, байт.
    var localFilesBytes: Int64? = nil
    /// Количество отслеживаемых локальных файлов.
    var localFilesCount: Int? = nil

    // MARK: - Computed Properties

    private var usagePercentage: Int {
        guard totalStorage > 0 else { return 0 }
        return Int((usedStorage / totalStorage) * 100)
    }

    private var progress: Double {
        guard totalStorage > 0 else { return 0 }
        return min(max(usedStorage / totalStorage, 0), 1)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Использовано облачного хранилища")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("\(usedStorage, specifier: "%.1f") GB")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(usagePercentage)%")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.cyan)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))

                    Capsule()
                        .fill(Color.cyan)
                        .frame(
                            width: geometry.size.width * progress
                        )
                }
            }
            .frame(height: 8)

            HStack {
                Text("Занято: \(usedStorage, specifier: "%.1f") GB")

                Spacer()

                Text("Всего: \(totalStorage, specifier: "%.1f") GB")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))

            Divider()
                .background(Color.white.opacity(0.08))

            statsRow
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 16) {
            if let backupVersionsBytes {
                statItem(
                    title: "Резервные версии",
                    value: Self.byteFormatter.string(fromByteCount: backupVersionsBytes)
                )
            }

            if let localFilesBytes, let localFilesCount {
                statItem(
                    title: "Локальные файлы (\(localFilesCount))",
                    value: Self.byteFormatter.string(fromByteCount: localFilesBytes)
                )
            }
        }
        .font(.system(size: 12))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

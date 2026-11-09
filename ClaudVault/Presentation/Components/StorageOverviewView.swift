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


    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Использовано облачного хранилища")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.75))

                    Text("\(usedStorage, specifier: "%.1f") GB")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer()

                Text("\(usagePercentage)%")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.cyan)
            }

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(providers) { provider in
                        let fraction = totalStorage > 0
                            ? provider.usedStorage / totalStorage : 0
                        let segmentWidth = geometry.size.width * CGFloat(fraction)

                        if segmentWidth > 0 {
                            Rectangle()
                                .fill(provider.tint)
                                .frame(width: segmentWidth)
                        }
                    }

                    let freeFraction = totalStorage > 0
                        ? max(totalStorage - usedStorage, 0) / totalStorage : 1

                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: geometry.size.width * CGFloat(freeFraction))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            HStack(spacing: 16) {
                ForEach(providers) { provider in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(provider.tint)
                            .frame(width: 6, height: 6)

                        Text("\(provider.name): \(provider.usedStorage, specifier: "%.1f") GB")
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.75))

            HStack {
                Text("Занято: \(usedStorage, specifier: "%.1f") GB")

                Spacer()

                Text("Всего: \(totalStorage, specifier: "%.1f") GB")
            }
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.75))

            Divider()
                .background(Color.primary.opacity(0.08))

            statsRow
        }
        .padding(18)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 16) {
            if let backupVersionsBytes {
                statItem(
                    title: "Резервные версии",
                    value: ByteFormatting.string(fromByteCount: backupVersionsBytes)
                )
            }

            if let localFilesBytes, let localFilesCount {
                statItem(
                    title: "Локальные файлы (\(localFilesCount))",
                    value: ByteFormatting.string(fromByteCount: localFilesBytes)
                )
            }
        }
        .font(.system(size: 12))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .foregroundStyle(.primary.opacity(0.7))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}

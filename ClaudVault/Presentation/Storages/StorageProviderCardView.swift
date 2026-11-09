import SwiftUI

struct StorageProviderCardView: View {
    let provider: StorageProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(provider.tint)
                    .frame(width: 46, height: 46)
                    .background(provider.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 5) {
                    Text(provider.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(provider.email)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.5))
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 9) {
                HStack {
                    Text("Использовано")
                        .foregroundStyle(.primary.opacity(0.55))

                    Spacer()

                    if provider.usageAvailable {
                        Text("\(provider.usedStorage.formatted(.number.precision(.fractionLength(1)))) GB / \(provider.totalStorage.formatted(.number.precision(.fractionLength(0)))) GB")
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        Text("—")
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                }
                .font(.system(size: 12))

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))

                        Capsule()
                            .fill(provider.tint)
                            .frame(width: geometry.size.width * provider.progress)
                    }
                }
                .frame(height: 7)
            }

            HStack {
                if provider.usageAvailable {
                    Text("\(provider.usagePercentage)% заполнено")
                        .foregroundStyle(.primary.opacity(0.5))
                } else {
                    Text("Загрузка данных о месте…")
                        .foregroundStyle(.primary.opacity(0.5))
                }

                Spacer()

                Label(
                    "Синхр. \(provider.syncTime)",
                    systemImage: "arrow.clockwise"
                )
                .foregroundStyle(.primary.opacity(0.5))
            }
            .font(.system(size: 11))
        }
        .padding(16)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

#if os(macOS)
import SwiftUI

/// Строка облачного провайдера в Menu Bar: иконка, название,
/// статус подключения, занятое место и состояние операции.
struct MenuBarProviderRow: View {
    let row: MenuBarViewModel.ProviderRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: row.provider.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(row.provider.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.provider.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    statusLine
                }

                Spacer()

                trailingStatus
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = row.errorMessage {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.error)
                .lineLimit(1)
        } else if let account = row.account {
            Text(account.email)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("Не подключено")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if row.isBusy {
            ProgressView()
                .controlSize(.small)
        } else if let usage = row.storageUsage, usage.totalBytes > 0 {
            Text("\(Int(usage.usagePercentage * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        } else if row.account != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.success)
        } else {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }
}
#endif

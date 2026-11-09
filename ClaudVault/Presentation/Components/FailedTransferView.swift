import SwiftUI

struct FailedTransferView: View {
    let fileName: String
    let errorDescription: String

    var onRetry: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 23))
                .foregroundStyle(Color.red)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(fileName)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textPrimary)

                Text(errorDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red.opacity(0.85))
            }

            Spacer()

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить из истории")
            }

            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Повторить передачу")
        }
        .padding(AppSpacing.md)
        .background(Color.red.opacity(0.035))
        .clipShape(
            RoundedRectangle(cornerRadius: AppRadius.extraLarge)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.extraLarge)
                .stroke(Color.red.opacity(0.16), lineWidth: 1)
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}

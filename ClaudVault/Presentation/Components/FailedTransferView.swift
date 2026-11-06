import SwiftUI

struct FailedTransferView: View {
    let fileName: String
    let errorDescription: String

    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 23))
                .foregroundStyle(Color.red)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(fileName)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)

                Text(errorDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red.opacity(0.85))
            }

            Spacer()

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
    }
}

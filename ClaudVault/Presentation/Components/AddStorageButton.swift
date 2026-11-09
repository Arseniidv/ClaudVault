import SwiftUI

struct AddStorageButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.cyan)

                Text("Добавить хранилище")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(Color.primary.opacity(0.015))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        Color.primary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1, dash: [7, 6])
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct CompletedTransfersView: View {
    let tasks: [SyncTask]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Завершено")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text("Сегодня")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }

            VStack(spacing: AppSpacing.md) {
                ForEach(tasks) { task in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.green)

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(task.fileName)
                                .font(.system(size: 15))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("\(task.source) · \(task.totalSize) МБ")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.6))
                        }

                        Spacer()

                        Text(task.remainingTime)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(Color.primary.opacity(0.045))
            .clipShape(
                RoundedRectangle(cornerRadius: AppRadius.extraLarge)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.extraLarge)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

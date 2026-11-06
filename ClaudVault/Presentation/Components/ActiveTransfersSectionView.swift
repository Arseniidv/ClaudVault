import SwiftUI

struct ActiveTransfersSectionView: View {
    let tasks: [SyncTask]

    var onPause: (SyncTask) -> Void = { _ in }

    var activeTasks: [SyncTask] {
        tasks.filter { $0.status == .transferring }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Передаём сейчас")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)

                Spacer()
            }

            Text("Новые копии · не влияют на актуальность облаков")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))

            ForEach(activeTasks) { task in
                SyncTaskCardView(task: task)
            }
        }
    }
}

import SwiftUI

struct SyncTaskCardView: View {

    let task: SyncTask
    var onDelete: (() -> Void)? = nil

    private var progressPercentage: Int {
        Int(min(max(task.progress, 0), 1) * 100)
    }

    private var formattedTransferredSize: String {
        String(format: "%.1f", task.transferredSize)
    }

    private var formattedTotalSize: String {
        String(format: "%.1f", task.totalSize)
    }

    private var formattedSpeed: String {
        String(format: "%.1f", task.speed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // MARK: - Header

            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.cyan)

                Text(task.fileName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить из истории")
                }

                Text("\(progressPercentage)%")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cyan)
            }

            // MARK: - Transfer Direction

            HStack {
                Text("\(task.source) → \(task.destination)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }

            // MARK: - Progress

            GeometryReader { geometry in
                ZStack(alignment: .leading) {

                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(Color.blue)
                        .frame(
                            width: geometry.size.width *
                            min(max(task.progress, 0), 1)
                        )
                }
            }
            .frame(height: 5)

            // MARK: - Transfer Information

            HStack {
                Text("\(formattedTransferredSize) / \(formattedTotalSize) МБ · \(formattedSpeed) МБ/с")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))

                Spacer()

                Text("≈ \(task.remainingTime)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}

import SwiftUI

struct FooterSectionView: View {
    let connectedClouds: Int
    let totalFiles: Int

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)

            Text("\(connectedClouds) облака · \(totalFiles.formatted()) файлов")
                .font(AppTypography.caption)
                .foregroundStyle(Color.white.opacity(0.75))

            Spacer()
        }
        .padding(.vertical, AppSpacing.sm)
    }
}


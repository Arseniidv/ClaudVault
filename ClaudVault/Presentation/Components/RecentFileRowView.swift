import SwiftUI

struct RecentFileRowView: View {
    let record: BackupRecord

    private var fileExtension: String {
        URL(fileURLWithPath: record.fileName)
            .pathExtension
            .uppercased()
    }

    private var fileIcon: String {
        switch fileExtension {
        case "PDF":
            return "doc.text"
        case "JPG", "JPEG", "PNG":
            return "photo"
        case "PPT", "PPTX":
            return "rectangle.on.rectangle"
        case "XLS", "XLSX":
            return "tablecells"
        default:
            return "doc"
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: fileIcon)
                .font(.system(size: 22))
                .foregroundStyle(Color.cyan)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.06))
                .clipShape(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                )

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(record.fileName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(record.updatedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                ))
                .font(AppTypography.caption)
                .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color.green)
        }
        .padding(AppSpacing.sm)
        .background(Color.white.opacity(0.045))
        .clipShape(
            RoundedRectangle(cornerRadius: AppRadius.large)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

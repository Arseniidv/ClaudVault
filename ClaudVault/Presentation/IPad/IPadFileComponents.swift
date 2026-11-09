#if os(iOS)
import SwiftUI

/// Иконка по расширению файла — та же логика, что в
/// `RecentFileRowView`, вынесена для переиспользования
/// в строках и карточках iPad-браузера.
enum BackupFileIcon {
    static func symbol(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName)
            .pathExtension.uppercased() {
        case "PDF": return "doc.text"
        case "JPG", "JPEG", "PNG": return "photo"
        case "PPT", "PPTX": return "rectangle.on.rectangle"
        case "XLS", "XLSX": return "tablecells"
        default: return "doc"
        }
    }
}

/// Строка файла для iPad-браузера: иконка типа, имя,
/// дата изменения, провайдер и состояние выбора.
struct IPadFileRowView: View {

    let record: BackupRecord
    var isSelected = false
    var isSelectionMode = false

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: BackupFileIcon.symbol(for: record.fileName))
                .font(.system(size: 20))
                .foregroundStyle(Color.cyan)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(record.fileName)
                    .font(AppTypography.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(record.storageProvider.tint)
                        .frame(width: 6, height: 6)

                    Text(record.storageProvider.name)
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .lineLimit(1)

                    Text("·")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.primary.opacity(0.35))

                    Text(record.updatedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    ))
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineLimit(1)
                }
            }

            Spacer()

            if isSelectionMode {
                Image(systemName: isSelected
                      ? "checkmark.circle.fill"
                      : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.blue : .primary.opacity(0.3))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.3))
            }
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(isSelected
                      ? Color.blue.opacity(0.18)
                      : Color.primary.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(
                    isSelected ? Color.blue.opacity(0.6) : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .contentShape(Rectangle())
    }
}

/// Карточка файла для grid-режима iPad-браузера.
struct IPadFileGridCardView: View {

    let record: BackupRecord
    var isSelected = false
    var isSelectionMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: BackupFileIcon.symbol(for: record.fileName))
                    .font(.system(size: 26))
                    .foregroundStyle(Color.cyan)

                Spacer()

                Circle()
                    .fill(record.storageProvider.tint)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(record.storageProvider.name)
            }

            Text(record.fileName)
                .font(AppTypography.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Text(record.updatedAt.formatted(
                date: .abbreviated,
                time: .omitted
            ))
            .font(AppTypography.caption)
            .foregroundStyle(Color.primary.opacity(0.55))
            .lineLimit(1)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(isSelected
                      ? Color.blue.opacity(0.18)
                      : Color.primary.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(
                    isSelected ? Color.blue.opacity(0.6) : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .contentShape(Rectangle())
    }
}

#endif

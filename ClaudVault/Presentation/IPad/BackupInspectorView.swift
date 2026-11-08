#if os(iOS)
import SwiftUI

/// Инспектор выбранного файла в iPad-разметке.
/// Показывает доступные метаданные `BackupRecord` и действия.
/// Вся логика (версии, переименование, перенос, удаление)
/// остаётся в `BackupRecordDetailView` — здесь только
/// быстрый доступ и сводка.
struct BackupInspectorView: View {

    let record: BackupRecord
    var onOpen: () -> Void = {}
    var onDelete: () -> Void = {}

    private var fileExtension: String {
        URL(fileURLWithPath: record.fileName)
            .pathExtension
            .uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                header
                metadataSection
                actionsSection
            }
            .padding(AppSpacing.md)
        }
        .background(Color(red: 0.035, green: 0.047, blue: 0.075))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Image(systemName: BackupFileIcon.symbol(for: record.fileName))
                .font(.system(size: 40))
                .foregroundStyle(Color.cyan)
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))

            Text(record.fileName)
                .font(AppTypography.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Label(record.storageProvider.name,
                  systemImage: record.storageProvider.icon)
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Свойства")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                metadataRow("Тип файла",
                            value: fileExtension.isEmpty
                                ? "Файл" : fileExtension)
                Divider().overlay(Color.white.opacity(0.08))
                metadataRow("Провайдер",
                            value: record.storageProvider.name)
                Divider().overlay(Color.white.opacity(0.08))
                metadataRow("Создана",
                            value: record.createdAt.formatted(
                                date: .abbreviated, time: .shortened))
                Divider().overlay(Color.white.opacity(0.08))
                metadataRow("Изменена",
                            value: record.updatedAt.formatted(
                                date: .abbreviated, time: .shortened))
            }
            .padding(.vertical, AppSpacing.xs)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        }
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.secondary)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(AppTypography.secondary)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Button(action: onOpen) {
                Label("Подробнее", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
            }
            .buttonStyle(.plain)
        }
    }
}

#endif

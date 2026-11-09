#if os(macOS)
import SwiftUI
import ClaudVaultDomain

/// Строка таблицы «Файлы» на macOS: запись бэкапа
/// плюс размер последней версии (для колонки «Размер»).
struct BackupTableRow: Identifiable, Hashable {
    let record: BackupRecord
    let sizeBytes: Int64?

    var id: UUID { record.id }

    /// Имя облака-провайдера для колонки «Облако».
    var providerName: String { record.storageProvider.name }

    /// Сортировочный ключ размера: записи без версии — в конец.
    var sortSize: Int64 { sizeBytes ?? Int64.max }

    static func == (lhs: BackupTableRow, rhs: BackupTableRow) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Нативная `Table` со списком резервных копий на macOS:
/// сортировка по заголовкам, множественный выбор,
/// контекстное меню, Quick Look по пробелу.
struct MacBackupTable: View {

    let rows: [BackupTableRow]
    @Binding var sortOrder: [KeyPathComparator<BackupTableRow>]
    @Binding var selection: Set<UUID>

    let isLoading: Bool
    let loadFailed: Bool
    /// Текущий поисковый запрос (пустая строка — поиск неактивен).
    let searchQuery: String
    /// Выбран ли фильтр по конкретному облаку.
    let providerFilterActive: Bool
    /// Подключено ли облако из фильтра (false → «облако не подключено»).
    let filterProviderConnected: Bool

    var onOpen: (BackupRecord) -> Void = { _ in }
    var onDelete: (BackupRecord) -> Void = { _ in }
    var onQuickLook: (BackupRecord) -> Void = { _ in }
    var onCreate: () -> Void = {}
    var onRetry: () -> Void = {}

    private var sortedRows: [BackupTableRow] {
        rows.sorted(using: sortOrder)
    }

    var body: some View {
        Table(selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Имя", value: \.record.fileName) { row in
                nameCell(row)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Облако", value: \.providerName) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.record.storageProvider.tint)
                        .frame(width: 7, height: 7)

                    Text(row.providerName)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Размер", value: \.sortSize) { row in
                Text(row.sizeBytes.map {
                    ByteFormatting.string(fromByteCount: $0)
                } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Изменено", value: \.record.updatedAt) { row in
                Text(row.record.updatedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                ))
                .foregroundStyle(.secondary)
            }
            .width(min: 150, ideal: 190)
        } rows: {
            ForEach(sortedRows) { row in
                TableRow(row)
                    .contextMenu {
                        Button {
                            onOpen(row.record)
                        } label: {
                            Label("Открыть", systemImage: "arrow.up.forward.square")
                        }

                        Button {
                            onQuickLook(row.record)
                        } label: {
                            Label("Быстрый просмотр", systemImage: "space")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete(row.record)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
            }
        }
        .overlay {
            if sortedRows.isEmpty {
                emptyState
            }
        }
        .onDeleteCommand {
            for id in selection {
                if let row = rows.first(where: { $0.id == id }) {
                    onDelete(row.record)
                }
            }
            selection.removeAll()
        }
        .onKeyPress(KeyEquivalent(" ")) {
            guard selection.count == 1,
                  let id = selection.first,
                  let row = rows.first(where: { $0.id == id })
            else { return .ignored }
            onQuickLook(row.record)
            return .handled
        }
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                Text("Загрузка списка файлов…")
                    .foregroundStyle(.secondary)
            }
        } else if loadFailed {
            ContentUnavailableView {
                Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Произошла ошибка при получении списка файлов.")
            } actions: {
                Button("Повторить", action: onRetry)
            }
        } else if !searchQuery.isEmpty {
            ContentUnavailableView {
                Label("Ничего не найдено", systemImage: "magnifyingglass")
            } description: {
                Text("По запросу «\(searchQuery)» файлов нет.")
            }
        } else if providerFilterActive {
            ContentUnavailableView {
                Label(
                    filterProviderConnected
                        ? "В этом облаке пока нет файлов"
                        : "Облако не подключено",
                    systemImage: "cloud"
                )
            } description: {
                Text(
                    filterProviderConnected
                        ? "Здесь появятся резервные копии, загруженные в это облако."
                        : "Подключите облако в разделе «Хранилища», чтобы видеть его файлы."
                )
            }
        } else {
            ContentUnavailableView {
                Label("Нет резервных копий", systemImage: "externaldrive")
            } description: {
                Text("Создайте первую резервную копию, чтобы она появилась здесь.")
            } actions: {
                Button("Создать резервную копию", action: onCreate)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    /// Ячейка имени: при наличии локального пути к исходному
    /// файлу строку можно перетаскивать в другие приложения.
    @ViewBuilder
    private func nameCell(_ row: BackupTableRow) -> some View {
        let content = HStack(spacing: AppSpacing.sm) {
            Image(systemName: Self.fileIcon(for: row.record.fileName))
                .font(.system(size: 15))
                .foregroundStyle(Color.cyan)
                .frame(width: 22)

            Text(row.record.fileName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())

        if let path = row.record.localFilePath {
            content.draggable(URL(fileURLWithPath: path))
        } else {
            content
        }
    }

    private static func fileIcon(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.uppercased() {
        case "PDF": return "doc.text"
        case "JPG", "JPEG", "PNG": return "photo"
        case "PPT", "PPTX": return "rectangle.on.rectangle"
        case "XLS", "XLSX": return "tablecells"
        default: return "doc"
        }
    }
}
#endif

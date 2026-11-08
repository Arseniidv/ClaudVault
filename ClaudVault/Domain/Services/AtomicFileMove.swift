import Foundation

/// Атомарная установка скачанного файла на целевой путь.
///
/// Заменяет опасный паттерн `removeItem(destination)` +
/// `moveItem(temp → destination)`: между удалением и перемещением
/// существующий файл пользователя безвозвратно терялся, а сбой
/// оставлял каталог без файла вообще.
///
/// Здесь источник сначала перемещается во временное имя рядом
/// с назначением (тот же том — rename, а не копирование), затем
/// `replaceItemAt` атомарно подменяет цель. Если назначение не
/// существует — обычный `moveItem`. При любой ошибке временный
/// файл удаляется, исходник при этом уже «переехал» — поэтому
/// вызывающий код должен считать источник потреблённым.
enum AtomicFileMove {

    static func moveIntoPlace(_ source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()

        // Соседнее временное имя: moveItem между томами — это
        // копирование, а rename в пределах каталога назначения
        // гарантирует атомарность replaceItemAt.
        let staging = directory.appendingPathComponent(
            ".clv-staging-\(UUID().uuidString)",
            isDirectory: false
        )

        try fileManager.moveItem(at: source, to: staging)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: staging
                )
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            // Не оставляем мусор в каталоге пользователя.
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}

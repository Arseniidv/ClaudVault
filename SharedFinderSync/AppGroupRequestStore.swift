import Foundation

/// Хранилище запросов Radial Menu в App Group.
///
/// Finder Sync Extension пишет JSON-файл с `RadialMenuRequest`,
/// основное приложение читает его по `id` из deep link
/// `claudvault://radial/open?request=<uuid>` и удаляет.
/// Запросы старше `requestLifetime` считаются протухшими
/// и удаляются при каждой записи/чтении.
enum AppGroupRequestStore {

    static let appGroupID = "group.com.Arseniidv.ClaudVault"
    static let requestDirectoryName = "RadialMenuRequests"
    /// Запрос живёт недолго: если приложение не подобрало его
    /// за 5 минут (например, было закрыто), он считается мусором.
    static let requestLifetime: TimeInterval = 300

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
    }

    static func requestsDirectoryURL() -> URL? {
        guard let container = containerURL else { return nil }
        let directory = container.appendingPathComponent(
            requestDirectoryName,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    /// Сохраняет запрос и возвращает URL файла. `nil` — App Group
    /// недоступен (например, entitlement не выдан при разработке).
    @discardableResult
    static func write(_ request: RadialMenuRequest) -> URL? {
        guard let directory = requestsDirectoryURL() else { return nil }
        cleanupExpiredRequests(in: directory)

        let fileURL = directory.appendingPathComponent(
            "\(request.id.uuidString).json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(request) else { return nil }
        try? data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Читает и удаляет запрос по идентификатору. `nil` — запрос
    /// не найден, повреждён или протух.
    static func consume(id: UUID) -> RadialMenuRequest? {
        guard let directory = requestsDirectoryURL() else { return nil }
        let fileURL = directory.appendingPathComponent(
            "\(id.uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let request = try? decoder.decode(
            RadialMenuRequest.self,
            from: data
        ) else { return nil }

        guard Date().timeIntervalSince(request.createdAt)
            <= requestLifetime else { return nil }
        return request
    }

    /// Удаляет все файлы запросов старше `requestLifetime`.
    static func cleanupExpiredRequests() {
        guard let directory = requestsDirectoryURL() else { return }
        cleanupExpiredRequests(in: directory)
    }

    private static func cleanupExpiredRequests(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-requestLifetime)
        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

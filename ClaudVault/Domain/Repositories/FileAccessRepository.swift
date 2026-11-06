import Foundation

protocol FileAccessRepository {
    func withAccess<T>(
        to url: URL,
        perform operation: (URL) throws -> T
    ) throws -> T
}

extension FileAccessRepository {
    /// Создаёт bookmark для файла, доступ к которому уже получен
    /// (например, через fileImporter). Bookmark можно сохранить и
    /// позже восстановить URL через `urlForBookmark`.
    /// Security-scope сам по себе не сохраняется в bookmark —
    /// доступ возобновляется через `startAccessingSecurityScopedResource`.
    func makeSecurityScopedBookmark(for url: URL) throws -> Data {
        try withAccess(to: url) { accessibleURL in
            try accessibleURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    /// Восстанавливает URL из сохранённого bookmark.
    func urlForBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }

    /// Удобная обёртка: bookmark (base64) -> URL.
    func urlForBookmark(base64: String) throws -> URL {
        guard let data = Data(base64Encoded: base64) else {
            throw FileAccessError.invalidURL
        }
        return try urlForBookmark(data)
    }
}

enum FileAccessError: LocalizedError {
    case coordinationFailed
    case fileNotFound
    case accessDenied
    case invalidFile
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .coordinationFailed:
            return "Не удалось получить доступ к файлу."
        case .fileNotFound:
            return "Не удалось обнаружить файл"
        case .invalidFile:
            return "Файл поврежден"
        case .invalidURL:
            return "ссылка повреждена "
        case .accessDenied:
            return "Доступ запрещен"
        }
    }
}

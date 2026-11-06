import Foundation

final class LocalFileAccess: FileAccessRepository {

    func withAccess<T>(
        to url: URL,
        perform operation: (URL) throws -> T
    ) throws -> T {

        let didStartAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)

        var coordinationError: NSError?
        var operationResult: Result<T, Error>?

        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            operationResult = Result {
                try operation(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let operationResult else {
            throw FileAccessError.coordinationFailed
        }

        return try operationResult.get()
    }
}

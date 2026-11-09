import XCTest
@testable import ClaudVault
import ClaudVaultDomain

/// Тесты явных состояний восстановления провайдеров:
/// `nil` от repository — это `unavailable`, а не успех,
/// а временная ошибка (`failed`) должна повторяться retry.
@MainActor
final class StoragesRestoreTests: XCTestCase {

    private let ownerID = "owner-\(UUID().uuidString)"

    override func tearDown() {
        CurrentUserContext.shared.set(nil)
        super.tearDown()
    }

    func testNilRestoreBecomesUnavailableAndIsNotRetried() async {
        CurrentUserContext.shared.set(ownerID)
        let repository = MockCloudRepository { nil }
        let viewModel = StoragesViewModel(
            repositories: [.dropbox: repository]
        )

        await viewModel.restoreConnection()

        let state = viewModel.state(for: .dropbox)
        XCTAssertEqual(state.restoreState, .unavailable)
        XCTAssertNil(state.account)
        XCTAssertEqual(repository.restoreCallCount, 1)

        // unavailable — терминальное состояние до reconnect/
        // token import: retry не должен крутиться по кругу.
        await viewModel.retryFailedRestores()
        XCTAssertEqual(repository.restoreCallCount, 1)
    }

    func testFailedRestoreIsRetriedUntilSuccess() async {
        CurrentUserContext.shared.set(ownerID)
        let account = CloudStorageAccount(
            id: "db-uid",
            email: "dropbox@example.com",
            displayName: "Dropbox"
        )
        var shouldFail = true
        let repository = MockCloudRepository {
            if shouldFail {
                throw CloudStorageError.network("offline")
            }
            return account
        }
        let viewModel = StoragesViewModel(
            repositories: [.dropbox: repository]
        )

        await viewModel.restoreConnection()
        XCTAssertEqual(
            viewModel.state(for: .dropbox).restoreState,
            .failed
        )
        XCTAssertEqual(repository.restoreCallCount, 1)

        shouldFail = false
        await viewModel.retryFailedRestores()

        let state = viewModel.state(for: .dropbox)
        XCTAssertEqual(state.restoreState, .restored)
        XCTAssertEqual(state.account, account)
        XCTAssertEqual(repository.restoreCallCount, 2)
    }

    func testRestoredProviderIsNotRestoredAgain() async {
        CurrentUserContext.shared.set(ownerID)
        let account = CloudStorageAccount(
            id: "db-uid",
            email: "dropbox@example.com",
            displayName: "Dropbox"
        )
        let repository = MockCloudRepository { account }
        let viewModel = StoragesViewModel(
            repositories: [.dropbox: repository]
        )

        await viewModel.restoreConnection()
        await viewModel.retryFailedRestores()

        XCTAssertEqual(repository.restoreCallCount, 1)
        XCTAssertEqual(
            viewModel.state(for: .dropbox).restoreState,
            .restored
        )
    }

    // MARK: - Mock

    private final class MockCloudRepository: CloudStorageRepository {
        private let handler: () async throws -> CloudStorageAccount?
        private(set) var restoreCallCount = 0

        init(handler: @escaping () async throws -> CloudStorageAccount?) {
            self.handler = handler
        }

        func restoreConnection() async throws -> CloudStorageAccount? {
            restoreCallCount += 1
            return try await handler()
        }

        func connect() async throws -> CloudStorageAccount {
            throw CloudStorageError.notImplemented
        }

        func signOut() async throws {}

        func getStorageUsage() async throws -> CloudStorageUsage {
            CloudStorageUsage(usedBytes: 0, totalBytes: 0, availableBytes: 0)
        }

        func listFiles(parentFolderID: String?) async throws -> [CloudFile] {
            []
        }

        func fileMetadata(id: String) async throws -> CloudFile {
            throw CloudStorageError.notFound
        }

        func createFolder(
            name: String,
            parentFolderID: String?
        ) async throws -> CloudFile {
            throw CloudStorageError.notImplemented
        }

        func uploadFile(
            at fileURL: URL,
            parentFolderID: String?,
            progressHandler: (@Sendable (Double) -> Void)?
        ) async throws -> CloudFile {
            throw CloudStorageError.notImplemented
        }

        func deleteFile(id: String) async throws {
            throw CloudStorageError.notImplemented
        }
    }
}

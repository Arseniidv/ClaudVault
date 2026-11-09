import XCTest
import SwiftData
import ClaudVaultDomain
@testable import ClaudVault


@MainActor
final class CreateBackupRecordUseCaseTests: XCTestCase {

    func testCreateAndFetchBackupRecord() throws {
        // Arrange
        let container = try CloudVaultModelContainer.make(
            inMemory: true
        )

        let repository = BackupMetadataRepositoryImpl(
            modelContext: container.mainContext
        )

        let createUseCase = CreateBackupRecordUseCase(
            repository: repository
        )

        let fetchUseCase = FetchBackupRecordsUseCase(
            repository: repository
        )

        // Act
        let createdRecord = try createUseCase.execute(
            fileName: "Documents.zip",
            sourceIdentifier: "local-file-001"
        )

        let records = try fetchUseCase.execute()

        // Assert
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, createdRecord.id)
        XCTAssertEqual(records.first?.fileName, "Documents.zip")
    }
}

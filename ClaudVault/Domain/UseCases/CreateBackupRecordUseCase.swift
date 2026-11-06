import Foundation
import SwiftUI

@MainActor
struct CreateBackupRecordUseCase {

    private let repository: BackupMetadataRepository

    init(repository: BackupMetadataRepository) {
        self.repository = repository
    }

    func execute(
        fileName: String,
        sourceIdentifier: String
    ) throws -> BackupRecord {
        let record = BackupRecord(
            id: UUID(),
            fileName: fileName,
            sourceIdentifier: sourceIdentifier,
            updatedAt: Date()
        )
        try repository.saveRecord(record)

        return record
    }
}
struct CreateBackupRecord:View {
    var body: some View {
        /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Hello, world!@*/Text("Hello, world!")/*@END_MENU_TOKEN@*/
    }
}

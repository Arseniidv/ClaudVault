import Foundation
import SwiftData

@MainActor
enum CloudVaultModelContainer {

    static func make(
        inMemory: Bool = false
    ) throws -> ModelContainer {

        let schema = Schema([
            BackupRecordModel.self,
            BackupVersionModel.self,
            UploadSessionModel.self,
            CloudFileModel.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            guard !inMemory else {
                throw error
            }

            let storeURL = configuration.url

            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    atPath: storeURL.path + suffix
                )
            }

            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        }
    }
}

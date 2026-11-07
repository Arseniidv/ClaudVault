import Foundation
import SwiftData

@MainActor
protocol BackupMetadataRepository {
    var modelContext:ModelContext{get}
    func fetchRecords() throws -> [BackupRecord]
    func fetchRecords(id: UUID) -> BackupRecord?
    func fetchRecord(bySource sourceIdentifier: String) throws -> BackupRecord?
    func deleteRecord(id: UUID) throws
    func saveVersion(_ version: BackupVersion) throws
    func saveVersion(_ version: BackupVersion, for recordID: UUID) throws
    /// Обновляет существующую версию (например, новый cloudObjectID
    /// после переноса между облаками). Если версии нет — ничего не делает.
    func updateVersion(_ version: BackupVersion) throws
    func deleteVersion(id: UUID) throws
    func saveRecord(_ record: BackupRecord) throws

    func fetchVersions(for recordID: UUID) throws -> [BackupVersion]
    func calculateUsedStorage() throws -> Int64
}
extension BackupMetadataRepository {
    func calculateUsedStorage() throws -> Int64 {
        let descriptor = FetchDescriptor<BackupVersionModel>()
        let versions = try modelContext.fetch(descriptor)

        return versions.reduce(Int64.zero) { total, version in
            total + version.fileSize
        }
    }
}
enum BackupMetadataRepositoryError: Error {
    case recordNotFound
}

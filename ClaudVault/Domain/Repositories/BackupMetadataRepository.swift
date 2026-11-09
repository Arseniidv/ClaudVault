import Foundation

/// Репозиторий метаданных резервных копий.
///
/// Платформенно-нейтральный протокол: iOS-реализация работает
/// поверх SwiftData (`BackupMetadataRepositoryImpl`), Android —
/// поверх SkipSQL/собственного хранилища.
///
/// `modelContext` намеренно не входит в протокол — он нужен
/// только SwiftData-реализации и остаётся деталью impl'а.
@MainActor
public protocol BackupMetadataRepository {
    func fetchRecords() throws -> [BackupRecord]
    func fetchRecords(id: UUID) -> BackupRecord?
    func fetchRecord(bySource sourceIdentifier: String) throws -> BackupRecord?
    func deleteRecord(id: UUID) throws
    func saveVersion(_ version: BackupVersion, for recordID: UUID) throws
    /// Обновляет существующую версию (например, новый cloudObjectID
    /// после переноса между облаками). Если версии нет — ничего не делает.
    func updateVersion(_ version: BackupVersion) throws
    func deleteVersion(id: UUID) throws
    func saveRecord(_ record: BackupRecord) throws

    func fetchVersions(for recordID: UUID) throws -> [BackupVersion]
    func calculateUsedStorage() throws -> Int64
}

public enum BackupMetadataRepositoryError: Error {
    case recordNotFound
}

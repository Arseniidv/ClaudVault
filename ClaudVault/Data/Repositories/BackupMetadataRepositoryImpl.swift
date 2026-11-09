import Foundation
import CryptoKit
import SwiftData

@MainActor
final class BackupMetadataRepositoryImpl: BackupMetadataRepository {
    internal let modelContext: ModelContext
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    func fetchRecord(bySource sourceIdentifier: String) throws -> BackupRecord? {
        let descriptor = FetchDescriptor<BackupRecordModel>(
            predicate: #Predicate { $0.sourceIdentifier == sourceIdentifier }
        )
        guard let model = try modelContext.fetch(descriptor).first else { return nil }
        return BackupModelMapper.toDomain(model)
    }
    
    func saveVersion(_ version: BackupVersion, for recordID: UUID) throws {
        let descriptor = FetchDescriptor<BackupRecordModel>(
            predicate: #Predicate { $0.id == recordID }
        )
        guard let recordModel = try modelContext.fetch(descriptor).first else {
            throw BackupMetadataRepositoryError.recordNotFound
        }
        
        let versionModel = BackupModelMapper.makeModel(
            from: version,
            backupRecord: recordModel
        )
        modelContext.insert(versionModel)
        try modelContext.save()
    }
    
    func updateVersion(_ version: BackupVersion) throws {
        let descriptor = FetchDescriptor<BackupVersionModel>(
            predicate: #Predicate { $0.id == version.id }
        )
        guard let model = try modelContext.fetch(descriptor).first else {
            return
        }
        model.fileSize = version.fileSize
        model.checksum = version.checksum
        model.cloudObjectID = version.cloudObjectID
        model.uploadedAt = version.uploadedAt
        try modelContext.save()
    }

    func deleteVersion(id: UUID) throws {
        let descriptor = FetchDescriptor<BackupVersionModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(model)
        try modelContext.save()
    }
    
    func fetchRecords(id: UUID) -> BackupRecord? {
        return try? fetchRecord(id: id)
    }
    
    func fetchVersion(for recordID: UUID) throws -> [BackupVersion] {
        return try fetchVersions(for: recordID)
    }
 
    func fetchRecords() throws -> [BackupRecord] {
        let descriptor = FetchDescriptor<BackupRecordModel>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let models = try modelContext.fetch(descriptor)
        return models.map { BackupModelMapper.toDomain($0) }
    }
    
    func calculateUsedStorage() throws -> Int64 {
        let descriptor = FetchDescriptor<BackupVersionModel>()
        let versions = try modelContext.fetch(descriptor)

        return versions.reduce(Int64.zero) { total, version in
            total + version.fileSize
        }
    }

    func fetchRecord(id: UUID) throws -> BackupRecord? {
        let descriptor = FetchDescriptor<BackupRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else { return nil }
        return BackupModelMapper.toDomain(model)
    }
    

    func saveRecord(_ record: BackupRecord) throws {
        let recordID = record.id
        let descriptor = FetchDescriptor<BackupRecordModel>(
            predicate: #Predicate { $0.id == recordID }
        )
        if let existingModel = try modelContext.fetch(descriptor).first {
            BackupModelMapper.update(existingModel, from: record)
        } else {
            let newModel = BackupModelMapper.makeModel(from: record)
            modelContext.insert(newModel)
        }
        try modelContext.save()
    }

    func deleteRecord(id: UUID) throws {
        let descriptor = FetchDescriptor<BackupRecordModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try modelContext.fetch(descriptor).first else { return }
        modelContext.delete(model)
        try modelContext.save()
    }
    
    // MARK: - Backup Versions
    
    func saveVersion(_ version: BackupVersion) throws {
        // Перенаправляем логику в новый протокольный метод, чтобы не дублировать код
        try saveVersion(version, for: version.backupRecordID)
    }
    
    func fetchVersions(for recordID: UUID) throws -> [BackupVersion] {
        let descriptor = FetchDescriptor<BackupRecordModel>(
            predicate: #Predicate { $0.id == recordID }
        )
        
        guard let recordModel = try modelContext.fetch(descriptor).first else {
            throw BackupMetadataRepositoryError.recordNotFound
        }
        
        return recordModel.versions
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { BackupModelMapper.toDomain($0) }
    }
   
}

extension BackupMetadataRepositoryImpl: FileAccessRepository, FileHashing {
    nonisolated func hashFile(at url: URL) throws -> String {
        return try sha256(of: url)
    }


    // MARK: - File Access

    nonisolated func withAccess<T>(
        to url: URL,
        perform operation: (URL) throws -> T
    ) throws -> T {

        guard url.isFileURL else {
            throw FileAccessError.invalidURL
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation(url)
    }

    func accessFile(at url: URL) throws {
        try withAccess(to: url) { accessibleURL in
            guard FileManager.default.fileExists(
                atPath: accessibleURL.path
            ) else {
                throw FileAccessError.fileNotFound
            }
            let resourceValues = try accessibleURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey
                ]
            )
            guard resourceValues.isRegularFile == true ||
                    resourceValues.isDirectory == true else {
                throw FileAccessError.invalidFile
            }
            guard FileManager.default.isReadableFile(
                atPath: accessibleURL.path
            ) else {
                throw FileAccessError.accessDenied
            }
        }
    }
    
    nonisolated func sha256(of fileURL: URL) throws -> String {
        return try withAccess(to: fileURL) { accessibleURL in
            guard FileManager.default.fileExists(
                atPath: accessibleURL.path
            ) else {
                throw FileAccessError.fileNotFound
            }
            let fileHandle = try FileHandle(
                forReadingFrom: accessibleURL
            )
            defer {
                try? fileHandle.close()
            }
            var hasher = SHA256()
            let chunkSize = 1_048_576
            
            while let data = try fileHandle.read(
                upToCount: chunkSize
            ), !data.isEmpty {
                
                hasher.update(data: data)
            }
            let digest = hasher.finalize()
            return digest
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }
    
    func calculateHashing(for url: URL) -> String {
        do {
            return try sha256(of: url)
        } catch {
            #if DEBUG
            print("SHA-256 calculation failed: \(error)")
            #endif
            return ""
        }
    }
}

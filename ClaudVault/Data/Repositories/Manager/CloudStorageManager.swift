import Foundation
import CloudKit

final class CloudStorageManager {

    private let container: CKContainer
    private let database: CKDatabase
    var errorMessage = ""
    private let recordType = "BackupFile"

    init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    // MARK: - Upload

    func uploadFile(
        from localURL: URL,
        to remotePath: String
    ) async throws -> CloudStorageItem {

        let record = CKRecord(recordType: recordType)

        record["name"] = localURL.lastPathComponent
        record["path"] = remotePath
        record["file"] = CKAsset(fileURL: localURL)
        record["size"] = try localURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize as NSNumber?

        let savedRecord = try await database.save(record)

        return CloudStorageItem(
            id: savedRecord.recordID.recordName,
            name: localURL.lastPathComponent,
            path: remotePath,
            size: Int64(
                (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            ),
            modifireAt: savedRecord.modificationDate
        )
    }

    // MARK: - Download

    func downloadFile(
        withID fileID: String,
        to localURL: URL
    ) async throws {

        let recordID = CKRecord.ID(recordName: fileID)

        let record = try await database.record(for: recordID)

        guard let asset = record["file"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw ManagerError.fileNotFound
        }

        let fileManager = FileManager.default

        let directory = localURL.deletingLastPathComponent()

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        try fileManager.copyItem(
            at: assetURL,
            to: localURL
        )
    }

    // MARK: - List

    func listFiles(
        in remotePath: String
    ) async throws -> [CloudStorageItem] {

        let predicate = NSPredicate(
            format: "path == %@",
            remotePath
        )

        let query = CKQuery(
            recordType: recordType,
            predicate: predicate
        )

        let result = try await database.records(matching: query)

        return result.matchResults.compactMap { _, recordResult in
            guard case .success(let record) = recordResult else {
                return nil
            }

            return CloudStorageItem(
                id: record.recordID.recordName,
                name: record["name"] as? String ?? "",
                path: record["path"] as? String ?? "",
                size: (record["size"] as? NSNumber)?.int64Value ?? 0,
                modifireAt: record.modificationDate
            )
        }
    }
    func deleteFile(
        withID fileID: String
    ) async throws {

        let recordID = CKRecord.ID(recordName: fileID)

        try await database.deleteRecord(withID: recordID)
    }
    enum ManagerError: LocalizedError {
        case fileNotFound
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Файл не найден в CloudKit."
            }
        }
    }
}

// MARK: - Models

struct CloudStorageItem {
    let id: String 
    let name: String
    let path: String
    let size: Int64
    let modifireAt: Date?
}

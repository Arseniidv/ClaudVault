import Foundation
import ClaudVaultDomain

enum BackupModelMapper {

    static func toDomain(
        _ model: BackupRecordModel
    ) -> BackupRecord {

        BackupRecord(
            id: model.id,
            fileName: model.fileName,
            sourceIdentifier: model.sourceIdentifier,
            storageProvider: StorageProviderType(
                rawValue: model.storageProviderRaw ?? ""
            ) ?? .unknown,
            localFilePath: model.localFilePath,
            localFileBookmark: model.localFileBookmark,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    static func makeModel(
        from entity: BackupRecord
    ) -> BackupRecordModel {

        BackupRecordModel(
            id: entity.id,
            fileName: entity.fileName,
            sourceIdentifier: entity.sourceIdentifier,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            storageProviderRaw: entity.storageProvider.rawValue,
            localFilePath: entity.localFilePath,
            localFileBookmark: entity.localFileBookmark
        )
    }

    static func update(
        _ model: BackupRecordModel,
        from entity: BackupRecord
    ) {
        model.fileName = entity.fileName
        model.sourceIdentifier = entity.sourceIdentifier
        model.storageProviderRaw = entity.storageProvider.rawValue
        model.localFilePath = entity.localFilePath
        model.localFileBookmark = entity.localFileBookmark
        model.updatedAt = entity.updatedAt
    }

    static func toDomain(
        _ model: BackupVersionModel
    ) -> BackupVersion {

        BackupVersion(
            id: model.id,
            backupRecordID: model.backupRecord?.id ?? UUID(),
            fileSize: model.fileSize,
            checksum: model.checksum,
            cloudObjectID: model.cloudObjectID,
            uploadedAt: model.uploadedAt
        )
    }

    static func makeModel(
        from entity: BackupVersion,
        backupRecord: BackupRecordModel
    ) -> BackupVersionModel {

        BackupVersionModel(
            id: entity.id,
            fileSize: entity.fileSize,
            checksum: entity.checksum,
            cloudObjectID: entity.cloudObjectID,
            uploadedAt: entity.uploadedAt,
            backupRecord: backupRecord,
            ownerID: backupRecord.ownerID
        )
    }
}

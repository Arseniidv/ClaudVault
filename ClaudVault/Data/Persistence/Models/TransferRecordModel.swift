import Foundation
import SwiftData
import ClaudVaultDomain

/// SwiftData-модель журнала chunked-передач.
/// Хранит смещение и состояние сессии для возобновления
/// после перезапуска приложения.
@Model
final class TransferRecordModel {

    @Attribute(.unique)
    var id: UUID

    var kindRaw: String
    var sourceProvider: String
    var sourceFileID: String
    var sourceFilePath: String
    var targetProvider: String
    var targetParentID: String
    var name: String
    var mimeType: String
    var sizeBytes: Int64
    var offset: Int64
    var sessionState: String
    var expectedHashAlgorithm: String
    var expectedHashValue: String
    var streamSHA256: String
    var stateRaw: String
    var moveSource: Bool
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    /// Владелец записи — пользователь CloudVault.
    var ownerID: String

    init(record: TransferRecord) {
        self.id = record.id
        self.kindRaw = record.kind.rawValue
        self.sourceProvider = record.sourceProvider
        self.sourceFileID = record.sourceFileID
        self.sourceFilePath = record.sourceFilePath
        self.targetProvider = record.targetProvider
        self.targetParentID = record.targetParentID
        self.name = record.name
        self.mimeType = record.mimeType
        self.sizeBytes = record.sizeBytes
        self.offset = record.offset
        self.sessionState = record.sessionState
        self.expectedHashAlgorithm = record.expectedHashAlgorithm
        self.expectedHashValue = record.expectedHashValue
        self.streamSHA256 = record.streamSHA256
        self.stateRaw = record.state.rawValue
        self.moveSource = record.moveSource
        self.errorMessage = record.errorMessage
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
        self.ownerID = CurrentUserContext.shared.ownerID ?? ""
    }

    func asRecord() -> TransferRecord {
        TransferRecord(
            id: id,
            kind: TransferRecord.Kind(rawValue: kindRaw) ?? .upload,
            sourceProvider: sourceProvider,
            sourceFileID: sourceFileID,
            sourceFilePath: sourceFilePath,
            targetProvider: targetProvider,
            targetParentID: targetParentID,
            name: name,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            offset: offset,
            sessionState: sessionState,
            expectedHashAlgorithm: expectedHashAlgorithm,
            expectedHashValue: expectedHashValue,
            streamSHA256: streamSHA256,
            state: TransferRecord.State(rawValue: stateRaw) ?? .pending,
            moveSource: moveSource,
            errorMessage: errorMessage,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(_ record: TransferRecord) {
        kindRaw = record.kind.rawValue
        sourceProvider = record.sourceProvider
        sourceFileID = record.sourceFileID
        sourceFilePath = record.sourceFilePath
        targetProvider = record.targetProvider
        targetParentID = record.targetParentID
        name = record.name
        mimeType = record.mimeType
        sizeBytes = record.sizeBytes
        offset = record.offset
        sessionState = record.sessionState
        expectedHashAlgorithm = record.expectedHashAlgorithm
        expectedHashValue = record.expectedHashValue
        streamSHA256 = record.streamSHA256
        stateRaw = record.state.rawValue
        moveSource = record.moveSource
        errorMessage = record.errorMessage
        updatedAt = record.updatedAt
    }
}

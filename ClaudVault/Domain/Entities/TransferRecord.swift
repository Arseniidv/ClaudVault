import Foundation

/// Запись журнала передач: позволяет возобновить chunked-загрузку
/// после перезапуска приложения и обеспечивает идемпотентность
/// по `id` (UUID генерируется до старта передачи).
public struct TransferRecord: Identifiable, Equatable {
    public enum Kind: String, Equatable {
        /// Локальный файл → облако.
        case upload
        /// Облако → облако.
        case cloudTransfer
    }

    public enum State: String, Equatable {
        case pending
        case uploading
        case verifying
        case completed
        case failed
        case cancelled
    }

    public let id: UUID
    public var kind: Kind
    /// `StorageProviderType.rawValue` источника; пусто — локальный файл.
    public var sourceProvider: String
    /// ID файла в облаке-источнике (для cloudTransfer).
    public var sourceFileID: String
    /// Путь к локальному файлу-источнику (для upload).
    public var sourceFilePath: String
    /// `StorageProviderType.rawValue` приёмника.
    public var targetProvider: String
    /// ID папки-приёмника (пусто — корень).
    public var targetParentID: String
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int64
    /// Подтверждённое провайдером смещение (байт).
    public var offset: Int64
    /// Сериализованное состояние сессии приёмника
    /// (session URL / sessionId / uploadUrl). Без токенов.
    public var sessionState: String
    /// Ожидаемый хеш содержимого (когда вычислим/известен).
    public var expectedHashAlgorithm: String
    public var expectedHashValue: String
    /// SHA-256 потока, прочитанного источником (контроль целостности передачи).
    public var streamSHA256: String
    public var state: State
    /// При move — удалять источник только после верификации.
    public var moveSource: Bool
    public var errorMessage: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        sourceProvider: String = "",
        sourceFileID: String = "",
        sourceFilePath: String = "",
        targetProvider: String,
        targetParentID: String = "",
        name: String,
        mimeType: String,
        sizeBytes: Int64,
        offset: Int64 = 0,
        sessionState: String = "",
        expectedHashAlgorithm: String = "",
        expectedHashValue: String = "",
        streamSHA256: String = "",
        state: State = .pending,
        moveSource: Bool = false,
        errorMessage: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.sourceProvider = sourceProvider
        self.sourceFileID = sourceFileID
        self.sourceFilePath = sourceFilePath
        self.targetProvider = targetProvider
        self.targetParentID = targetParentID
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.offset = offset
        self.sessionState = sessionState
        self.expectedHashAlgorithm = expectedHashAlgorithm
        self.expectedHashValue = expectedHashValue
        self.streamSHA256 = streamSHA256
        self.state = state
        self.moveSource = moveSource
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

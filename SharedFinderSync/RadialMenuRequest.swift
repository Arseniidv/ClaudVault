import Foundation

struct RadialMenuRequest: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case finderSync
        case services
        case accessibility
        case dragAndDrop
        case clipboard
    }

    let id: UUID
    let source: Source
    let fileURLs: [URL]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        source: Source,
        fileURLs: [URL],
        createdAt: Date = .now
    ) {
        self.id = id
        self.source = source
        self.fileURLs = fileURLs
        self.createdAt = createdAt
    }
}

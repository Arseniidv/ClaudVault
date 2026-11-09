import Foundation

public struct AuthUser:Identifiable,Equatable{
    public let id:UUID
    public let email:String
    public let displayName:String?
    public let emailVerified:Bool

    public init(id: UUID, email: String, displayName: String?, emailVerified: Bool) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.emailVerified = emailVerified
    }
}

extension AuthUser {
    public var resolvedDisplayName: String {
        if let displayName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }

        let localPart = email
            .split(separator: "@")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return localPart.isEmpty ? "Пользователь" : localPart
    }

    public var resolvedEmail: String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? "—" : trimmedEmail
    }
}

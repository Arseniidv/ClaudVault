import Foundation

struct AuthUser:Identifiable,Equatable{
    let id:UUID
    let email:String
    let displayName:String?
    let emailVerified:Bool
}

extension AuthUser {
    var resolvedDisplayName: String {
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

    var resolvedEmail: String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? "—" : trimmedEmail
    }
}

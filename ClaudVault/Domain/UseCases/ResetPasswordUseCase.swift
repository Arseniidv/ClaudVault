import Foundation

public struct ResetPasswordUseCase{
    public let repository:AuthRepository
    
    public init(repository: AuthRepository) {
        self.repository = repository
    }
    public func execute(email:String) async throws{
        try await repository.resetPassword(email: email)
    }
}

import Foundation

public struct SignUpUseCase{
    private let repository :AuthRepository
    
    public init(repository: AuthRepository) {
        self.repository = repository
    }
    public func execute(
        name:String,
        email:String,
        password:String
    ) async throws -> AuthUser{
        try await repository.signUp(
            name:name,
            email: email,
            password: password
        )
    }
}

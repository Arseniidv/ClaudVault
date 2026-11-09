import Foundation

public struct SignInUseCase{
    private let repository:AuthRepository
    public init(repository: AuthRepository) {
        self.repository = repository
    }
    public func execute(
        email:String,
        password: String
    ) async throws -> AuthUser{
        try await repository.signIn(email: email, password: password)
    }
}

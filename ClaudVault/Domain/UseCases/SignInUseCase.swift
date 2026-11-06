import Foundation

struct SignInUseCase{
    private let repository:AuthRepository
    init(repository: AuthRepository) {
        self.repository = repository
    }
    func execute(
        email:String,
        password: String
    ) async throws -> AuthUser{
        try await repository.signIn(email: email, password: password)
    }
}

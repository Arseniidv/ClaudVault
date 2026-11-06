import Foundation

struct SignUpUseCase{
    private let repository :AuthRepository
    
    init(repository: AuthRepository) {
        self.repository = repository
    }
    func execute(
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

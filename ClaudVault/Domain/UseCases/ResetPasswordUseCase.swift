import Foundation

struct ResetPasswordUseCase{
    let repository:AuthRepository
    
    init(repository: AuthRepository) {
        self.repository = repository
    }
    func execute(email:String) async throws{
        try await repository.resetPassword(email: email)
    }
}

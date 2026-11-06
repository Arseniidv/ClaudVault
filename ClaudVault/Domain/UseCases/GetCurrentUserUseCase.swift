import Foundation

struct GetCurrentUserUseCase{
    private let repository:AuthRepository
    
    init(repository: AuthRepository) {
        self.repository = repository
    }
    
    func execute()  async  -> AuthUser? {
        await repository.getCurrentUser()
    }
    func observeAuthState()->AsyncStream<AuthUser?>{
        repository.authStateChanges()
    }
}

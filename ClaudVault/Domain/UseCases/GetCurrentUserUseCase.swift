import Foundation

public struct GetCurrentUserUseCase{
    private let repository:AuthRepository
    
    public init(repository: AuthRepository) {
        self.repository = repository
    }
    
    public func execute()  async  -> AuthUser? {
        await repository.getCurrentUser()
    }
    public func observeAuthState()->AsyncStream<AuthUser?>{
        repository.authStateChanges()
    }
}

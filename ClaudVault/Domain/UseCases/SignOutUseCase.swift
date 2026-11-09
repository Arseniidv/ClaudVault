import Foundation

public struct SignOutUseCase{
    private let  repository:AuthRepository
    
    public init(repository: AuthRepository) {
        self.repository = repository
    }
    public func execute() async throws{
        try await repository.signOut()
    }
}

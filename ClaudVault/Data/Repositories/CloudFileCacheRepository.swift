import Foundation
import SwiftData
import ClaudVaultDomain

/// Кэш листингов облачных папок в SwiftData.
/// При каждом успешном `listFiles` содержимое папки
/// перезаписывается; при навигации UI сначала показывает
/// кэш, затем подменяет данными сети.
@MainActor
final class CloudFileCacheRepository {

    private let modelContext: ModelContext

    /// Владелец данных; nil — сеанса нет, кэш пуст.
    private var ownerID: String? {
        CurrentUserContext.shared.ownerID
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Полностью заменяет кэш папки свежим листингом.
    func save(
        files: [CloudFile],
        provider: StorageProviderType,
        parentFolderID: String
    ) {
        let key = parentFolderID
        let providerRaw = provider.rawValue
        guard let ownerID else { return }

        let descriptor = FetchDescriptor<CloudFileModel>(
            predicate: #Predicate {
                $0.provider == providerRaw
                    && $0.parentFolderID == key
                    && $0.ownerID == ownerID
            }
        )
        if let stale = try? modelContext.fetch(descriptor) {
            for model in stale {
                modelContext.delete(model)
            }
        }

        for file in files {
            let model = CloudFileModel.make(
                from: file,
                provider: providerRaw,
                parentFolderID: key
            )
            model.ownerID = ownerID
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    func fetch(
        provider: StorageProviderType,
        parentFolderID: String
    ) -> [CloudFile] {
        guard let ownerID else { return [] }
        let descriptor = FetchDescriptor<CloudFileModel>(
            predicate: #Predicate {
                $0.provider == provider.rawValue
                    && $0.parentFolderID == parentFolderID
                    && $0.ownerID == ownerID
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor))?
            .map { $0.asCloudFile() } ?? []
    }

    func clear(provider: StorageProviderType) {
        guard let ownerID else { return }
        let descriptor = FetchDescriptor<CloudFileModel>(
            predicate: #Predicate {
                $0.provider == provider.rawValue && $0.ownerID == ownerID
            }
        )
        if let stale = try? modelContext.fetch(descriptor) {
            for model in stale {
                modelContext.delete(model)
            }
            try? modelContext.save()
        }
    }
}

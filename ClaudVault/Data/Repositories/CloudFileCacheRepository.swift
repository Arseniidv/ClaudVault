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

        let descriptor = FetchDescriptor<CloudFileModel>(
            predicate: #Predicate {
                $0.provider == providerRaw && $0.parentFolderID == key
            }
        )
        if let stale = try? modelContext.fetch(descriptor) {
            for model in stale {
                modelContext.delete(model)
            }
        }

        for file in files {
            modelContext.insert(
                CloudFileModel.make(
                    from: file,
                    provider: providerRaw,
                    parentFolderID: key
                )
            )
        }
        try? modelContext.save()
    }

    func fetch(
        provider: StorageProviderType,
        parentFolderID: String
    ) -> [CloudFile] {
        let descriptor = FetchDescriptor<CloudFileModel>(
            predicate: #Predicate {
                $0.provider == provider.rawValue
                    && $0.parentFolderID == parentFolderID
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor))?
            .map { $0.asCloudFile() } ?? []
    }

    func clear(provider: StorageProviderType) {
        let descriptor = FetchDescriptor<CloudFileModel>(
            predicate: #Predicate { $0.provider == provider.rawValue }
        )
        if let stale = try? modelContext.fetch(descriptor) {
            for model in stale {
                modelContext.delete(model)
            }
            try? modelContext.save()
        }
    }
}

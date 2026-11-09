import SwiftUI
import Kingfisher

enum CloudThumbnailError: Error {
    case noPreview
}

/// Kingfisher-провайдер миниатюр облачных файлов.
/// Тянет изображение через `CloudStorageRepository.thumbnailData`
/// и кэширует результат в дисковом кэше Kingfisher —
/// исходники в память не попадают.
final class CloudThumbnailProvider: ImageDataProvider {
    let cacheKey: String
    private let load: @Sendable () async throws -> Data?

    init(
        cacheKey: String,
        load: @escaping @Sendable () async throws -> Data?
    ) {
        self.cacheKey = cacheKey
        self.load = load
    }

    func imageData(handler: @escaping (Result<Data, Error>) -> Void) {
        Task {
            do {
                if let data = try await load() {
                    handler(.success(data))
                } else {
                    handler(.failure(CloudThumbnailError.noPreview))
                }
            } catch {
                handler(.failure(error))
            }
        }
    }
}

/// Миниатюра файла в списке: для изображений — превью из облака
/// через Kingfisher, для остальных типов — иконка по mimeType.
struct CloudThumbnailView: View {
    let file: CloudFile
    /// nil — провайдер не поддерживает превью, показываем иконку.
    let provider: CloudThumbnailProvider?

    private var isImage: Bool {
        file.mimeType.hasPrefix("image/")
    }

    var body: some View {
        Group {
            if isImage, let provider {
                KFImage(source: .provider(provider))
                    .placeholder { thumbnailPlaceholder }
                    .fade(duration: 0.2)
                    .scaledToFill()
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(Color.primary.opacity(0.06))
    }

    private var thumbnailPlaceholder: some View {
        Image(systemName: iconName)
            .font(.system(size: 17))
            .foregroundStyle(iconColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconName: String {
        if file.isFolder { return "folder.fill" }
        if file.mimeType.hasPrefix("audio/") { return "music.note" }
        if file.mimeType.hasPrefix("video/") { return "film" }
        if file.mimeType.hasPrefix("image/") { return "photo" }
        return "doc.fill"
    }

    private var iconColor: Color {
        if file.isFolder { return .orange }
        if file.mimeType.hasPrefix("audio/") { return .pink }
        if file.mimeType.hasPrefix("video/") { return .purple }
        if file.mimeType.hasPrefix("image/") { return .green }
        return .blue
    }
}

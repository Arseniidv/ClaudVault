import Foundation
import Observation
import ClaudVaultDomain

/// Состояние подготовки предпросмотра облачного файла.
///
/// Для аудио/видео сначала пробуется потоковая ссылка
/// (`streamDescriptor`) — большой файл не скачивается целиком.
/// Если провайдер не поддерживает стриминг, файл скачивается
/// во временную папку через `downloadForPreview` и играется
/// локально. Для документов файл всегда скачивается.
///
/// Временная копия удаляется в `cleanup()` при закрытии preview —
/// оригинал в облаке не изменяется.
@MainActor
@Observable
final class FilePreviewViewModel {

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let item: FilePreviewItem
    let kind: FilePreviewKind

    private(set) var phase: Phase = .loading
    /// Потоковый дескриптор для аудио/видео (без скачивания).
    private(set) var mediaStream: CloudMediaStream?
    /// Локальная копия файла во временной папке.
    private(set) var localFileURL: URL?
    /// Временная папка, созданная `downloadForPreview` —
    /// удаляется целиком при закрытии.
    private var tempDirectoryURL: URL?

    init(item: FilePreviewItem) {
        self.item = item
        self.kind = FilePreviewKind(file: item.file)
    }

    var file: CloudFile { item.file }
    var provider: StorageProviderType { item.provider }

    func load(storagesViewModel: StoragesViewModel) async {
        phase = .loading
        do {
            switch kind {
            case .audio:
                // Аудио не скачиваем во временную папку:
                // трек передаётся в AudioPlayerService, а его
                // AudioSourceResolver сам выберет кэш/стриминг/
                // скачивание в постоянный кэш AudioCache.
                // Временная копия удалилась бы при закрытии
                // preview и оборвала бы воспроизведение.
                try await loadAudioMedia(storagesViewModel: storagesViewModel)
            case .video:
                try await loadMedia(storagesViewModel: storagesViewModel)
            case .pdf, .document, .text, .unsupported:
                try await downloadLocal(storagesViewModel: storagesViewModel)
            }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Аудио/видео: прямой стриминг, при недоступности — скачивание.
    private func loadMedia(storagesViewModel: StoragesViewModel) async throws {
        if let stream = try? await storagesViewModel.mediaStream(
            for: file,
            provider: provider
        ) {
            mediaStream = stream
            return
        }
        try await downloadLocal(storagesViewModel: storagesViewModel)
    }

    /// Аудио: только попытка получить потоковый дескриптор.
    /// Неуспех не фатален — `AudioSourceResolver` в плеере
    /// повторит резолв и при необходимости скачает файл
    /// в кэш `AudioCache`.
    private func loadAudioMedia(storagesViewModel: StoragesViewModel) async throws {
        if let stream = try? await storagesViewModel.mediaStream(
            for: file,
            provider: provider
        ) {
            mediaStream = stream
        }
    }

    private func downloadLocal(storagesViewModel: StoragesViewModel) async throws {
        let url = try await storagesViewModel.downloadForPreview(
            file,
            provider: provider
        )
        tempDirectoryURL = url.deletingLastPathComponent()
        localFileURL = url
    }

    /// Освобождает временные ресурсы: удаляет скачанную копию
    /// и сбрасывает плеерные дескрипторы.
    func cleanup() {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        localFileURL = nil
        mediaStream = nil
        phase = .loading
    }
}

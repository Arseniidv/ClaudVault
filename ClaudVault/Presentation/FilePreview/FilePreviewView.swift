import SwiftUI

/// Главный экран предпросмотра облачного файла.
/// Открывается по long press на файле; тап по строке сохраняет
/// прежнее поведение списка.
///
/// Внутри — навигация по типу файла (`FilePreviewKind`):
/// PDF → PDFKit, аудио/видео → AVKit/AVFoundation,
/// документы → QuickLook/ODT-текст, текст → текстовый вид,
/// остальное → заглушка с «Открыть в приложении».
@MainActor
struct FilePreviewView: View {
    let item: FilePreviewItem
    let storagesViewModel: StoragesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FilePreviewViewModel

    init(item: FilePreviewItem, storagesViewModel: StoragesViewModel) {
        self.item = item
        self.storagesViewModel = storagesViewModel
        _viewModel = State(initialValue: FilePreviewViewModel(item: item))
    }

    private var file: CloudFile { item.file }
    private var provider: StorageProviderType { item.provider }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.047, blue: 0.075)
                    .ignoresSafeArea()

                content
            }
            .navigationTitle(file.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(file.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(provider.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .task {
            await viewModel.load(storagesViewModel: storagesViewModel)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            loadingView
        case .failed(let message):
            failedView(message)
        case .ready:
            readyContent
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)

            VStack(spacing: 4) {
                Text("Подготовка предпросмотра…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)

                if let size = file.sizeBytes {
                    Text(ByteFormatting.string(fromByteCount: size))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange.opacity(0.8))

            VStack(spacing: 6) {
                Text("Не удалось открыть файл")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 12) {
                Button("Повторить") {
                    Task {
                        await viewModel.load(
                            storagesViewModel: storagesViewModel
                        )
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Color.blue.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let url = viewModel.localFileURL {
                    OpenExternallyButton(url: url)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Spacer()
        }
    }

    // MARK: - Ready content

    @ViewBuilder
    private var readyContent: some View {
        switch viewModel.kind {
        case .pdf:
            if let url = viewModel.localFileURL {
                PDFPreviewView(url: url)
            } else {
                missingContent
            }
        case .audio:
            AudioPreviewView(
                item: item,
                stream: viewModel.mediaStream
            )
        case .video:
            VideoPreviewView(
                stream: viewModel.mediaStream,
                localFileURL: viewModel.localFileURL
            )
        case .document:
            if let url = viewModel.localFileURL {
                DocumentPreviewView(url: url, fileName: file.name)
            } else {
                missingContent
            }
        case .text:
            if let url = viewModel.localFileURL {
                DocumentPreviewView(url: url, fileName: file.name)
            } else {
                missingContent
            }
        case .unsupported:
            if let url = viewModel.localFileURL {
                UnsupportedPreviewView(url: url, fileName: file.name)
            } else {
                missingContent
            }
        }
    }

    private var missingContent: some View {
        PreviewMessageView(
            icon: "questionmark.folder",
            title: "Содержимое недоступно",
            message: "Файл не был загружен. Попробуйте повторить позже."
        )
    }
}

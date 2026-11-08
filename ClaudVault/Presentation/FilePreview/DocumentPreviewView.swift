import SwiftUI

/// Предпросмотр текстовых документов:
/// - ODT — извлечение текста из `content.xml` (QuickLook ODT не умеет);
/// - DOC/DOCX/RTF и прочие офисные форматы — QuickLook;
/// - TXT/MD/JSON — читаемый текст с монospace-шрифтом.
struct DocumentPreviewView: View {
    let url: URL
    let fileName: String

    private var pathExtension: String {
        url.pathExtension.lowercased()
    }

    var body: some View {
        Group {
            if pathExtension == "odt" {
                odtContent
            } else if isPlainTextExtension {
                TextPreviewView(url: url)
            } else {
                QuickLookPreview(url: url)
            }
        }
        .background(Color(red: 0.035, green: 0.047, blue: 0.075).ignoresSafeArea())
    }

    private var isPlainTextExtension: Bool {
        ["txt", "md", "markdown", "json", "xml", "yaml", "yml",
         "csv", "tsv", "log"].contains(pathExtension)
    }

    @ViewBuilder
    private var odtContent: some View {
        if let text = OdtTextExtractor.text(from: url), !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
        } else {
            // Fallback: если извлечь текст не удалось — пробуем QuickLook,
            // а при полном провале показываем заглушку с внешним открытием.
            QuickLookPreview(url: url)
        }
    }
}

/// Простой текстовый просмотр: читает начало файла (до 4 МБ),
/// не загружая весь документ в память.
private struct TextPreviewView: View {
    let url: URL

    @State private var text: String?
    @State private var isTruncated = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let text {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        if isTruncated {
                            Text("Показано начало файла (4 МБ).")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .padding(16)
                }
            } else if loadFailed {
                PreviewMessageView(
                    icon: "doc.questionmark",
                    title: "Не удалось прочитать файл",
                    message: "Файл повреждён или имеет неподдерживаемую кодировку."
                )
            } else {
                ProgressView().tint(.white)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let maxBytes = 4 * 1024 * 1024
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var data = Data()
            while data.count < maxBytes,
                  let chunk = try handle.read(upToCount: 256 * 1024),
                  !chunk.isEmpty {
                data.append(chunk)
            }
            let offset = (try? handle.offset()) ?? 0
            isTruncated = offset >= UInt64(maxBytes)

            // String(decoding:as:) заменяет битые байты на U+FFFD —
            // файл с неизвестной кодировкой всё равно покажется.
            text = String(decoding: data, as: UTF8.self)
        } catch {
            loadFailed = true
        }
    }
}

/// Заглушка для неподдерживаемых форматов: иконка, пояснение
/// и кнопка «Открыть в приложении» (QuickLook «Open In» на iOS,
/// `NSWorkspace` на macOS). Файл в облаке не изменяется.
struct UnsupportedPreviewView: View {
    let url: URL
    let fileName: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.4))

            VStack(spacing: 6) {
                Text("Предпросмотр недоступен")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text(fileName)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("Формат этого файла не поддерживается для встроенного просмотра. Его можно открыть в другом приложении.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
            }

            OpenExternallyButton(url: url)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(red: 0.035, green: 0.047, blue: 0.075).ignoresSafeArea())
    }
}

/// Кнопка «Открыть в приложении»: на iOS показывает системное
/// меню «Открыть в…» (UIDocumentInteractionController),
/// на macOS — `NSWorkspace.shared.open`.
struct OpenExternallyButton: View {
    let url: URL

    #if os(iOS)
    @State private var showSheet = false
    #endif

    var body: some View {
        #if os(iOS)
        Button("Открыть в приложении") {
            showSheet = true
        }
        .sheet(isPresented: $showSheet) {
            ExternalOpenSheet(url: url) {
                showSheet = false
            }
            .presentationDetents([.medium])
        }
        #else
        Button("Открыть в приложении") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

#if os(iOS)
/// Контроллер, который при появлении показывает системное
/// меню «Открыть в…» для переданного файла.
private struct ExternalOpenSheet: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(url: url, onDismiss: onDismiss)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController,
                            UIDocumentInteractionControllerDelegate {
        private let url: URL
        private let onDismiss: () -> Void
        private var didPresent = false

        init(url: URL, onDismiss: @escaping () -> Void) {
            self.url = url
            self.onDismiss = onDismiss
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didPresent else { return }
            didPresent = true

            let interaction = UIDocumentInteractionController(url: url)
            interaction.delegate = self
            interaction.presentOptionsMenu(
                from: view.bounds,
                in: view,
                animated: true
            )
        }

        func documentInteractionControllerDidDismissOptionsMenu(
            _ controller: UIDocumentInteractionController
        ) {
            onDismiss()
        }
    }
}
#endif

/// Общая заглушка с сообщением (иконка + заголовок + описание).
struct PreviewMessageView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.047, blue: 0.075).ignoresSafeArea())
    }
}

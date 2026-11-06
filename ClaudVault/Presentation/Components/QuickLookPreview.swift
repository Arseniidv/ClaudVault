import SwiftUI
#if os(iOS)
import QuickLook
#elseif os(macOS)
import Quartz
#endif

/// Обёртка QuickLook для просмотра скачанного облачного файла.
struct QuickLookPreview: View {
    let url: URL

    var body: some View {
        #if os(iOS)
        IOSQuickLookPreview(url: url)
        #else
        MacQuickLookPreview(url: url)
        #endif
    }
}

// MARK: - iOS

#if os(iOS)

private struct IOSQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}

#endif

// MARK: - macOS

#if os(macOS)

private struct MacQuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else {
            return NSView()
        }
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? QLPreviewView)?.previewItem = url as NSURL
    }
}

#endif

import SwiftUI
import PDFKit

/// Постраничный просмотр PDF через PDFKit:
/// pinch-to-zoom, постраничная прокрутка, индикатор текущей страницы.
struct PDFPreviewView: View {
    let url: URL

    @State private var currentPage = 0
    @State private var pageCount = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            PDFViewRepresentable(
                url: url,
                onPageChanged: { index, count in
                    currentPage = index
                    pageCount = count
                }
            )

            if pageCount > 1 {
                Text("\(currentPage + 1) / \(pageCount)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
            }
        }
        .background(Color.black)
    }
}

private struct PDFViewRepresentable: View {
    #if os(iOS)
    typealias PlatformView = UIView
    #else
    typealias PlatformView = NSView
    #endif

    let url: URL
    let onPageChanged: (Int, Int) -> Void

    var body: some View {
        #if os(iOS)
        PDFKitView(url: url, onPageChanged: onPageChanged)
            .ignoresSafeArea()
        #else
        PDFKitView(url: url, onPageChanged: onPageChanged)
        #endif
    }
}

#if os(iOS)
private struct PDFKitView: UIViewRepresentable {
    let url: URL
    let onPageChanged: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .black
        pdfView.document = PDFDocument(url: url)
        context.coordinator.reportInitialPage(of: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}

    final class Coordinator {
        private let onPageChanged: (Int, Int) -> Void
        private var observation: NSObjectProtocol?

        init(onPageChanged: @escaping (Int, Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        func reportInitialPage(of pdfView: PDFView) {
            report(pdfView)
            observation = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak pdfView] _ in
                guard let pdfView else { return }
                self.report(pdfView)
            }
        }

        private func report(_ pdfView: PDFView) {
            guard let document = pdfView.document else { return }
            let index = pdfView.currentPage
                .flatMap { document.index(for: $0) } ?? 0
            onPageChanged(index, document.pageCount)
        }
    }
}
#else
private struct PDFKitView: NSViewRepresentable {
    let url: URL
    let onPageChanged: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .black
        pdfView.document = PDFDocument(url: url)
        context.coordinator.reportInitialPage(of: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {}

    final class Coordinator {
        private let onPageChanged: (Int, Int) -> Void
        private var observation: NSObjectProtocol?

        init(onPageChanged: @escaping (Int, Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        func reportInitialPage(of pdfView: PDFView) {
            report(pdfView)
            observation = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak pdfView] _ in
                guard let pdfView else { return }
                self.report(pdfView)
            }
        }

        private func report(_ pdfView: PDFView) {
            guard let document = pdfView.document else { return }
            let index = pdfView.currentPage
                .flatMap { document.index(for: $0) } ?? 0
            onPageChanged(index, document.pageCount)
        }
    }
}
#endif

import SwiftUI
#if os(iOS)
import UIKit
import VisionKit
#endif

/// Сканер документов на базе `VNDocumentCameraViewController` (iOS).
/// Отсканированные страницы автоматически собираются в многостраничный
/// PDF через `DocumentPDFConverter` и возвращаются через `onScanComplete`.
#if os(iOS)
struct DocumentScannerView: UIViewControllerRepresentable {

    let onScanComplete: (URL) -> Void
    let onCancel: () -> Void
    /// Вызывается при ошибке сканирования или генерации PDF.
    var onError: ((Error) -> Void)? = nil

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(
        _ uiViewController: VNDocumentCameraViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScanComplete: onScanComplete,
            onCancel: onCancel,
            onError: onError
        )
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScanComplete: (URL) -> Void
        private let onCancel: () -> Void
        private let onError: ((Error) -> Void)?
        private var didFinish = false

        init(
            onScanComplete: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void,
            onError: ((Error) -> Void)?
        ) {
            self.onScanComplete = onScanComplete
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard !didFinish else { return }
            didFinish = true
            controller.dismiss(animated: true)

            // `VNDocumentCameraScan` нужно опросить на главном потоке —
            // вытаскиваем UIImage здесь, а сам PDF рендерим в фоне.
            let images = (0..<scan.pageCount).map {
                scan.imageOfPage(at: $0)
            }

            guard !images.isEmpty else {
                onError?(DocumentPDFConverter.DocumentScanError.noPages)
                return
            }

            Task { @MainActor in
                do {
                    let url = try await Task.detached(priority: .userInitiated) {
                        try DocumentPDFConverter.writePDF(pageImages: images)
                    }.value
                    onScanComplete(url)
                } catch {
                    onError?(error)
                }
            }
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            guard !didFinish else { return }
            didFinish = true
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            guard !didFinish else { return }
            didFinish = true
            controller.dismiss(animated: true)
            onError?(error)
        }
    }
}

/// Собирает отсканированные страницы в многостраничный PDF-файл
/// во временной директории приложения.
enum DocumentPDFConverter {

    /// Записывает PDF и возвращает его URL во временной директории.
    /// Вызывать с фонового потока — рендер больших сканов тяжёлый.
    nonisolated static func writePDF(pageImages images: [UIImage]) throws -> URL {
        guard let firstImage = images.first else {
            throw DocumentScanError.noPages
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        // Размер страницы PDF = размер первого отсканированного изображения
        // (в пунктах). Все страницы вписываются (aspect-fit) в этот размер.
        let pageRect = CGRect(origin: .zero, size: firstImage.size)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: url) { context in
            for image in images {
                let imageRect = CGRect(origin: .zero, size: image.size)

                // Пропорциональное вписывание изображения в страницу.
                let scale = min(
                    pageRect.width / imageRect.width,
                    pageRect.height / imageRect.height
                )
                let scaledSize = CGSize(
                    width: imageRect.width * scale,
                    height: imageRect.height * scale
                )
                let drawRect = CGRect(
                    x: (pageRect.width - scaledSize.width) / 2,
                    y: (pageRect.height - scaledSize.height) / 2,
                    width: scaledSize.width,
                    height: scaledSize.height
                )

                context.beginPage()
                image.draw(in: drawRect)
            }
        }

        return url
    }

    enum DocumentScanError: LocalizedError {
        case noPages

        var errorDescription: String? {
            "Не удалось получить отсканированные страницы."
        }
    }
}
#endif

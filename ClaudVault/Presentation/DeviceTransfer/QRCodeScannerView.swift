import SwiftUI

/// Камера-сканер QR-кодов (iOS). На macOS камера не используется —
/// там доступен только ручной ввод ссылки/ID сессии.
#if os(iOS)
import Vision
import VisionKit

struct QRCodeScannerView: UIViewControllerRepresentable {

    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(
        _ uiViewController: DataScannerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCodeScanned: (String) -> Void
        private var didScan = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didScan else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue {
                    didScan = true
                    try? dataScanner.stopScanning()
                    onCodeScanned(payload)
                    return
                }
            }
        }
    }
}
#endif

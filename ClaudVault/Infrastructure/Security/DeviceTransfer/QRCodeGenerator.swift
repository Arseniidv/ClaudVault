import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Генератор QR-кода на базе `CIQRCodeGenerator` (Core Image).
///
/// Сервис намеренно отделён от создания защищённой сессии переноса:
/// на вход получает уже готовую строку payload и возвращает
/// `CGImage`, пригодный для отображения в SwiftUI на iOS и macOS.
///
/// Актор гарантирует, что дорогой CPU-bound рендер выполняется вне
/// `MainActor` и что параллельные вызовы сериализуются.
actor QRCodeGenerator {

    /// Толщина тихой зоны по спецификации QR — 4 модуля с каждой стороны.
    private static let quietZoneModules = 4
    /// Размер выходного изображения по умолчанию (большая сторона), px.
    /// ~1000 px достаточно для стабильного сканирования камерой.
    private static let defaultTargetPixelSize: CGFloat = 1024

    /// Переиспользуемый контекст Core Image — создание `CIContext`
    /// дорогое, поэтому экземпляр живёт всё время жизни сервиса.
    /// `CIContext` потокобезопасен для `createCGImage`.
    private let context = CIContext()

    enum GenerationError: LocalizedError, Sendable {
        /// Входная строка пуста — QR-код из неё построить нельзя.
        case emptyInput
        /// `CIQRCodeGenerator` не смог построить QR-символ
        /// (например, данные не помещаются в максимальную версию).
        case filterFailed
        /// Фильтр вернул пустое/некорректное `CIImage`.
        case renderFailed
        /// `CIContext` не смог создать `CGImage` из результата.
        case imageCreationFailed

        var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "Данные для QR-кода пусты."
            case .filterFailed:
                return "Не удалось создать QR-код из переданных данных."
            case .renderFailed:
                return "QR-фильтр не вернул изображение."
            case .imageCreationFailed:
                return "Не удалось отрисовать QR-код."
            }
        }
    }

    /// Генерирует QR-код из строки.
    ///
    /// - Parameters:
    ///   - string: содержимое QR-кода (например,
    ///     `claudvault://verify?session=…`).
    ///   - scale: пикселей на один QR-модуль. Целое число `>= 1`
    ///     сохраняет чёткие границы модулей. Значение `<= 0`
    ///     включает автоматический подбор масштаба под
    ///     `defaultTargetPixelSize`.
    /// - Returns: `CGImage` с тихой зоной и разрешением,
    ///   достаточным для сканирования камерой.
    /// - Throws: `GenerationError` на каждом этапе конвейера
    ///   и `CancellationError` при отмене задачи.
    func generate(from string: String, scale: CGFloat = 0) async throws -> CGImage {
        try Task.checkCancellation()
        guard !string.isEmpty else {
            throw GenerationError.emptyInput
        }

        // 1. QR-фильтр: строка кодируется в UTF-8 и передаётся
        //    через `message`, коррекция ошибок — уровень "M".
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        // 2. Выходной CIImage — квадрат из целых модулей.
        guard let output = filter.outputImage,
              output.extent.width.isFinite,
              output.extent.height.isFinite,
              output.extent.width > 0,
              output.extent.height > 0 else {
            throw GenerationError.renderFailed
        }

        // 3. Целочисленный масштаб — границы модулей остаются
        //    чёткими при любом последующем отображении.
        let moduleCount = Int(output.extent.width)
        let pixelScale: Int
        if scale > 0 {
            pixelScale = max(1, Int(scale.rounded()))
        } else {
            let totalModules = moduleCount + Self.quietZoneModules * 2
            pixelScale = max(
                1,
                Int(ceil(Self.defaultTargetPixelSize / CGFloat(totalModules)))
            )
        }

        let scaleFactor = CGFloat(pixelScale)
        var image = output.transformed(
            by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
        )

        // 4. Тихая зона: белое поле вокруг кода. Без неё часть
        //    сканеров не распознаёт QR, а края кода могут
        //    обрезаться при отображении в скруглённой рамке.
        let quietZone = Self.quietZoneModules * pixelScale
        let canvasExtent = CGRect(
            x: 0,
            y: 0,
            width: image.extent.width + CGFloat(quietZone * 2),
            height: image.extent.height + CGFloat(quietZone * 2)
        )
        let background = CIImage(color: CIColor.white)
            .cropped(to: canvasExtent)
        image = image.transformed(
            by: CGAffineTransform(
                translationX: CGFloat(quietZone),
                y: CGFloat(quietZone)
            )
        )
        let composited = image.composited(over: background)

        // 5. Растеризация через переиспользуемый CIContext.
        guard let cgImage = context.createCGImage(
            composited,
            from: canvasExtent
        ) else {
            throw GenerationError.imageCreationFailed
        }

        try Task.checkCancellation()
        return cgImage
    }
}

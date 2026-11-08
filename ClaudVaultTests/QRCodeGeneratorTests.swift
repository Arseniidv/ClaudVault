import XCTest
import Vision
@testable import ClaudVault

/// Тесты `QRCodeGenerator`: валидность изображения, контроль ошибок,
/// размер/качество и обратная совместимость с QR-сканером (Vision).
final class QRCodeGeneratorTests: XCTestCase {

    private let generator = QRCodeGenerator()

    /// Валидная строка → QR-код с quiet zone и достаточным разрешением.
    func testGeneratesQRForValidString() async throws {
        let payload = "claudvault://verify?session=12345678-1234-1234-1234-123456789012"
        let image = try await generator.generate(from: payload)

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertEqual(image.width, image.height, "QR-код должен быть квадратным")
        // Автомасштаб целится в ~1024 px по большей стороне.
        XCTAssertGreaterThanOrEqual(image.width, 700)
    }

    /// Пустая строка → контролируемая ошибка, а не пустая картинка.
    func testEmptyStringThrowsControlledError() async {
        do {
            _ = try await generator.generate(from: "")
            XCTFail("Ожидалась ошибка для пустой строки")
        } catch let error as QRCodeGenerator.GenerationError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Неожиданный тип ошибки: \(error)")
        }
    }

    /// Большой payload не должен ни падать, ни блокировать выполнение.
    /// 1500 символов помещаются в QR с коррекцией M (ёмкость ~2331 байт).
    func testLargePayloadGeneratesOffMainThread() async throws {
        let payload = "claudvault://verify?session=" + String(repeating: "a", count: 1500)
        let image = try await generator.generate(from: payload)
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertEqual(image.width, image.height)
    }

    /// Данные сверх ёмкости QR (~2953 байт даже на уровне L)
    /// должны давать контролируемую ошибку, а не зависание или крэш.
    func testOversizedPayloadThrowsControlledError() async {
        let payload = String(repeating: "a", count: 4000)
        do {
            _ = try await generator.generate(from: payload)
            XCTFail("Ожидалась ошибка для слишком большого payload")
        } catch is QRCodeGenerator.GenerationError {
            // Ожидаемый контролируемый отказ фильтра/рендера.
        } catch {
            XCTFail("Неожиданный тип ошибки: \(error)")
        }
    }

    /// Явный масштаб: выход = (модули + 2×quietZone) × scale.
    /// Для session-URL QR занимает 35 модулей → (35 + 8) × 4 = 172 px.
    func testExplicitIntegerScaleProducesSharpModules() async throws {
        let payload = "claudvault://verify?session=12345678-1234-1234-1234-123456789012"
        let image = try await generator.generate(from: payload, scale: 4)
        XCTAssertEqual(image.width, 172)
        XCTAssertEqual(image.height, 172)
    }

    /// Сгенерированный QR должен читаться обратно тем же механизмом,
    /// что использует сканер на принимающем устройстве (Vision barcode).
    func testGeneratedQRIsScannableByVision() async throws {
        let payload = "claudvault://verify?session=ABCDEFAB-1234-5678-9ABC-DEF012345678"
        let image = try await generator.generate(from: payload)

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // В unit-test sandbox симулятора Vision иногда не может
            // создать inference context — это ограничение окружения,
            // а не дефект QR-кода. На устройстве сканер работает.
            throw XCTSkip("Vision barcode recognition unavailable: \(error)")
        }

        let codes = request.results ?? []
        XCTAssertEqual(codes.count, 1, "Сканер должен найти ровно один QR-код")
        XCTAssertEqual(codes.first?.payloadStringValue, payload)
    }
}

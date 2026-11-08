import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Извлекает метаданные и обложку из аудиоактива.
///
/// Читает `commonMetadata` (ID3v2 для MP3, `©nam`/`©ART`/`covr`
/// для M4A/AAC) через асинхронный AVFoundation API —
/// не блокирует main thread и не требует полной загрузки файла
/// для потоковых источников.
enum AudioMetadataExtractor {

    struct Metadata {
        var title: String?
        var artist: String?
        var album: String?
        /// JPEG/PNG-данные обложки в исходном виде.
        var artworkData: Data?
    }

    /// Извлекает метаданные из asset. Возвращает nil-поля,
    /// если тегов нет — это нормальный сценарий.
    static func extract(from asset: AVURLAsset) async -> Metadata {
        var result = Metadata()
        do {
            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    result.title = await stringValue(of: item)
                case .commonKeyArtist:
                    result.artist = await stringValue(of: item)
                case .commonKeyAlbumName:
                    result.album = await stringValue(of: item)
                case .commonKeyArtwork:
                    result.artworkData = await artworkData(of: item)
                default:
                    break
                }
            }
        } catch {
            // Метаданные недоступны (обрезанный стрим, неподдерживаемый
            // контейнер) — плеер продолжает работать без них.
        }
        return result
    }

    /// Приводит значение метаданных к строке.
    /// `load(.value)` для текстовых ключей возвращает NSString.
    private static func stringValue(of item: AVMetadataItem) async -> String? {
        guard let value = try? await item.load(.value) else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    /// Достаёт бинарные данные обложки. Для `covr`/APIC
    /// `load(.value)` возвращает NSData.
    private static func artworkData(of item: AVMetadataItem) async -> Data? {
        guard let value = try? await item.load(.value) else { return nil }
        if let data = value as? Data { return data }
        if let nsData = value as? NSData { return nsData as Data }
        return nil
    }

    /// Конвертирует обложку в JPEG разумного размера
    /// (максимум `maxDimension` px по большей стороне) —
    /// достаточно для плеера, виджета и Live Activity
    /// без лишних мегабайт.
    static func jpegData(from data: Data, maxDimension: CGFloat = 600) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1)
        guard scale < 1 else {
            return image.jpegData(compressionQuality: 0.85)
        }
        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1)
        let targetSize = NSSize(
            width: size.width * scale,
            height: size.height * scale
        )
        let output = NSImage(size: targetSize)
        output.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.85]
        )
        #else
        return nil
        #endif
    }
}

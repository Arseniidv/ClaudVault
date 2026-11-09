import Foundation
import Compression

/// Извлекает plain-text из ODT-файла (OpenDocument Text).
///
/// ODT — это ZIP-архив, текст лежит в `content.xml`.
/// QuickLook ODT не поддерживает, поэтому читаем архив
/// минимальным ZIP-парсером (stored + deflate) и вырезаем
/// текст из XML-разметки `text:p`/`text:h`.
enum OdtTextExtractor {

    struct ExtractionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Возвращает извлечённый текст или nil, если файл не похож
    /// на ODT или текст извлечь не удалось.
    static func text(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let xmlData = unzipEntry(named: "content.xml", in: data),
              let xml = String(data: xmlData, encoding: .utf8) else {
            return nil
        }
        return plainText(from: xml)
    }

    // MARK: - ZIP parsing

    /// Достаёт несжатое содержимое записи `name` из ZIP-данных.
    /// Поддерживаются методы 0 (stored) и 8 (deflate).
    private static func unzipEntry(named name: String, in data: Data) -> Data? {
        guard let eocd = findEndOfCentralDirectory(in: data),
              let centralOffset = uint32(data, at: eocd + 16),
              let entryCount = uint16(data, at: eocd + 10) else {
            return nil
        }

        var offset = Int(centralOffset)
        for _ in 0..<Int(entryCount) {
            guard uint32(data, at: offset) == 0x0201_4b50,
                  let method = uint16(data, at: offset + 10),
                  let compressedSize = uint32(data, at: offset + 20),
                  let nameLength = uint16(data, at: offset + 28),
                  let extraLength = uint16(data, at: offset + 30),
                  let commentLength = uint16(data, at: offset + 32),
                  let localOffset = uint32(data, at: offset + 42) else {
                return nil
            }

            let nameStart = offset + 46
            guard nameStart + Int(nameLength) <= data.count else { return nil }
            let entryName = String(
                bytes: data[nameStart..<(nameStart + Int(nameLength))],
                encoding: .utf8
            )

            // Следующая запись центрального каталога.
            offset = nameStart + Int(nameLength)
                + Int(extraLength) + Int(commentLength)

            guard entryName == name else { continue }

            // Локальный заголовок: имя и extra могут отличаться
            // по длине от центрального каталога — читаем заново.
            guard uint32(data, at: Int(localOffset)) == 0x0403_4b50,
                  let localNameLength = uint16(data, at: Int(localOffset) + 26),
                  let localExtraLength = uint16(data, at: Int(localOffset) + 28) else {
                return nil
            }

            let dataStart = Int(localOffset) + 30
                + Int(localNameLength) + Int(localExtraLength)
            let dataEnd = dataStart + Int(compressedSize)
            guard dataStart >= 0, dataEnd <= data.count, dataStart < dataEnd else {
                return nil
            }
            let compressed = data[dataStart..<dataEnd]

            switch method {
            case 0:
                return Data(compressed)
            case 8:
                return inflate(Data(compressed))
            default:
                return nil
            }
        }
        return nil
    }

    /// EOCD-сигнатура 0x06054b50 ищется в конце файла
    /// (комментарий архива может быть до 64 КБ).
    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let signature: UInt32 = 0x0605_4b50
        let minOffset = max(0, data.count - 22 - 65_535)
        var i = data.count - 22
        while i >= minOffset {
            if uint32(data, at: i) == signature {
                return i
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Deflate

    /// ZIP хранит «сырой» deflate-поток, а `COMPRESSION_ZLIB`
    /// ждёт zlib-обёртку — добавляем 2-байтовый заголовок.
    private static func inflate(_ compressed: Data) -> Data? {
        var input = Data([0x78, 0x9C])
        input.append(compressed)

        var output = Data(count: compressed.count * 4 + 65_536)
        let written = input.withUnsafeBytes { src in
            output.withUnsafeMutableBytes { dst in
                compression_decode_buffer(
                    dst.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    dst.count,
                    src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    src.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        output.removeSubrange(written..<output.count)
        return output
    }

    // MARK: - XML → plain text

    /// Вырезает текст из `content.xml`: границы абзацев
    /// (`text:p`, `text:h`) становятся переводами строк,
    /// теги удаляются, XML-сущности раскодируются.
    private static func plainText(from xml: String) -> String {
        var result = ""
        result.reserveCapacity(xml.count / 2)

        var index = xml.startIndex
        while index < xml.endIndex {
            guard xml[index] == "<" else {
                // Обычный текст — копируем до следующего '<'.
                let next = xml[index...].firstIndex(of: "<") ?? xml.endIndex
                result += decodeEntities(String(xml[index..<next]))
                index = next
                continue
            }

            // Комментарии и CDATA пропускаем/обрабатываем как текст.
            if xml[index...].hasPrefix("<!--") {
                if let end = xml.range(of: "-->", range: index..<xml.endIndex) {
                    index = end.upperBound
                } else {
                    break
                }
                continue
            }
            if xml[index...].hasPrefix("<![CDATA[") {
                if let end = xml.range(of: "]]>", range: index..<xml.endIndex) {
                    result += String(xml[xml.index(index, offsetBy: 9)..<end.lowerBound])
                    index = end.upperBound
                } else {
                    break
                }
                continue
            }

            if let tagEnd = xml[index...].firstIndex(of: ">") {
                let tag = xml[xml.index(after: index)..<tagEnd]
                if isBlockTag(tag, "text:p") || isBlockTag(tag, "text:h")
                    || isBlockTag(tag, "text:list-item") {
                    result.append("\n")
                } else if tag == "text:s" || tag.hasPrefix("text:s ") {
                    result.append(" ")
                } else if tag.hasPrefix("text:tab") {
                    result.append("\t")
                } else if tag.hasPrefix("text:line-break") {
                    result.append("\n")
                }
                index = xml.index(after: tagEnd)
            } else {
                break
            }
        }

        // Схлопываем 3+ пустых строк до двух.
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `tag` — имя тега без `<`/`>`. Блочный тег — это сам тег
    /// или он с атрибутами/самозакрытием, но не более длинный
    /// тег с тем же префиксом (например, `text:page-number`).
    private static func isBlockTag(_ tag: Substring, _ name: String) -> Bool {
        guard tag.hasPrefix(name) else { return false }
        let rest = tag.dropFirst(name.count)
        return rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("/")
    }

    /// Однопроходное раскодирование XML-сущностей: именованных
    /// (`&amp;`, `&lt;`, …) и числовых (`&#65;`, `&#x41;`).
    /// Сущность считается только если `;` находится в пределах
    /// 10 символов — длинные «хвосты» остаются текстом.
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "&" else {
                let next = text[index...].firstIndex(of: "&") ?? text.endIndex
                result += text[index..<next]
                index = next
                continue
            }

            let searchEnd = text.index(index, offsetBy: 11,
                                       limitedBy: text.endIndex) ?? text.endIndex
            guard let semi = text[index..<searchEnd].firstIndex(of: ";"),
                  semi > text.index(after: index) else {
                result.append("&")
                index = text.index(after: index)
                continue
            }

            let entity = String(text[text.index(after: index)..<semi])
            let decoded: String?
            switch entity {
            case "lt": decoded = "<"
            case "gt": decoded = ">"
            case "quot": decoded = "\""
            case "apos": decoded = "'"
            case "amp": decoded = "&"
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X"),
                   let value = UInt32(entity.dropFirst(2), radix: 16),
                   let scalar = Unicode.Scalar(value) {
                    decoded = String(scalar)
                } else if entity.hasPrefix("#"),
                          let value = UInt32(entity.dropFirst()),
                          let scalar = Unicode.Scalar(value) {
                    decoded = String(scalar)
                } else {
                    decoded = nil
                }
            }

            if let decoded {
                result += decoded
                index = text.index(after: semi)
            } else {
                result.append("&")
                index = text.index(after: index)
            }
        }
        return result
    }

    // MARK: - Little-endian readers

    private static func uint16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt16? in
            let base = raw.baseAddress!.advanced(by: offset)
            let b0 = base.load(as: UInt8.self)
            let b1 = base.load(fromByteOffset: 1, as: UInt8.self)
            return UInt16(b0) | (UInt16(b1) << 8)
        }
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt32? in
            let base = raw.baseAddress!.advanced(by: offset)
            return UInt32(base.load(as: UInt8.self))
                | (UInt32(base.load(fromByteOffset: 1, as: UInt8.self)) << 8)
                | (UInt32(base.load(fromByteOffset: 2, as: UInt8.self)) << 16)
                | (UInt32(base.load(fromByteOffset: 3, as: UInt8.self)) << 24)
        }
    }
}

import Foundation

/// Элемент, который открывается в предпросмотре по long press:
/// облачный файл вместе с провайдером, из которого он скачивается.
struct FilePreviewItem: Identifiable, Equatable {
    let provider: StorageProviderType
    let file: CloudFile

    var id: String {
        "\(provider.rawValue)|\(file.id)"
    }
}

/// Тип содержимого файла — определяет, какой предпросмотр
/// использовать внутри `FilePreviewView`.
enum FilePreviewKind: Equatable {
    /// PDF — PDFKit (масштабирование, постраничная навигация).
    case pdf
    /// MP3/M4A/AAC и прочие аудио — AVPlayer.
    case audio
    /// MP4/MOV и прочие видео — AVPlayerViewController/AVPlayerView.
    case video
    /// DOC/DOCX/RTF/ODT и офисные форматы — QuickLook,
    /// для ODT — извлечение текста из content.xml.
    case document
    /// Простой текст (TXT/MD/JSON/…) — текстовый просмотр.
    case text
    /// Неподдерживаемый формат — заглушка + «Открыть в приложении».
    case unsupported
}

extension FilePreviewKind {
    init(file: CloudFile) {
        let ext = file.name
            .split(separator: ".")
            .last?
            .lowercased() ?? ""
        let mime = file.mimeType.lowercased()

        if ext == "pdf" || mime == "application/pdf" {
            self = .pdf
        } else if mime.hasPrefix("audio/")
                    || ["mp3", "m4a", "aac", "wav", "flac", "ogg", "oga", "opus", "m4b"]
                        .contains(ext) {
            self = .audio
        } else if mime.hasPrefix("video/")
                    || ["mp4", "mov", "m4v"].contains(ext) {
            self = .video
        } else if ["txt", "md", "markdown", "json", "xml", "yaml", "yml",
                  "csv", "tsv", "log", "text"].contains(ext)
                    || mime.hasPrefix("text/") {
            self = .text
        } else if ["doc", "docx", "rtf", "odt", "ppt", "pptx", "xls", "xlsx",
                  "numbers", "pages", "key"].contains(ext)
                    || mime.contains("wordprocessingml")
                    || mime.contains("opendocument")
                    || mime == "application/rtf" {
            self = .document
        } else {
            self = .unsupported
        }
    }
}

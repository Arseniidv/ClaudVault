import Foundation

/// Санитизация имён файлов, приходящих из облачных провайдеров
/// или пользовательского ввода, перед записью на локальный диск.
///
/// `appendingPathComponent` не защищает от `..` и разделителей
/// внутри строки: файл с именем `..` или `a/b` мог бы выйти за
/// пределы целевой директории (в пределах sandbox — но с доступом
/// к SwiftData store и кэшам приложения).
public enum SafeFileName {

    /// Возвращает безопасное локальное имя файла или `nil`,
    /// если имя недопустимо (`""`, `"."`, `".."`, только
    /// управляющие символы).
    ///
    /// - Берётся только последний компонент пути — `/` и `\`
    ///   внутри облачного имени отбрасываются.
    /// - Управляющие символы (включая NUL) вырезаются.
    public static func sanitized(_ raw: String) -> String? {
        // NSString.lastPathComponent корректно обрабатывает оба
        // разделителя и не создаёт путь из строки с ".." внутри.
        let last = (raw as NSString).lastPathComponent
        let withoutControls = String(
            last.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            }
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !withoutControls.isEmpty,
              withoutControls != ".",
              withoutControls != ".." else {
            return nil
        }
        return withoutControls
    }

    /// Как `sanitized`, но с запасным именем — для мест,
    /// где файл обязан быть записан в любом случае.
    public static func sanitized(_ raw: String, fallback: String) -> String {
        sanitized(raw) ?? fallback
    }
}

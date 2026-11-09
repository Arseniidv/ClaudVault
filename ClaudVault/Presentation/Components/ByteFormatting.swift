import Foundation

/// Единый форматтер размеров файлов.
///
/// `ByteCountFormatter` без явной локали на английской системе
/// выводит «Zero KB» — смешанный язык рядом с русским интерфейсом,
/// а в актуальных SDK у него нет публичного `locale`.
/// Формат повторяет `ByteCountFormatter` (`.file`): минимальная
/// единица — КБ, дальше МБ/ГБ/ТБ с одной дробной цифрой.
enum ByteFormatting {

    private static let units = ["КБ", "МБ", "ГБ", "ТБ", "ПБ"]

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func string(fromByteCount count: Int64) -> String {
        let bytes = Double(max(count, 0))

        guard bytes > 0 else { return "0 КБ" }
        // Файл меньше килобайта — как у ByteCountFormatter
        // с минимальной единицей КБ показываем «1 КБ».
        guard bytes >= 1024 else { return "1 КБ" }

        var value = bytes / 1024
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let number = numberFormatter.string(
            from: NSNumber(value: value)
        ) ?? String(format: "%.1f", value)
        return "\(number) \(units[unitIndex])"
    }
}

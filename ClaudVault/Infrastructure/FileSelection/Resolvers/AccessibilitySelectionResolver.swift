#if os(macOS)
import Cocoa
import ApplicationServices

/// Пытается получить выделенные файлы текущего приложения
/// через Accessibility API.
///
/// Эвристика best-effort: macOS не предоставляет универсального
/// API «какие файлы выделены в чужом приложении». Мы идём по
/// AX-деревву активного приложения и собираем `AXURL`/`AXDocument`
/// у элементов, помеченных как выбранные (`AXSelected`,
/// `AXSelectedRows`, `AXSelectedChildren`, `AXSelectedCells`).
///
/// Требуется разрешение Accessibility (Privacy & Security).
/// Результат зависит от конкретного приложения: Finder, Preview
/// и браузеры отдают URL выделения, многие — нет.
struct AccessibilitySelectionResolver: FileSelectionResolving {

    let source: SelectionSource = .accessibility

    private let validator = FileAccessValidator()
    /// Ограничения обхода дерева: AX-иерархии некоторых
    /// приложений (почта, IDE) содержат десятки тысяч узлов.
    private let maxElements = 800
    private let maxDepth = 14

    func resolve() async -> FileSelection? {
        // AX API синхронный и может ходить в чужой процесс —
        // уводим обход с MainActor.
        let maxElements = self.maxElements
        let maxDepth = self.maxDepth
        let urls = await Task.detached(priority: .userInitiated) {
            Self.collectSelectedFileURLs(
                maxElements: maxElements,
                maxDepth: maxDepth
            )
        }.value
        let selection = validator.validate(urls, source: source)
        return selection.isEmpty ? nil : selection
    }

    // MARK: - AX traversal

    private static func collectSelectedFileURLs(
        maxElements: Int,
        maxDepth: Int
    ) -> [URL] {
        guard AXIsProcessTrusted() else { return [] }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedApp = focusedValue,
              CFGetTypeID(focusedApp) == AXUIElementGetTypeID()
        else { return [] }

        let app = unsafeBitCast(focusedApp, to: AXUIElement.self)

        // Не сканируем самих себя — иначе меню будет «выделять»
        // собственные элементы.
        var pid = pid_t(0)
        if AXUIElementGetPid(app, &pid) == .success,
           pid == ProcessInfo.processInfo.processIdentifier {
            return []
        }

        // Стартовая точка — ключевое окно, иначе всё приложение.
        var root: AXUIElement?
        for windowAttribute in [
            kAXFocusedWindowAttribute, kAXMainWindowAttribute
        ] {
            var windowValue: AnyObject?
            if AXUIElementCopyAttributeValue(
                app,
                windowAttribute as CFString,
                &windowValue
            ) == .success,
               let window = windowValue,
               CFGetTypeID(window) == AXUIElementGetTypeID() {
                root = unsafeBitCast(window, to: AXUIElement.self)
                break
            }
        }

        var collector = AXCollector(
            maxElements: maxElements,
            maxDepth: maxDepth
        )
        collector.traverse(root ?? app)
        return collector.urls
    }

    // MARK: - Collector

    /// Обход AX-дерева: собирает URL элементов, которые приложение
    /// считает выбранными. Порядок обхода BFS — выделение
    /// сохраняет визуальный порядок слева направо/сверху вниз.
    private struct AXCollector {
        private(set) var urls: [URL] = []
        private var visited = 0
        private var queue: [(element: AXUIElement, depth: Int)] = []
        private var seen = Set<UInt>()
        private let maxElements: Int
        private let maxDepth: Int

        init(maxElements: Int, maxDepth: Int) {
            self.maxElements = maxElements
            self.maxDepth = maxDepth
        }

        mutating func traverse(_ root: AXUIElement) {
            enqueue(root, depth: 0)
            var index = 0
            while index < queue.count, visited < maxElements {
                let (element, depth) = queue[index]
                index += 1
                visited += 1
                process(element, depth: depth)
            }
        }

        private mutating func enqueue(_ element: AXUIElement, depth: Int) {
            let key = UInt(
                bitPattern: Unmanaged.passUnretained(element).toOpaque()
            )
            guard !seen.contains(key) else { return }
            seen.insert(key)
            queue.append((element, depth))
        }

        private mutating func process(_ element: AXUIElement, depth: Int) {
            // Прямое выделение: AXSelected == true + AXURL.
            if boolAttribute(element, kAXSelectedAttribute as String),
               let url = fileURLAttribute(element) {
                append(url)
            }

            // Контейнеры выделения: таблицы/списки отдают
            // AXSelectedRows/AXSelectedChildren/AXSelectedCells.
            for attributeName in [
                "AXSelectedRows", "AXSelectedChildren", "AXSelectedCells"
            ] {
                for child in elementArray(element, attributeName) {
                    if let url = fileURLAttribute(child) {
                        append(url)
                    } else {
                        // Выделенная строка может быть группой —
                        // проверяем её прямых детей на один уровень.
                        for grandchild in elementArray(
                            child, kAXChildrenAttribute as String
                        ) {
                            if let url = fileURLAttribute(grandchild) {
                                append(url)
                            }
                        }
                    }
                    enqueue(child, depth: depth + 1)
                }
            }

            guard depth < maxDepth else { return }
            for child in elementArray(element, kAXChildrenAttribute as String)
                + elementArray(element, "AXVisibleChildren") {
                enqueue(child, depth: depth + 1)
            }
        }

        private mutating func append(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard !urls.contains(where: {
                $0.standardizedFileURL == normalized
            }) else { return }
            urls.append(url)
        }

        // MARK: Attribute helpers

        private func attribute(
            _ element: AXUIElement,
            _ name: String
        ) -> AnyObject? {
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, name as CFString, &value
            ) == .success else { return nil }
            return value
        }

        private func boolAttribute(
            _ element: AXUIElement,
            _ name: String
        ) -> Bool {
            guard let value = attribute(element, name),
                  CFGetTypeID(value) == CFBooleanGetTypeID()
            else { return false }
            return CFBooleanGetValue(
                unsafeBitCast(value, to: CFBoolean.self)
            )
        }

        private func fileURLAttribute(_ element: AXUIElement) -> URL? {
            for name in ["AXURL", kAXDocumentAttribute as String] {
                guard let value = attribute(element, name) else { continue }
                if let url = value as? URL, url.isFileURL { return url }
                if let nsURL = value as? NSURL,
                   let url = URL(string: nsURL.absoluteString ?? ""),
                   url.isFileURL { return url }
                if CFGetTypeID(value) == CFURLGetTypeID(),
                   let url = (value as? NSURL).flatMap({
                       URL(string: $0.absoluteString ?? "")
                   }), url.isFileURL { return url }
            }
            return nil
        }

        private func element(_ value: AnyObject) -> AXUIElement? {
            guard CFGetTypeID(value) == AXUIElementGetTypeID()
            else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }

        private func elementArray(
            _ element: AXUIElement,
            _ name: String
        ) -> [AXUIElement] {
            guard let value = attribute(element, name) else { return [] }
            if let single = self.element(value) { return [single] }
            if let array = value as? [AnyObject] {
                return array.compactMap { self.element($0) }
            }
            if let array = value as? NSArray {
                return array.compactMap {
                    self.element($0 as AnyObject)
                }
            }
            return []
        }
    }
}
#endif

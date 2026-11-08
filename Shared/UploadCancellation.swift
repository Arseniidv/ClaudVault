import Foundation

/// Кооперативная отмена загрузок резервных копий.
///
/// Кнопка «Отменить» в Live Activity выполняется в процессе
/// приложения или расширения виджета и не имеет доступа к `Task`
/// загрузки, поэтому отмена — это флаг по `UploadSession.id`:
/// в памяти текущего процесса и в `UserDefaults` App Group
/// (на случай, если intent отработал в процессе расширения —
/// приложение увидит флаг при следующей проверке).
/// Циклы передачи проверяют флаг на границе каждого чанка
/// через `checkCancellation()` / `isCancelledForCurrentTask()`.
enum UploadCancellation {

    /// `UploadSession.id` загрузки, идущей в текущей задаче.
    /// Use case'и устанавливают его через `withValue` вокруг
    /// вызова `repository.uploadFile` — TaskLocal доезжает
    /// до асинхронных циклов провайдеров без смены сигнатур.
    @TaskLocal static var sessionID: UUID?

    private static let cancelledKey = "cancelledUploadSessionIDs"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cancelledInMemory: Set<String> = []

    /// Общее хранилище приложения и расширения виджета.
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WidgetStorage.appGroupID)
    }

    /// Помечает сессию отменённой. Вызывается из `AppIntent`
    /// Live Activity — может выполниться в любом из процессов.
    static func markCancelled(_ id: UUID) {
        let string = id.uuidString

        lock.lock()
        cancelledInMemory.insert(string)
        lock.unlock()

        var ids = sharedDefaults?.stringArray(forKey: cancelledKey) ?? []
        if !ids.contains(string) {
            ids.append(string)
            sharedDefaults?.set(ids, forKey: cancelledKey)
        }
    }

    /// Снимает пометку отмены. Флаг одноразовый: use case
    /// вызывает `clear` после завершения загрузки (успех,
    /// ошибка или отмена), `LiveActivityManager` — для сессий,
    /// завершившихся без загрузки в этом процессе.
    static func clear(_ id: UUID) {
        let string = id.uuidString

        lock.lock()
        cancelledInMemory.remove(string)
        lock.unlock()

        guard var ids = sharedDefaults?.stringArray(forKey: cancelledKey),
              ids.contains(string) else { return }
        ids.removeAll { $0 == string }
        sharedDefaults?.set(ids, forKey: cancelledKey)
    }

    /// `true`, если загрузка текущей задачи помечена на отмену.
    /// Для `shouldCancel`-замыканий `ChunkedUploadRunner`.
    static func isCancelledForCurrentTask() -> Bool {
        guard let id = sessionID else { return false }
        return isCancelled(id)
    }

    /// Проверка для циклов передачи провайдеров: бросает
    /// `CancellationError`, если сессия текущей задачи отменена;
    /// иначе делегирует обычной `Task.checkCancellation()`.
    static func checkCancellation() throws {
        if isCancelledForCurrentTask() {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    private static func isCancelled(_ id: UUID) -> Bool {
        let string = id.uuidString

        lock.lock()
        let inMemory = cancelledInMemory.contains(string)
        lock.unlock()
        if inMemory { return true }

        return sharedDefaults?
            .stringArray(forKey: cancelledKey)?
            .contains(string) == true
    }
}

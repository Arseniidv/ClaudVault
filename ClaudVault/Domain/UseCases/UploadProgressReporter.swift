import Foundation

/// Троттлит обновления прогресса загрузки: репортит не чаще
/// ~4 МБ приращения, чтобы не писать в SwiftData на каждый чанк.
public final class UploadProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReportedBytes: Int64 = -1
    private let onBytes: @Sendable (Int64) -> Void

    public init(onBytes: @escaping @Sendable (Int64) -> Void) {
        self.onBytes = onBytes
    }

    public func report(fraction: Double, totalBytes: Int64) {
        let bytes = Int64((fraction * Double(totalBytes)).rounded())
        lock.lock()
        let shouldReport = bytes >= totalBytes
            || bytes - lastReportedBytes >= 4_194_304
            || lastReportedBytes < 0
        if shouldReport {
            lastReportedBytes = bytes
        }
        lock.unlock()
        if shouldReport {
            onBytes(bytes)
        }
    }
}

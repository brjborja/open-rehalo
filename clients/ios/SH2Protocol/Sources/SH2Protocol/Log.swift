import Foundation

/// Lightweight logging bridge from the (UI-agnostic) protocol layer to the host app's live log
/// view. The app installs a sink once at launch via `setSink`; protocol code calls `SH2Log.log`.
/// When no sink is installed (e.g. `swift test`), logging is a cheap no-op (the message autoclosure
/// is never evaluated).
///
/// Thread-safety: the sink is read/written under a lock, so `log` can be called from any actor /
/// queue (the `Session` actor, the CoreBluetooth queue, …). The app's sink is responsible for
/// hopping to the main actor before touching UI state.
public enum SH2Log {
    private static let lock = NSLock()
    private static var _sink: (@Sendable (String) -> Void)?

    /// Install (or clear with `nil`) the log sink. Called once by the app.
    public static func setSink(_ sink: (@Sendable (String) -> Void)?) {
        lock.lock(); _sink = sink; lock.unlock()
    }

    /// Emit a log line. The message is only built if a sink is installed.
    public static func log(_ message: @autoclosure () -> String) {
        lock.lock(); let s = _sink; lock.unlock()
        guard let s else { return }
        s(message())
    }

    /// Format a byte payload as spaced hex, truncated for readability.
    public static func hex(_ data: Data, max: Int = 32) -> String {
        let bytes = [UInt8](data)
        if bytes.isEmpty { return "(empty)" }
        let shown = bytes.prefix(max).map { String(format: "%02x", $0) }.joined(separator: " ")
        return bytes.count > max ? "\(shown) … (\(bytes.count)B)" : shown
    }
}

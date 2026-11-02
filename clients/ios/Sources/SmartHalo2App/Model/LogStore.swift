import Foundation
import Combine

/// In-app live log, fed by `SH2Log` (protocol layer) and the BLE layer. Displayed by
/// `LogConsoleView` so the connect/recover flow is visible on-device in real time.
@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    struct Line: Identifiable {
        let id: Int
        let time: String
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    private var counter = 0
    private static let cap = 500

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Append on the main actor (call sites that are already on main).
    func append(_ text: String) {
        counter += 1
        lines.append(Line(id: counter, time: Self.formatter.string(from: Date()), text: text))
        if lines.count > Self.cap { lines.removeFirst(lines.count - Self.cap) }
    }

    /// Append from any thread/actor (the `SH2Log` sink and CoreBluetooth callbacks use this).
    nonisolated func appendFromAnywhere(_ text: String) {
        Task { @MainActor in self.append(text) }
    }

    func clear() { lines.removeAll(); counter = 0 }

    /// Flat text for copy/share.
    func plainText() -> String {
        lines.map { "\($0.time)  \($0.text)" }.joined(separator: "\n")
    }
}

import Foundation
import SH2Protocol

/// Keeps a record of each ride in Documents/rides, one `RideTrace` per file, when switched on in
/// Settings › Advanced: every fix, what the screen showed and what the ring was told, so a bug seen on
/// the road can be looked at, fix by fix, at home.
@MainActor
final class RideRecorder {
    static let shared = RideRecorder()
    nonisolated static let enabledKey = "sh2.recordRides"
    /// A two-hour ride is about 10 MB: only the latest ones stay.
    private static let kept = 10

    private var file: FileHandle?

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rides", isDirectory: true)
    }

    /// Recorded rides, newest first.
    static var rides: [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func begin(_ header: RideTrace.Header) {
        end()
        guard isEnabled else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = Self.directory.appendingPathComponent("ride-\(format.string(from: Date())).jsonl")
        guard manager.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        file = handle
        write(header)
        for old in Self.rides.dropFirst(Self.kept) { try? manager.removeItem(at: old) }
    }

    func record(_ entry: RideTrace.Entry) {
        if file != nil { write(entry) }
    }

    func end() {
        try? file?.close()
        file = nil
    }

    private func write<T: Encodable>(_ value: T) {
        if let line = RideTrace.line(value) { try? file?.write(contentsOf: line) }
    }
}

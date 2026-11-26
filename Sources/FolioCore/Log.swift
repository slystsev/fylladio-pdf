import Foundation
import os

/// Small diagnostic log: ~/Library/Logs/Folio/folio.log (rotated at 2 MB, one old file kept),
/// mirrored to the unified log (subsystem app.folio.pdf). Thread-safe.
public enum Log {
    public static var directory: URL {
        // The self-test logs into its own output folder, keeping the user's log clean.
        let dir = ProcessInfo.processInfo.environment["FOLIO_SELFTEST"].map { URL(fileURLWithPath: $0).appendingPathComponent("logs", isDirectory: true) }
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    public static var fileURL: URL { directory.appendingPathComponent("folio.log") }

    private static let queue = DispatchQueue(label: "folio.log")
    private static let osLog = Logger(subsystem: "app.folio.pdf", category: "app")
    private static let lock = NSLock()
    private static var _activity = "idle"
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    /// What the main thread is doing right now; reported if it hangs.
    public static var activity: String {
        get { lock.lock(); defer { lock.unlock() }; return _activity }
        set { lock.lock(); _activity = newValue; lock.unlock() }
    }

    public static func info(_ message: String) {
        osLog.log("\(message, privacy: .public)")
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            let url = fileURL
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000 {
                let old = directory.appendingPathComponent("folio.1.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: url, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Runs `body`, recording it as the current activity and logging it if it takes longer than `threshold`.
    /// (Escaping, non-throwing and without `defer` on purpose: a non-escaping version made swiftc 6.3 hang
    /// in its closure-lifetime pass.)
    @discardableResult
    public static func timed<T>(_ label: String, threshold: TimeInterval = 0.25, _ body: @escaping () -> T) -> T {
        let previous = activity
        activity = label
        let start = Date()
        let result = body()
        let d = Date().timeIntervalSince(start)
        if d >= threshold { info(String(format: "%@ took %.2f s", label, d)) }
        activity = previous
        return result
    }
}

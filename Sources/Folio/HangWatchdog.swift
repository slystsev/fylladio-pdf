import Foundation
import FolioCore

/// Detects main-thread stalls. A background thread checks a heartbeat that the main queue updates every
/// 0.1 s. If the main thread is silent for more than `threshold`, it logs the current `Log.activity` and runs
/// /usr/bin/sample on this process (2 s), writing the main thread's stack to ~/Library/Logs/Folio/hang-*.txt.
/// When the main thread recovers, it logs how long the stall lasted.
final class HangWatchdog {
    static let shared = HangWatchdog()
    var threshold: TimeInterval = 1.0
    private let lock = NSLock()
    private var lastBeat = Date()
    private var samplesTaken = 0
    private let maxSamples = 5

    func start() {
        beat()
        let t = Thread { [weak self] in self?.watch() }
        t.name = "Folio hang watchdog"
        t.qualityOfService = .utility
        t.start()
    }

    private func beat() {
        lock.lock(); lastBeat = Date(); lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.beat() }
    }

    private func watch() {
        var stalledSince: Date?
        var stalledActivity = ""
        while true {
            Thread.sleep(forTimeInterval: 0.25)
            lock.lock(); let last = lastBeat; lock.unlock()
            let silent = Date().timeIntervalSince(last)
            if silent > threshold + 0.1 {
                if stalledSince == nil {
                    stalledSince = last
                    stalledActivity = Log.activity
                    Log.info("HANG main thread unresponsive for >\(threshold) s, activity: \(stalledActivity)")
                    sample()
                }
            } else if let since = stalledSince {
                Log.info(String(format: "HANG ended after %.1f s (activity: %@)", last.timeIntervalSince(since), stalledActivity))
                stalledSince = nil
            }
        }
    }

    private func sample() {
        guard samplesTaken < maxSamples else { return }
        samplesTaken += 1
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let out = Log.directory.appendingPathComponent("hang-\(stamp).txt")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        p.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "2", "-mayDie", "-file", out.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); Log.info("HANG stack sample → \(out.path)") } catch { Log.info("HANG sample failed: \(error)") }
        pruneSamples()
    }

    private func pruneSamples() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Log.directory, includingPropertiesForKeys: nil) else { return }
        let hangs = items.filter { $0.lastPathComponent.hasPrefix("hang-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in hangs.dropFirst(20) { try? fm.removeItem(at: old) }
    }
}

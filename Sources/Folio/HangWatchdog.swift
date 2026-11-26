import AppKit
import FolioCore

/// Detects main-thread stalls. Every 0.25 s a background thread posts a ping to the main queue and measures how
/// long the main thread takes to answer. If it doesn't answer within `threshold`, the watchdog logs the current
/// `Log.activity` and runs /usr/bin/sample on this process (2 s), writing the main thread's stack to
/// ~/Library/Logs/Folio/hang-*.txt. When the main thread answers, it logs how long the stall lasted.
///
/// Only checked while Folio is the active app: in the background, App Nap legitimately delays the main queue,
/// which earlier produced false "hangs" with an idle main thread.
final class HangWatchdog {
    static let shared = HangWatchdog()
    var threshold: TimeInterval = 1.0
    private let lock = NSLock()
    private var appActive = true
    private var samplesTaken = 0
    private let maxSamples = 5

    func start() {
        appActive = NSApp.isActive
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setActive(true) }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setActive(false) }
        let t = Thread { [weak self] in self?.watch() }
        t.name = "Folio hang watchdog"
        t.qualityOfService = .utility
        t.start()
    }

    /// For the self-test, which runs in the background but must still be watched.
    func forceActive() { setActive(true); forced = true }
    private var forced = false

    private func setActive(_ active: Bool) {
        lock.lock(); appActive = active || forced; lock.unlock()
    }

    private var isActive: Bool { lock.lock(); defer { lock.unlock() }; return appActive }

    private func watch() {
        while true {
            Thread.sleep(forTimeInterval: 0.25)
            guard isActive else { continue }
            let answered = DispatchSemaphore(value: 0)
            let sent = Date()
            DispatchQueue.main.async { answered.signal() }
            if answered.wait(timeout: .now() + threshold) == .success { continue }
            let activity = Log.activity
            Log.info("HANG main thread unresponsive for >\(threshold) s, activity: \(activity)")
            let sampled = sample()
            answered.wait()
            Log.info(String(format: "HANG ended after %.1f s (activity: %@)", Date().timeIntervalSince(sent), activity))
            // /usr/bin/sample suspends the process while it records; don't report the pauses it causes itself.
            if sampled { Thread.sleep(forTimeInterval: 4) }
        }
    }

    @discardableResult
    private func sample() -> Bool {
        guard samplesTaken < maxSamples else { return false }
        samplesTaken += 1
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let out = Log.directory.appendingPathComponent("hang-\(stamp).txt")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        p.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "2", "-mayDie", "-file", out.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); Log.info("HANG stack sample → \(out.path)") } catch { Log.info("HANG sample failed: \(error)"); return false }
        pruneSamples()
        return true
    }

    private func pruneSamples() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Log.directory, includingPropertiesForKeys: nil) else { return }
        let hangs = items.filter { $0.lastPathComponent.hasPrefix("hang-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in hangs.dropFirst(20) { try? fm.removeItem(at: old) }
    }
}

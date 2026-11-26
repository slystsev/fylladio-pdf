import Foundation

/// The app was called "Folio" up to v0.1.0 (bundle id app.folio.pdf, ~/Library/Application Support/Folio).
/// On the first launch as Fylladio, copy the user's data over (copy, not move: the old data stays as a fallback):
/// tools, bookmarks, backups and recovery journals, plus settings (reading positions, open windows, sidebar,
/// window frame) with their "Folio." keys renamed. Runs once; never during the self-test.
public enum LegacyMigration {
    public static let doneKey = "Fylladio.migratedFromFolio"

    @discardableResult
    public static func runIfNeeded() -> [String] {
        guard ProcessInfo.processInfo.environment["FYLLADIO_SELFTEST"] == nil else { return [] }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return migrate(oldSupport: base.appendingPathComponent("Folio", isDirectory: true),
                       newSupport: base.appendingPathComponent("Fylladio", isDirectory: true),
                       oldSettings: UserDefaults.standard.persistentDomain(forName: "app.folio.pdf"),
                       newDefaults: .standard)
    }

    /// Copies items of `src` missing in `dst`, descending into folders both have. Never overwrites.
    static func merge(from src: URL, into dst: URL, prefix: String) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for name in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] {
            let s = src.appendingPathComponent(name), d = dst.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: d.path, isDirectory: &isDir) {
                var srcIsDir: ObjCBool = false
                if isDir.boolValue, fm.fileExists(atPath: s.path, isDirectory: &srcIsDir), srcIsDir.boolValue {
                    out += merge(from: s, into: d, prefix: prefix + name + "/")
                }
                continue
            }
            if (try? fm.copyItem(at: s, to: d)) != nil { out.append(prefix + name) }
        }
        return out
    }

    /// Testable core. Returns what was copied, for the log.
    @discardableResult
    public static func migrate(oldSupport: URL, newSupport: URL, oldSettings: [String: Any]?, newDefaults: UserDefaults) -> [String] {
        guard !newDefaults.bool(forKey: doneKey) else { return [] }
        var copied: [String] = []
        let fm = FileManager.default
        if fm.fileExists(atPath: oldSupport.path) {
            try? fm.createDirectory(at: newSupport, withIntermediateDirectories: true)
            copied += merge(from: oldSupport, into: newSupport, prefix: "")
        }
        if let old = oldSettings {
            for (k, v) in old {
                let newKey: String
                if k.hasPrefix("Folio.") { newKey = "Fylladio." + k.dropFirst("Folio.".count) }
                else if k == "NSWindow Frame FolioDocumentWindow" { newKey = "NSWindow Frame FylladioDocumentWindow" }
                else { continue }
                if newDefaults.object(forKey: newKey) == nil { newDefaults.set(v, forKey: newKey); copied.append(newKey) }
            }
        }
        newDefaults.set(true, forKey: doneKey)
        return copied
    }
}

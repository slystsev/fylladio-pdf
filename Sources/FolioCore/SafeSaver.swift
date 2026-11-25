import Foundation
import PDFKit

public enum SaveError: Error, LocalizedError {
    case writeFailed
    public var errorDescription: String? { "PDFKit could not write the document." }
}

/// Writes a PDFDocument without ever leaving a half-written file, keeping a backup of the original.
public enum SafeSaver {
    public static var backupDirectory: URL {
        let dir = ToolConfig.supportDirectory.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static let maxBackups = 30

    /// Copies the file (APFS clone when possible) into the backup folder and prunes old backups.
    @discardableResult
    public static func backup(_ url: URL) -> URL? {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = backupDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(stamp).pdf")
        do { try fm.copyItem(at: url, to: dest) } catch {
            NSLog("Folio: backup failed: \(error)")
            return nil
        }
        prune()
        return dest
    }

    static func prune() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let sorted = items.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in sorted.dropFirst(maxBackups) { try? fm.removeItem(at: old) }
    }

    /// Writes to a temporary file on the same volume, then atomically replaces `url`.
    public static func save(_ doc: PDFDocument, to url: URL) throws {
        let fm = FileManager.default
        let tmpDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fm.removeItem(at: tmpDir) }
        let tmp = tmpDir.appendingPathComponent(url.lastPathComponent)
        guard doc.write(to: tmp) else { throw SaveError.writeFailed }
        _ = try fm.replaceItemAt(url, withItemAt: tmp, backupItemName: nil, options: [])
    }
}

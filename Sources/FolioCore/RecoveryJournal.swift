import Foundation
import PDFKit
import CryptoKit

/// Modification date + size of a file, to tell whether it changed since a journal was written.
public struct FileStamp: Codable, Equatable {
    public var modified: Date
    public var size: Int64
    public static func of(_ url: URL) -> FileStamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let d = a[.modificationDate] as? Date, let n = a[.size] as? NSNumber else { return nil }
        return FileStamp(modified: d, size: n.int64Value)
    }
}

/// Crash insurance between saves. Every edit rewrites a small sidecar PDF with one blank page per changed
/// page, carrying copies of that page's Folio-editable annotations (`AnnotationFactory.isEditable`), plus a
/// JSON file saying which pages they belong to. PDFKit's own writer is used, so fidelity equals a real save
/// (verified pixel-identical on the user's file, incl. Preview's annotations; NSKeyedArchiver was not: it
/// loses Line geometry). Deleted once a save has covered every journaled change.
public enum RecoveryJournal {
    public struct Meta: Codable, Equatable {
        public var path: String
        public var pages: [Int]
        public var base: FileStamp?
        public var date: Date
        public init(path: String, pages: [Int], base: FileStamp?, date: Date) {
            self.path = path; self.pages = pages; self.base = base; self.date = date
        }
    }

    public static var directory: URL {
        let dir = (ProcessInfo.processInfo.environment["FOLIO_SELFTEST"].map { URL(fileURLWithPath: $0) } ?? ToolConfig.supportDirectory)
            .appendingPathComponent("Recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func baseName(for file: URL) -> String {
        let h = SHA256.hash(data: Data(file.standardizedFileURL.path.utf8))
        return h.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    public static func pdfURL(for file: URL) -> URL { directory.appendingPathComponent(baseName(for: file) + ".pdf") }
    public static func metaURL(for file: URL) -> URL { directory.appendingPathComponent(baseName(for: file) + ".json") }

    /// Builds the journal for `pages` of `doc` (main thread: touches PDFKit objects). Pages are sorted.
    public static func build(doc: PDFDocument, pages: [Int]) -> (Data, [Int])? {
        let pages = pages.filter { $0 >= 0 && $0 < doc.pageCount }.sorted()
        guard !pages.isEmpty else { return nil }
        let j = PDFDocument()
        for (k, i) in pages.enumerated() {
            guard let src = doc.page(at: i) else { continue }
            let blank = PDFPage()
            blank.setBounds(src.bounds(for: .mediaBox), for: .mediaBox)
            j.insert(blank, at: k)
            for a in src.annotations where AnnotationFactory.isEditable(a) {
                AnnotationFactory.restoreOpacity(a)
                guard let c = a.copy() as? PDFAnnotation else { continue }
                // copy() loses the colour's colour space (Folio's sRGB aqua came back duller); set it again.
                c.color = a.color
                if let f = a.fontColor { c.fontColor = f }
                if let i = a.interiorColor { c.interiorColor = i }
                blank.addAnnotation(c)
            }
        }
        guard let data = j.dataRepresentation() else { return nil }
        return (data, pages)
    }

    /// Writes journal data (any thread). The meta file goes last, so a half-written journal is never offered.
    public static func write(_ data: Data, meta: Meta, for file: URL) {
        do {
            try? FileManager.default.removeItem(at: metaURL(for: file))
            try data.write(to: pdfURL(for: file), options: .atomic)
            try JSONEncoder().encode(meta).write(to: metaURL(for: file), options: .atomic)
        } catch {
            Log.info("recovery journal write failed: \(error)")
        }
    }

    public static func delete(for file: URL) {
        try? FileManager.default.removeItem(at: metaURL(for: file))
        try? FileManager.default.removeItem(at: pdfURL(for: file))
    }

    /// A journal left behind for `file` (Folio quit without saving these edits), if any.
    public static func pending(for file: URL) -> (Meta, PDFDocument)? {
        guard let data = try? Data(contentsOf: metaURL(for: file)),
              let meta = try? JSONDecoder().decode(Meta.self, from: data),
              meta.path == file.standardizedFileURL.path,
              let doc = PDFDocument(url: pdfURL(for: file)), doc.pageCount == meta.pages.count else { return nil }
        return (meta, doc)
    }

    /// Replaces the editable annotations on the journaled pages of `doc` with the journal's. Returns the
    /// restored page indices. The caller must keep `journal` alive while `doc` is in use: the moved annotations'
    /// appearance streams still live in the journal's PDF data. Non-editable annotations (e.g. Preview's shape stamps) are left as they are.
    @discardableResult
    public static func apply(_ journal: PDFDocument, meta: Meta, to doc: PDFDocument) -> [Int] {
        var restored: [Int] = []
        for (k, i) in meta.pages.enumerated() {
            guard i < doc.pageCount, let target = doc.page(at: i), let src = journal.page(at: k) else { continue }
            for a in target.annotations where AnnotationFactory.isEditable(a) { target.removeAnnotation(a) }
            // Move the objects over rather than copying: a copy of an annotation loaded from disk is redrawn by
            // PDFKit (highlights then render slightly differently); the moved object keeps its appearance.
            for a in src.annotations {
                src.removeAnnotation(a)
                AnnotationFactory.restoreOpacity(a)   // read back from a file: markers report opaque colours
                target.addAnnotation(a)
            }
            restored.append(i)
        }
        return restored
    }

    /// Keeps a discarded journal in the Backups folder instead of deleting it, just in case.
    public static func archive(for file: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = SafeSaver.backupDirectory.appendingPathComponent("\(file.deletingPathExtension().lastPathComponent) unsaved annotations \(stamp).pdf")
        try? FileManager.default.moveItem(at: pdfURL(for: file), to: dest)
        delete(for: file)
    }
}

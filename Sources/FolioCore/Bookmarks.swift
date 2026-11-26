import Foundation

/// A place in a document: page index plus the top-left point of the visible area (page coordinates).
public struct Spot: Codable, Equatable {
    public var page: Int
    public var x: Double
    public var y: Double
    public init(page: Int, x: Double = 0, y: Double = 10_000) { self.page = page; self.x = x; self.y = y }
}

public struct Bookmark: Codable, Equatable {
    public var id: String
    public var name: String
    /// nil until the user places it (a new file's Current starts unplaced, so a careless click can't jump to page 1).
    public var spot: Spot?
    public init(id: String, name: String, spot: Spot?) { self.id = id; self.name = name; self.spot = spot }
    public var isPlaced: Bool { spot != nil }
}

/// Bookmarks of one document, modelled on ribbons in a physical book.
///
/// - At most one bookmark is **active**: the one you arrived through. It follows your reading (scrolling,
///   Page Up/Down) like a ribbon you keep moving along.
/// - Going to a bookmark makes it active. Any other jump (page number, search result, link, thumbnail,
///   first/last page) makes none active, so nothing moves by accident; the bar shows no highlight.
/// - **Pin** puts a bookmark where you are and makes it active (one click after "go to page N").
/// - **Back** toggles between the spot before the last jump and where you are, restoring which bookmark
///   was active at each.
public struct BookmarkState: Codable, Equatable {
    public static let maxCount = 4
    public static let currentID = "current"

    public var bookmarks: [Bookmark]
    public var activeID: String?
    public var back: Spot?
    public var backActiveID: String?

    public init(bookmarks: [Bookmark], activeID: String?, back: Spot? = nil, backActiveID: String? = nil) {
        self.bookmarks = bookmarks; self.activeID = activeID; self.back = back; self.backActiveID = backActiveID
    }

    /// A new document: one bookmark, Current, not placed yet. The sidebar asks you to place it.
    public static func initial() -> BookmarkState {
        BookmarkState(bookmarks: [Bookmark(id: currentID, name: "Current", spot: nil)], activeID: nil)
    }

    /// States saved by the first bookmark version had a "Review" that was never placed but sat at the
    /// page-1 default; drop it so nobody jumps to page 1 by accident.
    public mutating func migrate() {
        bookmarks.removeAll { $0.id == "review" && $0.spot == Spot(page: 0) && activeID != "review" }
        if backActiveID.map({ bookmark($0) == nil }) == true { backActiveID = nil }
    }

    public var active: Bookmark? { bookmarks.first { $0.id == activeID } }

    /// Bookmarks in book order: by page, then top to bottom on the page; unplaced ones last (in creation order).
    public var inPageOrder: [Bookmark] {
        bookmarks.enumerated().sorted { l, r in
            switch (l.element.spot, r.element.spot) {
            case let (a?, b?): return a.page != b.page ? a.page < b.page : (a.y != b.y ? a.y > b.y : l.offset < r.offset)
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return l.offset < r.offset
            }
        }.map(\.element)
    }

    /// Creation index (stable): decides a bookmark's ribbon colour.
    public func colorIndex(of id: String) -> Int { bookmarks.firstIndex { $0.id == id } ?? 0 }
    public func bookmark(_ id: String) -> Bookmark? { bookmarks.first { $0.id == id } }
    public var canAdd: Bool { bookmarks.count < Self.maxCount }

    /// Reading moved the view: the active bookmark follows.
    public mutating func follow(_ spot: Spot) {
        guard let i = bookmarks.firstIndex(where: { $0.id == activeID }) else { return }
        bookmarks[i].spot = spot
    }

    /// Going to a bookmark from `here`. Returns where to go (nil: stay). An unplaced bookmark is placed here
    /// instead (like slipping a ribbon in), and clicking the active one does nothing.
    public mutating func jump(to id: String, from here: Spot) -> Spot? {
        guard let b = bookmark(id) else { return nil }
        guard let target = b.spot else { pin(id, at: here); return nil }
        if id == activeID { follow(here); return nil }
        follow(here)
        back = here; backActiveID = activeID
        activeID = id
        return target
    }

    /// Any other jump (page number, search, link, thumbnail) away from `here`: no bookmark follows afterwards.
    public mutating func jumpElsewhere(from here: Spot) {
        follow(here)
        back = here; backActiveID = activeID
        activeID = nil
    }

    /// Puts a bookmark at `here` and makes it the one that follows you. Not a jump: Back is unchanged.
    public mutating func pin(_ id: String, at here: Spot) {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[i].spot = here
        activeID = id
    }

    /// Toggles to the spot before the last jump. Returns where to go.
    public mutating func goBack(from here: Spot) -> Spot? {
        guard let target = back else { return nil }
        follow(here)
        let targetActive = backActiveID
        back = here; backActiveID = activeID
        activeID = targetActive.flatMap { bookmark($0) != nil ? $0 : nil }
        return target
    }

    /// Adds a bookmark at `here` and makes it active, like slipping a new ribbon in. Returns its id.
    @discardableResult
    public mutating func add(name: String, at here: Spot) -> String? {
        guard canAdd else { return nil }
        let id = "b-" + UUID().uuidString.prefix(8).lowercased()
        bookmarks.append(Bookmark(id: id, name: name, spot: here))
        activeID = id
        return id
    }

    public mutating func rename(_ id: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[i].name = n
    }

    /// Removes a bookmark (Current can't be removed).
    public mutating func remove(_ id: String) {
        guard id != Self.currentID else { return }
        bookmarks.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
        if backActiveID == id { backActiveID = nil }
    }

    /// Keeps spots inside a document of `pageCount` pages (e.g. the file was replaced by a shorter one).
    public mutating func clamp(pageCount: Int) {
        let last = max(pageCount - 1, 0)
        for i in bookmarks.indices where (bookmarks[i].spot?.page ?? 0) > last { bookmarks[i].spot = Spot(page: last) }
        if let b = back, b.page > last { back = Spot(page: last) }
    }
}

/// Bookmark states per file, in ~/Library/Application Support/Folio/bookmarks.json (keyed by path).
/// Kept outside the PDF: the active bookmark changes as you scroll, and writing that into the PDF would
/// mean constant multi-second saves and iCloud uploads of big files.
public final class BookmarkStore {
    /// The self-test (FOLIO_SELFTEST=<dir>) keeps its bookmarks in its output folder, away from the user's.
    public static let shared = BookmarkStore(url: ProcessInfo.processInfo.environment["FOLIO_SELFTEST"]
        .map { URL(fileURLWithPath: $0).appendingPathComponent("bookmarks.json") }
        ?? ToolConfig.supportDirectory.appendingPathComponent("bookmarks.json"))

    private let url: URL
    private var states: [String: BookmarkState]
    private let queue = DispatchQueue(label: "folio.bookmarks")
    private var pendingWrite: DispatchWorkItem?

    public init(url: URL) {
        self.url = url
        states = (try? JSONDecoder().decode([String: BookmarkState].self, from: Data(contentsOf: url))) ?? [:]
    }

    /// The state for `fileURL`. If the file was moved or renamed, falls back to the only entry with the
    /// same file name whose path no longer exists, and re-keys it.
    public func state(for fileURL: URL) -> BookmarkState? {
        let key = fileURL.standardizedFileURL.path
        if let s = states[key] { return s }
        let name = fileURL.lastPathComponent
        let orphans = states.keys.filter { URL(fileURLWithPath: $0).lastPathComponent == name && !FileManager.default.fileExists(atPath: $0) }
        guard orphans.count == 1, let s = states.removeValue(forKey: orphans[0]) else { return nil }
        states[key] = s
        scheduleWrite()
        return s
    }

    public func set(_ state: BookmarkState, for fileURL: URL) {
        let key = fileURL.standardizedFileURL.path
        guard states[key] != state else { return }
        states[key] = state
        scheduleWrite()
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        pendingWrite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    /// Writes now (also called on quit).
    public func flush() {
        pendingWrite?.cancel(); pendingWrite = nil
        let snapshot = states
        let url = self.url
        queue.sync {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(snapshot).write(to: url, options: .atomic)
        }
    }
}

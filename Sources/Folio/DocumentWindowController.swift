import AppKit
import PDFKit
import FolioCore

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    AnnotatingPDFViewDelegate, PDFDocumentDelegate, NSSearchFieldDelegate, NSTextFieldDelegate {

    let url: URL
    let pdfDocument: PDFDocument
    let pdfView = AnnotatingPDFView(frame: .zero)
    let thumbnails = PDFThumbnailView(frame: .zero)
    private let split = NSSplitView()
    private var tools: [ToolSpec]
    private let palette: ToolPaletteView
    let pageField = NSTextField()
    private let pageCountLabel = NSTextField(labelWithString: "")
    let searchField = NSSearchField()
    let searchStatus = NSTextField(labelWithString: "")
    private let undo = UndoManager()

    private var dirty = false { didSet { window?.isDocumentEdited = dirty } }
    private var saveTimer: DispatchWorkItem?
    private var backedUp = false
    private var lastSaveDuration: TimeInterval = 0
    private var editGeneration = 0
    private var saveInFlight = false
    private var resaveWanted = false
    private var closed = false
    private var saveFailedShown = false
    private var positionTimer: DispatchWorkItem?

    private var searchQuery = ""
    var searchResults: [PDFSelection] = []
    private var searchIndex = -1
    var searchIndexForTest: Int { searchIndex }
    private var searching = false

    var onClose: ((DocumentWindowController) -> Void)?

    // Bookmarks (see BookmarkState for the rules)
    let bookmarkBar = BookmarkBarView()
    private(set) var bookmarks = BookmarkState.initial(reading: nil)
    private var followTimer: DispatchWorkItem?

    init?(url: URL, tools: [ToolSpec]) {
        guard let doc = PDFDocument(url: url) else { return nil }
        self.url = url
        self.pdfDocument = doc
        self.tools = tools
        self.palette = ToolPaletteView(tools: tools)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 1100),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],  // not full-size: the PDF's "top" must be the visible top (bookmarks, position)
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        window.representedURL = url
        window.title = url.lastPathComponent
        window.setFrameAutosaveName("FolioDocumentWindow")
        window.tabbingMode = .preferred
        setupViews()
        setupToolbar()
        setupBookmarkBar()
        doc.delegate = self
        updatePageField()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Setup

    private func setupViews() {
        pdfView.document = pdfDocument
        pdfView.annotationDelegate = self
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .underPageBackgroundColor

        thumbnails.pdfView = pdfView
        thumbnails.thumbnailSize = NSSize(width: 96, height: 128)
        thumbnails.allowsMultipleSelection = true
        thumbnails.backgroundColor = .windowBackgroundColor

        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(thumbnails)
        split.addArrangedSubview(pdfView)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        window?.contentView = split
        setSidebar(visible: UserDefaults.standard.bool(forKey: "Folio.sidebar"))

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleSavePosition), name: .PDFViewScaleChanged, object: pdfView)

        palette.onSelect = { [weak self] t in self?.select(tool: t) }
    }

    private func setupToolbar() {
        let tb = NSToolbar(identifier: "FolioToolbar")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        window?.toolbar = tb

        pageField.alignment = .right
        pageField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pageField.delegate = self
        pageField.target = self
        pageField.action = #selector(pageFieldEntered)
        pageField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        pageCountLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pageCountLabel.textColor = .secondaryLabelColor

        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(searchEntered)
        searchField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        searchStatus.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        searchStatus.textColor = .secondaryLabelColor
    }

    private enum TB {
        static let sidebar = NSToolbarItem.Identifier("sidebar")
        static let page = NSToolbarItem.Identifier("page")
        static let zoom = NSToolbarItem.Identifier("zoom")
        static let tools = NSToolbarItem.Identifier("tools")
        static let search = NSToolbarItem.Identifier("search")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [TB.sidebar, TB.page, TB.zoom, .flexibleSpace, TB.tools, .flexibleSpace, TB.search]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case TB.sidebar:
            let b = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Thumbnails")!, target: self, action: #selector(toggleSidebar(_:)))
            b.bezelStyle = .texturedRounded
            b.toolTip = "Thumbnails (⌥⌘S)"
            item.view = b
            item.label = "Thumbnails"
        case TB.page:
            let stack = NSStackView(views: [pageField, pageCountLabel])
            stack.spacing = 4
            item.view = stack
            item.label = "Page"
            item.toolTip = "Go to page (⌥⌘G)"
        case TB.zoom:
            let seg = NSSegmentedControl(images: [NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom out")!,
                                                  NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: "Fit width")!,
                                                  NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom in")!],
                                         trackingMode: .momentary, target: self, action: #selector(zoomSegment(_:)))
            seg.setToolTip("Zoom out (⌘-)", forSegment: 0)
            seg.setToolTip("Fit width (⌘9)", forSegment: 1)
            seg.setToolTip("Zoom in (⌘+)", forSegment: 2)
            item.view = seg
            item.label = "Zoom"
        case TB.tools:
            item.view = palette
            item.label = "Tools"
        case TB.search:
            let stack = NSStackView(views: [searchStatus, searchField])
            stack.spacing = 6
            item.view = stack
            item.label = "Search"
        default: return nil
        }
        return item
    }

    // MARK: Tools

    func select(tool: ToolSpec) {
        pdfView.tool = tool
        palette.selectedID = tool.id
    }

    func toolShortcutPressed(_ tool: ToolSpec) {
        // Pressing the active tool's key again returns to the pointer, like putting the pen down.
        select(tool: pdfView.tool.id == tool.id ? .pointer : tool)
    }

    func allTools() -> [ToolSpec] { tools }

    /// Settings changed: rebuild the palette, keep the current tool if it still exists (with its new settings).
    func updateTools(_ newTools: [ToolSpec]) {
        tools = newTools
        palette.reload(tools: newTools)
        select(tool: newTools.first { $0.id == pdfView.tool.id } ?? .pointer)
    }

    @objc func chooseTool(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            select(tool: tools.first { $0.id == id } ?? .pointer)
        }
    }

    // MARK: Autosave

    func annotationsDidChange() {
        editGeneration += 1
        dirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveTimer?.cancel()
        // Saving runs in the background, so the pause only limits how often a big file is rewritten.
        let delay = max(1.5, min(5, lastSaveDuration))
        saveTimer = Debounce.after(delay) { [weak self] in self?.saveNow() }
    }

    /// Starts a save of the current state. The document is snapshotted with `PDFDocument.copy()` (about 1 ms,
    /// independent of later edits; verified) and written on a serial background queue, so a big file's
    /// multi-second rewrite never blocks the window. Edits made meanwhile keep the document dirty and are
    /// saved by a follow-up save.
    func saveNow() {
        saveTimer?.cancel(); saveTimer = nil
        pdfView.endTextEntry(commit: true)
        guard dirty else { return }
        if saveInFlight { resaveWanted = true; return }
        if !backedUp {
            let copy: URL? = Log.timed("backup") { SafeSaver.backup(self.url) }
            backedUp = copy != nil
        }
        let copied: Any = Log.timed("snapshot") { self.pdfDocument.copy() }
        guard let snapshot = copied as? PDFDocument else { return }
        let generation = editGeneration
        let url = self.url
        saveInFlight = true
        SaveQueue.group.enter()
        SaveQueue.queue.async {
            let started = Date()
            var failure: Error?
            do { try SafeSaver.save(snapshot, to: url) } catch { failure = error }
            let duration = Date().timeIntervalSince(started)
            let outcome: String = failure.map { " FAILED: \($0)" } ?? ""
            Log.info("saved \(url.lastPathComponent) in \(String(format: "%.2f", duration)) s (background)\(outcome)")
            DispatchQueue.main.async {
                self.saveFinished(generation: generation, duration: duration, error: failure)
                SaveQueue.group.leave()
            }
        }
    }

    private func saveFinished(generation: Int, duration: TimeInterval, error: Error?) {
        saveInFlight = false
        lastSaveDuration = duration
        if let error {
            FileHandle.standardError.write("Folio: save failed for \(url.path): \(error)\n".data(using: .utf8)!)
            resaveWanted = false
            if !saveFailedShown {
                saveFailedShown = true
                let alert = NSAlert()
                alert.messageText = "Couldn't save “\(url.lastPathComponent)”"
                alert.informativeText = "The file may be locked or read-only. Your annotations are still open here. Save a copy to keep them."
                alert.addButton(withTitle: "Save a Copy…")
                alert.addButton(withTitle: "Later")
                if let w = window, w.isVisible {
                    alert.beginSheetModal(for: w) { [weak self] r in if r == .alertFirstButtonReturn { self?.saveCopy(nil) } }
                } else {
                    alert.runModal()
                }
            }
            return
        }
        saveFailedShown = false
        if generation == editGeneration { dirty = false }
        if dirty {
            if resaveWanted || closed { resaveWanted = false; saveNow() } else { scheduleSave() }
        }
    }

    @objc func saveDocument(_ sender: Any?) { saveNow() }

    @objc func saveCopy(_ sender: Any?) {
        pdfView.endTextEntry(commit: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + " copy.pdf"
        guard let w = window else { return }
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let dest = panel.url, let self else { return }
            if !self.pdfDocument.write(to: dest) {
                NSAlert(error: SaveError.writeFailed).runModal()
            }
        }
    }

    // MARK: Bookmarks

    private func setupBookmarkBar() {
        let acc = NSTitlebarAccessoryViewController()
        acc.view = bookmarkBar
        acc.layoutAttribute = .bottom
        window?.addTitlebarAccessoryViewController(acc)
        bookmarkBar.onGo = { [weak self] id in self?.goToBookmark(id: id) }
        bookmarkBar.onPin = { [weak self] id in self?.pinBookmark(id: id) }
        bookmarkBar.onBack = { [weak self] in self?.goBack(nil) }
        bookmarkBar.onAdd = { [weak self] in self?.addBookmark(nil) }
        bookmarkBar.onRename = { [weak self] id in self?.renameBookmark(id: id) }
        bookmarkBar.onRemove = { [weak self] id in self?.removeBookmark(id: id) }
        pdfView.onJump = { [weak self] in self?.pageJumped() }
        pdfView.onViewMoved = { [weak self] in self?.scheduleFollow() }
    }

    /// Loads this file's bookmarks (after the reading position is restored, so Current starts there).
    private func loadBookmarks() {
        var state = BookmarkStore.shared.state(for: url) ?? .initial(reading: currentSpot())
        state.clamp(pageCount: pdfDocument.pageCount)
        bookmarks = state
        bookmarksChanged()
    }

    /// A bookmark spot is the point a little below the top edge of the visible area (view pixels), so it lands
    /// on the page you see rather than in the gap between pages; `show` puts it back at the same height.
    private let spotInset: CGFloat = 12

    func currentSpot() -> Spot? {
        let b = pdfView.bounds
        let p = NSPoint(x: b.minX + 1, y: pdfView.isFlipped ? b.minY + spotInset : b.maxY - spotInset)
        guard let page = pdfView.page(for: p, nearest: true) else { return nil }
        let pt = pdfView.convert(p, to: page)
        return Spot(page: pdfDocument.index(for: page), x: Double(pt.x), y: Double(pt.y))
    }

    private func show(_ spot: Spot) {
        guard let page = pdfDocument.page(at: min(max(spot.page, 0), pdfDocument.pageCount - 1)) else { return }
        let up = spotInset / max(pdfView.scaleFactor, 0.01)
        pdfView.goQuietly { pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: spot.x, y: spot.y + up))) }
        updatePageField()
    }

    private func bookmarksChanged() {
        followTimer?.cancel(); followTimer = nil
        BookmarkStore.shared.set(bookmarks, for: url)
        bookmarkBar.reload(bookmarks) { [weak self] i in
            guard let self, let p = self.pdfDocument.page(at: i) else { return "\(i + 1)" }
            return p.label ?? "\(i + 1)"
        }
    }

    /// Scrolling / reading: the active bookmark follows (debounced).
    private func scheduleFollow() {
        guard positionRestored, bookmarks.activeID != nil else { return }
        followTimer?.cancel()
        followTimer = Debounce.after(0.3) { [weak self] in self?.followNow() }
    }

    private func followNow() {
        followTimer?.cancel(); followTimer = nil
        guard positionRestored, let here = currentSpot() else { return }
        let before = bookmarks.active?.spot.page
        bookmarks.follow(here)
        BookmarkStore.shared.set(bookmarks, for: url)
        if bookmarks.active?.spot.page != before { bookmarksChanged() }  // tooltips show page numbers
    }

    /// A jump not made through a bookmark: no bookmark follows afterwards.
    private func pageJumped() {
        guard positionRestored, let here = currentSpot() else { return }
        bookmarks.jumpElsewhere(from: here)
        bookmarksChanged()
    }

    func goToBookmark(id: String) {
        guard let here = currentSpot() else { return }
        let target = bookmarks.jump(to: id, from: here)
        bookmarksChanged()
        if let target { show(target) }
    }

    func pinBookmark(id: String) {
        guard let here = currentSpot() else { return }
        bookmarks.pin(id, at: here)
        bookmarksChanged()
    }

    @objc func goToBookmark(_ sender: NSMenuItem) {
        guard sender.tag >= 1, sender.tag <= bookmarks.bookmarks.count else { NSSound.beep(); return }
        goToBookmark(id: bookmarks.bookmarks[sender.tag - 1].id)
    }

    @objc func pinBookmark(_ sender: NSMenuItem) {
        guard sender.tag >= 1, sender.tag <= bookmarks.bookmarks.count else { NSSound.beep(); return }
        pinBookmark(id: bookmarks.bookmarks[sender.tag - 1].id)
    }

    /// Toggles between the spot before the last jump and here.
    @objc func goBack(_ sender: Any?) {
        guard let here = currentSpot(), let target = bookmarks.goBack(from: here) else { NSSound.beep(); return }
        bookmarksChanged()
        show(target)
    }

    @objc func addBookmark(_ sender: Any?) {
        guard bookmarks.canAdd else { NSSound.beep(); return }
        askName(title: "Add a bookmark here", initial: bookmarks.bookmarks.count == 2 ? "Answers" : "Bookmark \(bookmarks.bookmarks.count + 1)") { [weak self] name in
            guard let self, let here = self.currentSpot() else { return }
            self.bookmarks.add(name: name, at: here)
            self.bookmarksChanged()
        }
    }

    func renameBookmark(id: String) {
        guard let b = bookmarks.bookmark(id) else { return }
        askName(title: "Rename bookmark", initial: b.name) { [weak self] name in
            self?.bookmarks.rename(id, to: name)
            self?.bookmarksChanged()
        }
    }

    func removeBookmark(id: String) {
        bookmarks.remove(id)
        bookmarksChanged()
    }

    private func askName(title: String, initial: String, done: @escaping (String) -> Void) {
        guard let w = window else { return }
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: w) { r in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if r == .alertFirstButtonReturn, !name.isEmpty { done(String(name.prefix(24))) }
        }
    }

    // MARK: Position

    @objc private func pageChanged() {
        updatePageField()
        scheduleSavePosition()
    }

    @objc private func scheduleSavePosition() {
        positionTimer?.cancel()
        positionTimer = Debounce.after(0.7) { [weak self] in self?.savePosition() }
    }

    func savePosition() {
        positionTimer?.cancel(); positionTimer = nil
        guard positionRestored else { return } // don't overwrite the saved spot with the initial layout
        guard let dest = pdfView.currentDestination, let page = dest.page else { return }
        let idx = pdfDocument.index(for: page)
        PositionStore.set(ReadingPosition(page: idx, x: Double(dest.point.x), y: Double(dest.point.y),
                                          scale: Double(pdfView.scaleFactor), autoScales: pdfView.autoScales), for: url)
    }

    private var positionRestored = false

    /// Call after the window is on screen, so the view has its final size.
    func restorePosition() {
        defer { positionRestored = true; updatePageField(); loadBookmarks() }
        guard let pos = PositionStore.get(url), pos.page < pdfDocument.pageCount, let page = pdfDocument.page(at: pos.page) else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        if !pos.autoScales { pdfView.autoScales = false; pdfView.scaleFactor = CGFloat(pos.scale) }
        pdfView.layoutDocumentView()
        pdfView.goQuietly { pdfView.go(to: PDFDestination(page: page, at: NSPoint(x: pos.x, y: pos.y))) }
    }

    // MARK: Pages

    private func updatePageField() {
        guard let page = pdfView.currentPage else { return }
        pageField.stringValue = "\(pdfDocument.index(for: page) + 1)"
        pageCountLabel.stringValue = "/ \(pdfDocument.pageCount)"
    }

    @objc func pageFieldEntered() {
        let n = Int(pageField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        if n >= 1, n <= pdfDocument.pageCount, let page = pdfDocument.page(at: n - 1) {
            pdfView.go(to: page)
        } else if let label = pdfDocument.findPage(label: pageField.stringValue) {
            pdfView.go(to: label)
        } else {
            NSSound.beep()
        }
        updatePageField()
        window?.makeFirstResponder(pdfView)
    }

    @objc func goToPage(_ sender: Any?) {
        window?.makeFirstResponder(pageField)
        pageField.selectText(nil)
    }

    @objc func firstPage(_ sender: Any?) { pdfView.goToFirstPage(sender) }
    @objc func lastPage(_ sender: Any?) { pdfView.goToLastPage(sender) }
    @objc func nextPage(_ sender: Any?) { pdfView.goToNextPage(sender) }
    @objc func previousPage(_ sender: Any?) { pdfView.goToPreviousPage(sender) }

    // MARK: View

    @objc func toggleSidebar(_ sender: Any?) {
        setSidebar(visible: thumbnails.isHidden)
        UserDefaults.standard.set(!thumbnails.isHidden, forKey: "Folio.sidebar")
    }

    private func setSidebar(visible: Bool) {
        thumbnails.isHidden = !visible
        split.adjustSubviews()
        split.setPosition(visible ? 150 : 0, ofDividerAt: 0)
    }

    @objc private func zoomSegment(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: zoomOut(sender)
        case 1: fitWidth(sender)
        default: zoomIn(sender)
        }
    }
    @objc func zoomIn(_ sender: Any?) { pdfView.autoScales = false; pdfView.zoomIn(sender) }
    @objc func zoomOut(_ sender: Any?) { pdfView.autoScales = false; pdfView.zoomOut(sender) }
    @objc func actualSize(_ sender: Any?) { pdfView.autoScales = false; pdfView.scaleFactor = 1 }
    @objc func fitWidth(_ sender: Any?) { pdfView.autoScales = true }
    @objc func singlePage(_ sender: Any?) { pdfView.displayMode = .singlePageContinuous }
    @objc func twoPages(_ sender: Any?) { pdfView.displayMode = .twoUpContinuous }

    // MARK: Search

    @objc func performFind(_ sender: Any?) {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    @objc func searchEntered() {
        let q = searchField.stringValue
        if q.isEmpty { clearSearch(); return }
        if q == searchQuery, !searchResults.isEmpty {
            let back = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            step(back ? -1 : 1)
            return
        }
        pdfDocument.cancelFindString()
        searchQuery = q
        searchResults = []
        searchIndex = -1
        searching = true
        searchStatus.stringValue = "Searching…"
        pdfView.highlightedSelections = nil
        pdfDocument.beginFindString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    private func clearSearch() {
        pdfDocument.cancelFindString()
        searchQuery = ""; searchResults = []; searchIndex = -1
        pdfView.highlightedSelections = nil
        searchStatus.stringValue = ""
    }

    func didMatchString(_ instance: PDFSelection) {
        instance.color = NSColor.systemYellow.withAlphaComponent(0.5)
        searchResults.append(instance)
        if searchIndex < 0 { searchIndex = 0; show(instance) }
        if searchResults.count % 50 == 1 { updateSearchStatus() }
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        searching = false
        if searchResults.count <= 2000 { pdfView.highlightedSelections = searchResults }
        updateSearchStatus()
    }

    private func updateSearchStatus() {
        if searchResults.isEmpty { searchStatus.stringValue = searching ? "Searching…" : "Not found"; return }
        searchStatus.stringValue = "\(searchIndex + 1) of \(searchResults.count)\(searching ? "+" : "")"
    }

    private func step(_ d: Int) {
        guard !searchResults.isEmpty else { NSSound.beep(); return }
        searchIndex = (searchIndex + d + searchResults.count) % searchResults.count
        show(searchResults[searchIndex])
        updateSearchStatus()
    }

    private func show(_ sel: PDFSelection) {
        pdfView.setCurrentSelection(sel, animate: false)
        pdfView.jumping { pdfView.go(to: sel) }
    }

    @objc func findNext(_ sender: Any?) { if searchQuery.isEmpty { performFind(sender) } else { step(1) } }
    @objc func findPrevious(_ sender: Any?) { if searchQuery.isEmpty { performFind(sender) } else { step(-1) } }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if control === searchField, sel == #selector(NSResponder.cancelOperation(_:)) {
            searchField.stringValue = ""; clearSearch(); window?.makeFirstResponder(pdfView); return true
        }
        if control === pageField, sel == #selector(NSResponder.cancelOperation(_:)) {
            updatePageField(); window?.makeFirstResponder(pdfView); return true
        }
        return false
    }

    // MARK: Print

    @objc func printDocument(_ sender: Any?) {
        pdfView.endTextEntry(commit: true)
        runPrint(pdfDocument)
    }

    @objc func printSelectedPages(_ sender: Any?) {
        pdfView.endTextEntry(commit: true)
        let pages = thumbnails.selectedPages ?? []
        guard !thumbnails.isHidden, !pages.isEmpty else {
            let a = NSAlert()
            a.messageText = "Select pages in the thumbnail sidebar first"
            a.informativeText = "Open the sidebar (⌥⌘S), then ⌘-click or ⇧-click thumbnails. For a simple range, use File ▸ Print and the Pages field."
            if thumbnails.isHidden { toggleSidebar(nil) }
            a.beginSheetModal(for: window!)
            return
        }
        let sub = PDFDocument()
        let sorted = pages.sorted { pdfDocument.index(for: $0) < pdfDocument.index(for: $1) }
        for (i, p) in sorted.enumerated() {
            if let copy = p.copy() as? PDFPage { sub.insert(copy, at: i) }
        }
        runPrint(sub)
    }

    private func runPrint(_ doc: PDFDocument) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .spool
        guard let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { NSSound.beep(); return }
        op.jobTitle = url.deletingPathExtension().lastPathComponent
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.printPanel.options.insert([.showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation, .showsScaling, .showsPreview])
        op.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Window

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }

    func windowDidResignKey(_ notification: Notification) {
        if dirty { saveNow() }
        savePosition()
    }

    func windowWillClose(_ notification: Notification) {
        followNow()
        closed = true
        saveNow()
        savePosition()
        pdfDocument.cancelFindString()
        onClose?(self)
    }

    /// Called on app quit / deactivate.
    func flush() {
        followNow()
        if dirty { saveNow() }
        savePosition()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(chooseTool(_:)):
            item.state = (item.representedObject as? String) == pdfView.tool.id ? .on : .off
        case #selector(toggleSidebar(_:)):
            item.title = thumbnails.isHidden ? "Show Thumbnails" : "Hide Thumbnails"
        case #selector(singlePage(_:)):
            item.state = pdfView.displayMode == .singlePageContinuous ? .on : .off
        case #selector(twoPages(_:)):
            item.state = pdfView.displayMode == .twoUpContinuous ? .on : .off
        case #selector(goBack(_:)): return bookmarks.back != nil
        case #selector(goToBookmark(_:)):
            guard item.tag <= bookmarks.bookmarks.count else { item.title = "Bookmark \(item.tag)"; return false }
            let b = bookmarks.bookmarks[item.tag - 1]
            item.title = "Go to “\(b.name)”"
            item.state = b.id == bookmarks.activeID ? .on : .off
        case #selector(pinBookmark(_:)):
            guard item.tag <= bookmarks.bookmarks.count else { item.title = "Move Bookmark \(item.tag) Here"; return false }
            item.title = "Move “\(bookmarks.bookmarks[item.tag - 1].name)” Here"
        case #selector(addBookmark(_:)): return bookmarks.canAdd
        default: break
        }
        return true
    }
}

private extension PDFDocument {
    func findPage(label: String) -> PDFPage? {
        let l = label.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return nil }
        for i in 0..<pageCount { if let p = page(at: i), p.label == l { return p } }
        return nil
    }
}

/// GCD-based debounce: runs on the main queue even during mouse tracking / scrolling and isn't
/// subject to run-loop mode or timer coalescing the way Timer is.
/// Background saves. Serial, so writes to the same file never overlap; the group lets quit wait for them.
enum SaveQueue {
    static let queue = DispatchQueue(label: "folio.save", qos: .userInitiated)
    static let group = DispatchGroup()

    /// Blocks until every started save (including follow-ups they trigger) has finished. Used at quit.
    static func waitForAll() {
        while group.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

enum Debounce {
    static func after(_ seconds: Double, _ f: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: f)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }
}

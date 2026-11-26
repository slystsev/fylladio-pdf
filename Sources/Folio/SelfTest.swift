import AppKit
import PDFKit
import FolioCore

/// Drives the real UI with synthetic events. Enabled with env FOLIO_SELFTEST=<outDir> and a PDF argument.
/// Writes PNG snapshots of Folio's own window and report.txt, then quits.
final class SelfTest {
    let out: URL
    let app: AppDelegate
    var log: [String] = []
    var failures = 0

    init(out: URL, app: AppDelegate) {
        self.out = out; self.app = app
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func check(_ ok: Bool, _ msg: String) { log.append((ok ? "PASS " : "FAIL ") + msg); if !ok { failures += 1 } }

    var c: DocumentWindowController { app.controllersForTest.first! }
    var view: AnnotatingPDFView { c.pdfView }

    func snap(_ name: String) {
        guard let w = c.window, let v = w.contentView?.superview ?? w.contentView else { return }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
        // PDFKit's tiled layers don't show up in cacheDisplay, so also render the current page with its annotations.
        if let page = view.currentPage {
            let img = page.thumbnail(of: NSSize(width: 900, height: 1200), for: .mediaBox)
            if let t = img.tiffRepresentation, let r = NSBitmapImageRep(data: t) {
                try? r.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + "-page.png"))
            }
        }
    }

    func windowPoint(page: Int, _ p: NSPoint) -> NSPoint {
        let pg = view.document!.page(at: page)!
        return view.convert(view.convert(p, from: pg), to: nil)
    }

    func mouse(_ type: NSEvent.EventType, _ wp: NSPoint, mods: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: wp, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: c.window!.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    func key(_ chars: String, code: UInt16 = 0) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: c.window!.windowNumber, context: nil, characters: chars,
                                 charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        view.keyDown(with: e)
    }

    func drag(page: Int, from a: NSPoint, to b: NSPoint, mods: NSEvent.ModifierFlags = []) {
        let wa = windowPoint(page: page, a), wb = windowPoint(page: page, b)
        view.mouseDown(with: mouse(.leftMouseDown, wa, mods: mods))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: (wa.x + wb.x) / 2, y: (wa.y + wb.y) / 2), mods: mods))
        view.mouseDragged(with: mouse(.leftMouseDragged, wb, mods: mods))
        view.mouseUp(with: mouse(.leftMouseUp, wb, mods: mods))
    }

    func dragPath(page: Int, _ pts: [NSPoint], mods: NSEvent.ModifierFlags = []) {
        let w = pts.map { windowPoint(page: page, $0) }
        view.mouseDown(with: mouse(.leftMouseDown, w[0], mods: mods))
        for p in w.dropFirst() { view.mouseDragged(with: mouse(.leftMouseDragged, p, mods: mods)) }
        view.mouseUp(with: mouse(.leftMouseUp, w.last!, mods: mods))
    }

    func last(_ page: Int) -> PDFAnnotation? { view.document!.page(at: page)!.annotations.last }

    func click(page: Int, _ p: NSPoint, clicks: Int = 1) {
        let w = windowPoint(page: page, p)
        view.mouseDown(with: mouse(.leftMouseDown, w, clicks: clicks))
        view.mouseUp(with: mouse(.leftMouseUp, w, clicks: clicks))
    }

    func annCount(_ page: Int) -> Int { view.document!.page(at: page)!.annotations.count }

    var activity: NSObjectProtocol?

    func run() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "self-test")
        let steps: [(Double, () -> Void)] = [
            (1.0, { [self] in
                c.window?.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 1000), display: true)
                view.go(to: view.document!.page(at: 0)!)
                view.autoScales = true
            }),
            (0.8, { [self] in snap("01-open") }),
            (0.2, { [self] in
                let base = annCount(0)
                key("1"); check(view.tool.id == "marker-yellow", "key 1 selects yellow marker")
                drag(page: 0, from: NSPoint(x: 52, y: 745), to: NSPoint(x: 400, y: 745))
                check(annCount(0) == base + 1, "text highlight added")
                check(view.document!.page(at: 0)!.annotations.last?.type == "Highlight", "it is a Highlight")
                key("2"); drag(page: 0, from: NSPoint(x: 200, y: 723), to: NSPoint(x: 150, y: 679))
                let q = view.document!.page(at: 0)!.annotations.last?.quadrilateralPoints?.count ?? 0
                check(q == 12, "multi-line green highlight has 3 quads (got \(q / 4))")
                key("5"); drag(page: 0, from: NSPoint(x: 52, y: 657), to: NSPoint(x: 300, y: 657))
                key("6"); drag(page: 0, from: NSPoint(x: 52, y: 635), to: NSPoint(x: 300, y: 635))
                key("7"); drag(page: 0, from: NSPoint(x: 52, y: 613), to: NSPoint(x: 300, y: 613))
                key("8"); drag(page: 0, from: NSPoint(x: 52, y: 591), to: NSPoint(x: 300, y: 591))
                // Rectangle on the "scan" (starts on non-text), and a forced rect with Option over text
                key("4"); drag(page: 0, from: NSPoint(x: 62, y: 190), to: NSPoint(x: 380, y: 220))
                check(view.document!.page(at: 0)!.annotations.last?.quadrilateralPoints?.count == 4, "rect highlight on image")
                key("3"); drag(page: 0, from: NSPoint(x: 300, y: 560), to: NSPoint(x: 420, y: 520), mods: .option)
                key("5"); drag(page: 0, from: NSPoint(x: 62, y: 160), to: NSPoint(x: 380, y: 175))
                check(annCount(0) == base + 9, "9 markups added (got \(annCount(0) - base))")
                // Text note
                key("9"); check(view.tool.kind == .text, "key 9 selects text")
                click(page: 0, NSPoint(x: 420, y: 270))
                if let tv = c.window?.firstResponder as? NSTextView {
                    tv.insertText("Hello note", replacementRange: tv.selectedRange())
                    tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                } else { check(false, "text editor opened") }
                check(view.document!.page(at: 0)!.annotations.last?.type == "FreeText", "free text added")
                if let note = view.document!.page(at: 0)!.annotations.last {
                    check(abs(note.bounds.midY - 270) < 1, "note's line is centred on the click (midY \(note.bounds.midY))")
                }
                key("0"); click(page: 0, NSPoint(x: 420, y: 240))
                if let tv = c.window?.firstResponder as? NSTextView {
                    tv.insertText("Red one", replacementRange: tv.selectedRange())
                }
                snap("02-editing-text")
            }),
            (0.3, { [self] in
                click(page: 0, NSPoint(x: 500, y: 100)) // commits red note, starts a new empty editor
                view.endTextEntry(commit: false)
                check(view.document!.page(at: 0)!.annotations.contains { $0.contents == "Red one" }, "red note committed by clicking elsewhere")
                view.tool = .pointer; c.select(tool: .pointer)
                snap("03-annotated")
                // Either still pending, or already saved because the window lost focus (resign-key saves at once).
                let onDisk = PDFDocument(url: c.url)!.page(at: 0)!.annotations.count == annCount(0)
                check(c.window?.isDocumentEdited == true || onDisk, "edit pending or already saved")
            }),
            (2.5, { [self] in
                check(c.window?.isDocumentEdited == false, "autosaved after idle")
                let disk = PDFDocument(url: c.url)!
                check(disk.page(at: 0)!.annotations.count == annCount(0), "disk annotations match view (\(disk.page(at: 0)!.annotations.count))")
                // Select + delete + undo
                let before = annCount(0)
                click(page: 0, NSPoint(x: 100, y: 205))
                check(view.selectedAnnotation != nil, "click selects annotation")
                snap("04-selected")
                key("\u{7f}", code: 51)
                check(annCount(0) == before - 1, "delete removes annotation")
            }),
            (0.1, { [self] in
                let before = annCount(0) + 1
                let um = c.window!.undoManager!
                log.append("INFO undo canUndo=\(um.canUndo) level=\(um.groupingLevel) name=\(um.undoActionName) same=\(um === view.undoManager)")
                um.undo()
                check(annCount(0) == before, "undo restores annotation")
                c.window?.undoManager?.redo()
                check(annCount(0) == before - 1, "redo deletes again")
                c.window?.undoManager?.undo()
                check(annCount(0) == before, "undo again restores")
                // Edit a text note via double-click
                view.tool = .pointer
                let note = view.document!.page(at: 0)!.annotations.first { $0.contents == "Hello note" }!
                click(page: 0, NSPoint(x: note.bounds.midX, y: note.bounds.midY), clicks: 2)
                if let tv = c.window?.firstResponder as? NSTextView {
                    tv.string = "Edited note"; tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                }
                check(view.document!.page(at: 0)!.annotations.contains { $0.contents == "Edited note" }, "double-click edits note")
            }),
            (0.2, { [self] in
                // Underline on a non-text area: a free line from point to point, snapped flat when nearly horizontal.
                key("5"); drag(page: 0, from: NSPoint(x: 70, y: 110), to: NSPoint(x: 370, y: 114))
                check(last(0)?.type == "Ink" && (last(0)?.bounds.height ?? 99) < 8, "near-horizontal free underline snapped flat")
                key("7"); drag(page: 0, from: NSPoint(x: 400, y: 90), to: NSPoint(x: 540, y: 150))
                check((last(0)?.bounds.height ?? 0) > 50, "steep curly line follows the drag")
                // Pen: freehand stroke
                key("q"); check(view.tool.kind == .pen, "key q selects pen")
                var stroke: [NSPoint] = []
                for i in 0...30 { let a = Double(i) / 30 * 2 * .pi; stroke.append(NSPoint(x: 470 + 45 * cos(a), y: 420 + 22 * sin(a))) }
                dragPath(page: 0, stroke)
                let pen = last(0)
                check(pen.flatMap { AnnotationFactory.kind(of: $0) } == .pen, "pen stroke added")
                key("\u{1b}", code: 53)
                check(view.tool.kind == .select, "Esc returns to pointer")
            }),
            (0.2, { [self] in
                // Move the pen stroke by dragging it in pointer mode
                let pen = view.document!.page(at: 0)!.annotations.last { AnnotationFactory.kind(of: $0) == .pen }!
                let before = pen.bounds
                dragPath(page: 0, [NSPoint(x: 515, y: 420), NSPoint(x: 500, y: 400), NSPoint(x: 465, y: 380)])
                check(abs(pen.bounds.minX - (before.minX - 50)) < 0.5 && abs(pen.bounds.minY - (before.minY - 40)) < 0.5,
                      "drag moves annotation by (-50,-40) (got \(pen.bounds.minX - before.minX), \(pen.bounds.minY - before.minY))")
                snap("08-moved")
            }),
            (0.1, { [self] in
                let pen = view.selectedAnnotation!
                let x = pen.bounds.minX
                key("", code: 124)
                check(abs(pen.bounds.minX - (x + 1)) < 0.01, "right arrow nudges 1pt")
                c.window?.undoManager?.undo()
                check(abs(pen.bounds.minX - x) < 0.01, "undo nudge")
            }),
            (0.1, { [self] in
                let pen = view.selectedAnnotation!
                c.window?.undoManager?.undo()
                check(abs(pen.bounds.midX - 470) < 3, "undo move puts stroke back")
            }),
            (0.1, { [self] in
                // Resize: drag the right-edge handle of the selected stroke 60 view points to the right.
                let pen = view.selectedAnnotation!
                let before = pen.bounds
                let r = view.convert(pen.bounds, from: pen.page!).insetBy(dx: -3, dy: -3)
                let a = view.convert(NSPoint(x: r.maxX, y: r.midY), to: nil)
                let b = NSPoint(x: a.x + 60, y: a.y)
                view.mouseDown(with: mouse(.leftMouseDown, a))
                view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: a.x + 30, y: a.y)))
                view.mouseDragged(with: mouse(.leftMouseDragged, b))
                view.mouseUp(with: mouse(.leftMouseUp, b))
                let grew = pen.bounds.width - before.width, expected = 60 / view.scaleFactor
                let box = pen.paths!.map(\.bounds).reduce(pen.paths![0].bounds) { $0.union($1) }
                check(abs(grew - expected) < 1 && abs(pen.bounds.minX - before.minX) < 0.01,
                      "right handle widens stroke by \(String(format: "%.1f", expected)) pt (got \(String(format: "%.1f", grew)))")
                check(box.maxX <= pen.bounds.width + 0.01 && box.width > before.width - 10, "stroke path scaled with its bounds")
                snap("08b-resized")
            }),
            (0.1, { [self] in
                let pen = view.selectedAnnotation!
                c.window?.undoManager?.undo()
                check(abs(pen.bounds.midX - 470) < 3 && pen.bounds.width < 110, "undo resize restores size (\(pen.bounds.width))")
            }),
            (0.1, { [self] in
                // Cross-page move: show the bottom of page 1 and top of page 2, draw a stroke low on page 1, drag it onto page 2.
                let p0 = view.document!.page(at: 0)!
                view.go(to: PDFDestination(page: p0, at: NSPoint(x: 0, y: 250)))
                key("q")
                dragPath(page: 0, [NSPoint(x: 300, y: 120), NSPoint(x: 340, y: 130), NSPoint(x: 380, y: 120)])
                key("\u{1b}", code: 53)
            }),
            (0.1, { [self] in
                // Separate step, so drawing and moving are separate undo groups.
                let p0 = view.document!.page(at: 0)!, p1 = view.document!.page(at: 1)!
                let stroke = p0.annotations.last!
                let n0 = p0.annotations.count, n1 = p1.annotations.count
                // Grab the stroke exactly on its path (sweep down at x = 340 until the strict hit test fires).
                let grabY = stride(from: stroke.bounds.maxY, through: stroke.bounds.minY, by: -0.25)
                    .first { AnnotationFactory.hits(stroke, at: NSPoint(x: 340, y: $0), tolerance: 1) } ?? 0
                let a = windowPoint(page: 0, NSPoint(x: 340, y: grabY)), b = windowPoint(page: 1, NSPoint(x: 340, y: 700))
                let hit = grabY > 0
                let grabOffset = grabY - stroke.bounds.minY
                check(AnnotationFactory.kind(of: stroke) == .pen && hit && view.tool.kind == .select,
                      "stroke for cross-page test drawn (kind \(String(describing: AnnotationFactory.kind(of: stroke))), hit \(hit), tool \(view.tool.kind), bounds \(stroke.bounds))")
                let va = view.convert(a, from: nil)
                let pg = view.page(for: va, nearest: true)
                let pp = pg.map { view.convert(va, to: $0) } ?? .zero
                guard hit, pg === p0, AnnotationFactory.hits(stroke, at: pp, tolerance: 2) else { check(false, "cross-page drag start not on stroke"); return }
                view.mouseDown(with: mouse(.leftMouseDown, a))
                view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: a.x, y: (a.y + b.y) / 2)))
                view.mouseDragged(with: mouse(.leftMouseDragged, b))
                view.mouseUp(with: mouse(.leftMouseUp, b))
                check(stroke.page === p1 && p0.annotations.count == n0 - 1 && p1.annotations.count == n1 + 1,
                      "drag moves annotation from page 1 to page 2")
                check(abs(stroke.bounds.minY + grabOffset - 700) < 1, "grabbed point lands where dropped on page 2 (\(stroke.bounds.minY + grabOffset))")
                snap("08c-cross-page")
            }),
            (0.1, { [self] in
                let p0 = view.document!.page(at: 0)!
                let stroke = view.selectedAnnotation!
                c.window?.undoManager?.undo()
                check(stroke.page === p0 && abs(stroke.bounds.midY - 122.5) < 3, "undo returns it to page 1 (midY \(stroke.bounds.midY))")
            }),
            (2.2, { [self] in
                let disk = PDFDocument(url: c.url)!.page(at: 0)!.annotations
                check(disk.contains { AnnotationFactory.kind(of: $0) == .pen && abs($0.bounds.midX - 470) < 3 }, "pen stroke autosaved at its position")
                // Settings: add a 4th pen, recolour black pen; palette and shortcuts follow
                var t = app.tools
                t.insert(ToolSpec(id: "pen-green", kind: .pen, name: "Green pen", color: "22AA22", key: "r", width: 2), at: t.lastIndex { $0.kind == .pen }! + 1)
                app.apply(tools: t)
                check(c.allTools().count == t.count, "window got new tools")
                key("r"); check(view.tool.id == "pen-green", "new pen shortcut works")
                key("\u{1b}", code: 53)
                app.showSettings(nil)
            }),
            (0.6, { [self] in
                if let w = NSApp.windows.first(where: { $0.title == "Tools" }), let v = w.contentView {
                    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("09-settings.png"))
                    check(true, "settings window opens")
                    w.close()
                } else { check(false, "settings window opens") }
                app.apply(tools: ToolConfig.defaults)
            }),
            (0.1, { [self] in
                // Search
                c.searchField.stringValue = "line 7"
                c.searchEntered()
            }),
            (1.5, { [self] in
                check(c.searchResults.count == view.document!.pageCount, "search found \(c.searchResults.count) results")
                snap("05-search")
                c.searchEntered() // next
                let r1 = c.searchResults[1], p1 = r1.pages.first!
                let shown = view.convert(r1.bounds(for: p1), from: p1)
                check(c.searchIndexForTest == 1 && view.document!.index(for: p1) == 1 && view.bounds.contains(shown),
                      "next result (page 2) is on screen")
                c.pageField.stringValue = "30"
                c.pageFieldEntered()
            }),
            (0.5, { [self] in
                let idx = view.currentPage.map { view.document!.index(for: $0) } ?? -1
                check(idx == 29, "go to page 30 (at \(idx + 1))")
                check(c.pdfDocument.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) != nil, "print operation available")
                snap("06-page30")
                let url = c.url
                c.window?.performClose(nil)
                app.open(url)
            }),
            (1.0, { [self] in
                let idx = view.currentPage.map { view.document!.index(for: $0) } ?? -1
                check(idx == 29, "position restored on reopen (page \(idx + 1))")
                check(annCount(0) > 5, "annotations present after reopen")
                snap("07-reopened")
            }),
            // Bookmarks: physical-book rules in the real window (sidebar on the left).
            (0.3, { [self] in
                let sb = c.bookmarkSidebar
                check(sb.rows.keys.sorted() == ["current"] && c.bookmarks.bookmark("current")?.spot == nil, "new file: one bookmark, Current, unplaced")
                check(!sb.statusLabel.stringValue.isEmpty, "sidebar asks to place Current")
                check(c.ribbonsForTest.isEmpty, "no ribbons before placing")
                sb.rows["current"]!.performClick()
                check(view.currentPage.map { view.document!.index(for: $0) } == 29 && c.bookmarks.activeID == "current" && c.bookmarks.bookmark("current")?.spot?.page == 29,
                      "clicking unplaced Current places it on page 30, no jump")
                check(c.ribbonsForTest.count == 1 && c.ribbonsForTest[0].active, "active ribbon shown")
                c.nextPage(nil)   // reading on (Page Down)
            }),
            (0.6, { [self] in
                check(c.bookmarks.activeID == "current" && c.bookmarks.bookmark("current")?.spot?.page == 30, "Current follows reading to page 31")
                c.pageField.stringValue = "45"; c.pageFieldEntered()
            }),
            (0.6, { [self] in
                check(view.currentPage.map { view.document!.index(for: $0) } == 44, "page field jumps to 45")
                check(c.bookmarks.activeID == nil && c.bookmarks.bookmark("current")?.spot?.page == 30, "page jump: no bookmark follows, Current stays on 31")
                check(!c.bookmarkSidebar.statusLabel.stringValue.isEmpty, "sidebar says nothing moves with you")
                c.addBookmark(named: "Answers")
                let ans = c.bookmarks.bookmarks.last!
                check(ans.name == "Answers" && ans.spot?.page == 44 && c.bookmarks.activeID == ans.id, "new bookmark goes on this page and moves with you")
                c.bookmarkSidebar.rows["current"]!.performClick()
            }),
            (0.6, { [self] in
                check(view.currentPage.map { view.document!.index(for: $0) } == 30 && c.bookmarks.activeID == "current", "Current click returns to page 31")
                c.bookmarkSidebar.backButton.performClick(nil)
            }),
            (0.6, { [self] in
                check(view.currentPage.map { view.document!.index(for: $0) } == 44 && c.bookmarks.active?.name == "Answers", "Back returns to Answers, which moves with you again")
                view.go(to: view.document!.page(at: 9)!)   // like a thumbnail or link
            }),
            (0.6, { [self] in
                check(c.bookmarks.activeID == nil && c.bookmarks.bookmark("current")?.spot?.page == 30, "thumbnail/link jump leaves bookmarks in place")
                let ansID = c.bookmarks.bookmarks.last!.id
                c.bookmarkSidebar.pinButtons[ansID]!.performClick(nil)
                check(c.bookmarks.activeID == ansID && c.bookmarks.bookmark(ansID)?.spot?.page == 9, "one-click pin moves Answers to page 10")
                check(c.ribbonsForTest.count == 2 && c.ribbonsForTest.filter(\.active).count == 1, "two ribbons, one active")
                snap("09-bookmarks")
                let col = c.bookmarkSidebar.superview!
                if let rep = col.bitmapImageRepForCachingDisplay(in: col.bounds) {
                    col.cacheDisplay(in: col.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("09-sidebar.png"))
                }
                check(col.frame.width >= 140 && col.frame.width <= 320, "left column is narrow (\(Int(col.frame.width)) px)")
                BookmarkStore.shared.flush()
                check(BookmarkStore(url: out.appendingPathComponent("bookmarks.json")).state(for: c.url) == c.bookmarks, "bookmarks saved")
                // Deliberate main-thread stall: the watchdog must log it and take a stack sample.
                Thread.sleep(forTimeInterval: 1.8)
            }),
            (9.0, { [self] in
                let logText = (try? String(contentsOf: Log.fileURL, encoding: .utf8)) ?? ""
                let tail = logText.split(separator: "\n").suffix(40).joined(separator: "\n")
                check(tail.contains("HANG main thread unresponsive"), "watchdog logged the stall")
                check(tail.contains("HANG ended after"), "watchdog logged the stall's end")
                let samples = (try? FileManager.default.contentsOfDirectory(atPath: Log.directory.path))?.filter { $0.hasPrefix("hang-") } ?? []
                check(!samples.isEmpty, "stack sample written (\(samples.count))")
                finish()
            }),
        ]
        runStep(steps, 0)
    }

    /// Each step's delay counts from the end of the previous step.
    private func runStep(_ steps: [(Double, () -> Void)], _ i: Int) {
        guard i < steps.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + steps[i].0) { [self] in
            FileHandle.standardError.write("step \(i) start\n".data(using: .utf8)!)
            steps[i].1()
            try? log.joined(separator: "\n").write(to: out.appendingPathComponent("progress.txt"), atomically: true, encoding: .utf8)
            // Real events close NSUndoManager's per-event group; post one so steps behave like separate user actions.
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(e, atStart: false)
            }
            runStep(steps, i + 1)
        }
    }

    func finish() {
        log.append(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
        try? log.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}

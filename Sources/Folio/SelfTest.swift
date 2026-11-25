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
                check(c.window?.isDocumentEdited == true, "document marked edited")
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
                // Search
                c.searchField.stringValue = "line 7"
                c.searchEntered()
            }),
            (1.5, { [self] in
                check(c.searchResults.count == view.document!.pageCount, "search found \(c.searchResults.count) results")
                snap("05-search")
                c.searchEntered() // next
                check(view.currentPage.map { view.document!.index(for: $0) } == 1, "next result goes to page 2")
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

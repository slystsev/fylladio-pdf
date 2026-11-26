import AppKit
import PDFKit
import FolioCore

// Headless self-check. Usage: FolioCheck [outDir] [largePages]
let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : NSTemporaryDirectory() + "folio-check")
let largePages = args.count > 2 ? Int(args[2]) ?? 2000 : 2000
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var failures = 0
func check(_ cond: Bool, _ msg: String) { print((cond ? "PASS " : "FAIL ") + msg); if !cond { failures += 1 } }
func time<T>(_ label: String, _ f: () throws -> T) rethrows -> T {
    let t = Date(); let r = try f(); print(String(format: "TIME %@: %.3fs", label, Date().timeIntervalSince(t))); return r
}

/// Makes a PDF with text lines and a grey "scanned image" box.
func makePDF(_ url: URL, pages: Int, withImage: Bool = true) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    for p in 0..<pages {
        ctx.beginPDFPage(nil)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Helvetica", size: 14)!]
        for i in 0..<20 {
            NSAttributedString(string: "Page \(p + 1) line \(i + 1): The quick brown fox jumps over the lazy dog.", attributes: attrs)
                .draw(at: NSPoint(x: 50, y: 740 - CGFloat(i) * 22))
        }
        if withImage {
            NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 50, y: 80, width: 500, height: 200).fill()
            NSColor.black.setFill(); NSRect(x: 70, y: 200, width: 300, height: 12).fill() // "scanned text" bar
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

func render(_ page: PDFPage, to url: URL) {
    let img = page.thumbnail(of: NSSize(width: 1224, height: 1584), for: .mediaBox)
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
}

let tools = ToolConfig.defaults
func tool(_ id: String) -> ToolSpec { tools.first { $0.id == id }! }

// 1. Annotate small doc: text-based and rectangle-based markups + free text.
let small = outDir.appendingPathComponent("small.pdf")
try? FileManager.default.removeItem(at: small)
makePDF(small, pages: 3)
let doc = PDFDocument(url: small)!
let page = doc.page(at: 0)!
check(AnnotationFactory.hasCharacter(on: page, at: NSPoint(x: 52, y: 745)), "character found at text point")
check(!AnnotationFactory.hasCharacter(on: page, at: NSPoint(x: 300, y: 150)), "no character inside image box")

let rows: [(String, Int)] = [("marker-yellow", 0), ("marker-green", 1), ("underline-red", 3), ("underline-blue", 4), ("squiggly-red", 6), ("squiggly-blue", 7)]
for (id, line) in rows {
    let y = 740 - CGFloat(line) * 22
    let sel = doc.selection(from: page, at: NSPoint(x: 52, y: y + 5), to: page, at: NSPoint(x: 400, y: y + 5))!
    let rects = sel.selectionsByLine().map { $0.bounds(for: page) }
    check(!(sel.string ?? "").isEmpty, "text selection for \(id): \(sel.string ?? "")")
    let t = tool(id)
    let ann = t.kind == .marker ? AnnotationFactory.highlight(tool: t, rects: rects)!
        : AnnotationFactory.line(tool: t, segments: AnnotationFactory.segmentsUnder(lines: rects, kind: t.kind))!
    page.addAnnotation(ann)
}
// Multi-line selection
let multi = doc.selection(from: page, at: NSPoint(x: 200, y: 740 - 9 * 22 + 5), to: page, at: NSPoint(x: 150, y: 740 - 11 * 22 + 5))!
let mrects = multi.selectionsByLine().map { $0.bounds(for: page) }
check(mrects.count == 3, "multi-line selection yields 3 line rects (got \(mrects.count))")
page.addAnnotation(AnnotationFactory.highlight(tool: tool("marker-pink"), rects: mrects)!)
// Rectangle markups on the "scan"
page.addAnnotation(AnnotationFactory.highlight(tool: tool("marker-blue"), rects: [NSRect(x: 65, y: 195, width: 310, height: 22)])!)
// Point-to-point lines on the "scan": straight, curly, and a slanted one
page.addAnnotation(AnnotationFactory.line(tool: tool("underline-red"), segments: [(NSPoint(x: 65, y: 160), NSPoint(x: 375, y: 160))])!)
page.addAnnotation(AnnotationFactory.line(tool: tool("squiggly-blue"), segments: [(NSPoint(x: 65, y: 120), NSPoint(x: 375, y: 120))])!)
page.addAnnotation(AnnotationFactory.line(tool: tool("squiggly-red"), segments: [(NSPoint(x: 400, y: 100), NSPoint(x: 540, y: 160))])!)
// Freehand: a hand-drawn loop with sparse, jittery samples
var loop: [NSPoint] = []
for i in 0...24 { let a = Double(i) / 24 * 2 * .pi; loop.append(NSPoint(x: 470 + 40 * cos(a) + Double(i % 3) * 0.8, y: 380 + 25 * sin(a))) }
let pen = AnnotationFactory.freehand(tool: tool("pen-blue"), points: loop)!
page.addAnnotation(pen)
check(AnnotationFactory.hits(pen, at: NSPoint(x: 510, y: 380)), "pen stroke hit on path")
check(!AnnotationFactory.hits(pen, at: NSPoint(x: 470, y: 380)), "pen stroke not hit in loop's empty middle")
// Moving: a highlight, an ink line and a note
let movable = AnnotationFactory.highlight(tool: tool("marker-green"), rects: [NSRect(x: 50, y: 300, width: 80, height: 14)])!
page.addAnnotation(movable)
AnnotationFactory.move(movable, by: NSPoint(x: 400, y: 0))
let movedPen = AnnotationFactory.freehand(tool: tool("pen-red"), points: loop.map { NSPoint(x: $0.x - 380, y: $0.y - 60) })!
page.addAnnotation(movedPen)
AnnotationFactory.move(movedPen, by: NSPoint(x: 0, y: -40))
page.addAnnotation(AnnotationFactory.freeText(tool: tool("text-red"), text: "Red note\nsecond line", topLeft: NSPoint(x: 420, y: 270)))
page.addAnnotation(AnnotationFactory.freeText(tool: tool("text-blue"), text: "Blue note", topLeft: NSPoint(x: 420, y: 200)))
// Resizing: a marker rectangle doubled in width, a pen loop squashed, an ink line stretched.
let resizable = AnnotationFactory.highlight(tool: tool("marker-yellow"), rects: [NSRect(x: 50, y: 560, width: 60, height: 20)])!
page.addAnnotation(resizable)
AnnotationGeometry.capture(resizable).resized(to: NSRect(x: 50, y: 560, width: 120, height: 20)).apply(to: resizable)
let quadXs = resizable.quadrilateralPoints!.map { $0.pointValue.x }
check(abs(quadXs.max()! - quadXs.min()! - 120) < 0.5, "resized marker quads span new width (\(quadXs.max()! - quadXs.min()!))")
let squash = AnnotationFactory.freehand(tool: tool("pen-black"), points: loop.map { NSPoint(x: $0.x - 300, y: $0.y + 200) })!
page.addAnnotation(squash)
let sb = squash.bounds
AnnotationGeometry.capture(squash).resized(to: NSRect(x: sb.minX, y: sb.minY, width: sb.width * 2, height: sb.height / 2)).apply(to: squash)
let pathBox = squash.paths!.map(\.bounds).reduce(squash.paths![0].bounds) { $0.union($1) }
check(abs(squash.bounds.width - sb.width * 2) < 0.01 && pathBox.maxX <= squash.bounds.width + 0.01 && pathBox.minY >= -0.01,
      "resized pen path stays inside its new bounds")
let stretchLine = AnnotationFactory.line(tool: tool("underline-blue"), segments: [(NSPoint(x: 60, y: 520), NSPoint(x: 160, y: 520))])!
page.addAnnotation(stretchLine)
let lb = stretchLine.bounds
AnnotationGeometry.capture(stretchLine).resized(to: NSRect(x: lb.minX, y: lb.minY, width: lb.width + 100, height: lb.height)).apply(to: stretchLine)
check(abs(stretchLine.paths![0].bounds.width - 200) < 0.5, "stretched underline is 200 pt long (\(stretchLine.paths![0].bounds.width))")
// Moving to another page: same object re-parented.
let traveller = AnnotationFactory.freehand(tool: tool("pen-blue"), points: loop.map { NSPoint(x: $0.x - 300, y: $0.y - 250) })!
page.addAnnotation(traveller)
page.removeAnnotation(traveller)
doc.page(at: 1)!.addAnnotation(traveller)
render(page, to: outDir.appendingPathComponent("annotated-memory.png"))

// 2. Save while the doc stays open, reload, verify.
let n = page.annotations.count
try time("save small") { try SafeSaver.save(doc, to: small) }
let reloaded = PDFDocument(url: small)!
check(reloaded.page(at: 0)!.annotations.count == n, "annotations survive save/reload (\(n))")
check(reloaded.page(at: 0)!.annotations.contains { $0.type == "Ink" }, "ink persisted")
let kinds = reloaded.page(at: 0)!.annotations.compactMap { AnnotationFactory.kind(of: $0) }
check(kinds.contains(.squiggly) && kinds.contains(.underline) && kinds.contains(.pen) && kinds.contains(.text), "tool kinds survive reload via /NM tag")
let mv = reloaded.page(at: 0)!.annotations.first { $0.type == "Highlight" && abs($0.bounds.minX - 450) < 0.5 }
check(mv != nil, "moved highlight persisted at new position")
let mp = reloaded.page(at: 0)!.annotations.first { AnnotationFactory.kind(of: $0) == .pen && $0.bounds.minY < 300 }
check(mp != nil, "moved pen stroke persisted at new position")
check(reloaded.page(at: 0)!.annotations.contains { $0.type == "Highlight" && abs($0.bounds.width - 120) < 0.5 }, "resized marker persisted")
check(reloaded.page(at: 0)!.annotations.contains { $0.type == "Ink" && abs(($0.paths?.first?.bounds.width ?? 0) - 200) < 0.5 }, "stretched underline persisted")
check(reloaded.page(at: 1)!.annotations.contains { AnnotationFactory.kind(of: $0) == .pen }, "annotation moved to page 2 persisted there")
// Background save: a copy() snapshot written off the main thread while the original keeps changing
// must contain exactly the state at snapshot time.
do {
    let live = PDFDocument(url: small)!
    let before = live.page(at: 0)!.annotations.count
    let snap = live.copy() as! PDFDocument
    let bgURL = small.deletingLastPathComponent().appendingPathComponent("snapshot.pdf")
    try? FileManager.default.removeItem(at: bgURL)
    try? FileManager.default.copyItem(at: small, to: bgURL)
    let done = DispatchSemaphore(value: 0)
    var bgError: Error?
    DispatchQueue.global().async { do { try SafeSaver.save(snap, to: bgURL) } catch { bgError = error }; done.signal() }
    var edits = 0
    repeat {
        let a = PDFAnnotation(bounds: CGRect(x: 5, y: 5, width: 10, height: 10), forType: .square, withProperties: nil)
        live.page(at: 0)!.addAnnotation(a)
        if let f = live.page(at: 0)!.annotations.first { var b = f.bounds; b.origin.y += 1; f.bounds = b }
        edits += 1
    } while done.wait(timeout: .now()) == .timedOut
    let saved = PDFDocument(url: bgURL)!.page(at: 0)!.annotations.count
    check(bgError == nil && saved == before, "background snapshot save excludes \(edits) later edits (\(saved) == \(before))")
}
// Bookmarks: the physical-book rules.
do {
    var fresh = BookmarkState.initial()
    check(fresh.bookmarks.count == 1 && fresh.bookmarks[0].spot == nil && fresh.activeID == nil, "new file: one bookmark, Current, unplaced")
    check(fresh.jump(to: "current", from: Spot(page: 7)) == nil && fresh.bookmark("current")?.spot?.page == 7 && fresh.activeID == "current",
          "clicking an unplaced bookmark places it here (no jump)")
    var old = BookmarkState(bookmarks: [Bookmark(id: "current", name: "Current", spot: Spot(page: 50)),
                                        Bookmark(id: "review", name: "Review", spot: Spot(page: 0))], activeID: "current")
    old.migrate()
    check(old.bookmarks.map(\.id) == ["current"], "migration drops the never-placed Review")
    var b = BookmarkState(bookmarks: [Bookmark(id: "current", name: "Current", spot: Spot(page: 10)),
                                      Bookmark(id: "review", name: "Review", spot: Spot(page: 0, y: 700))], activeID: "current")
    b.migrate()
    check(b.bookmarks.count == 2, "migration keeps a Review that was placed")
    b.follow(Spot(page: 12))
    check(b.bookmark("current")?.spot?.page == 12, "active bookmark follows reading")
    b.jumpElsewhere(from: Spot(page: 13))                       // go to page 200
    check(b.activeID == nil && b.bookmark("current")?.spot?.page == 13 && b.back?.page == 13, "page jump detaches, Current stays where you left")
    b.follow(Spot(page: 200))
    check(b.bookmark("current")?.spot?.page == 13, "detached reading moves no bookmark")
    b.pin("current", at: Spot(page: 200))
    check(b.activeID == "current" && b.bookmark("current")?.spot?.page == 200, "pin moves Current here and makes it follow")
    let toReview = b.jump(to: "review", from: Spot(page: 201))
    check(toReview?.page == 0 && b.activeID == "review" && b.bookmark("current")?.spot?.page == 201, "go to Review: Current keeps its place, Review follows")
    b.follow(Spot(page: 3))
    let backTo = b.goBack(from: Spot(page: 3))
    check(backTo?.page == 201 && b.activeID == "current" && b.bookmark("review")?.spot?.page == 3, "Back returns to Current and re-activates it")
    let again = b.goBack(from: Spot(page: 201))
    check(again?.page == 3 && b.activeID == "review", "Back again toggles to Review")
    check(b.jump(to: "review", from: Spot(page: 4)) == nil && b.bookmark("review")?.spot?.page == 4, "clicking the active bookmark stays put")
    let ans = b.add(name: "Answers", at: Spot(page: 350))
    _ = b.add(name: "Glossary", at: Spot(page: 360))
    check(!b.canAdd && b.add(name: "Fifth", at: Spot(page: 1)) == nil, "at most 4 bookmarks")
    b.remove("current"); b.remove(ans!)
    check(b.bookmark("current") != nil && b.bookmark(ans!) == nil && b.canAdd, "Current can't be removed, others can")
    b.clamp(pageCount: 100)
    check(b.bookmarks.allSatisfy { ($0.spot?.page ?? 0) <= 99 }, "spots clamped to the page count")
    // Store: survives reload, follows a renamed file.
    let storeURL = outDir.appendingPathComponent("bookmarks.json")
    try? FileManager.default.removeItem(at: storeURL)
    let s1 = BookmarkStore(url: storeURL)
    let oldPath = outDir.appendingPathComponent("gone-away.pdf")
    s1.set(b, for: oldPath); s1.flush()
    let s2 = BookmarkStore(url: storeURL)
    check(s2.state(for: oldPath) == b, "bookmark store persists")
    let moved = outDir.appendingPathComponent("elsewhere/gone-away.pdf")
    try? FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: moved.path, contents: Data())
    check(s2.state(for: moved) == b && s2.state(for: oldPath) == nil, "bookmarks follow a moved file (same name, old path gone)")
}
check(ToolConfig.validate(ToolConfig.defaults).isEmpty, "default tools valid")
var bad = ToolConfig.defaults; bad[1].key = "1"
check(!ToolConfig.validate(bad).isEmpty, "duplicate shortcut rejected")
check(!ToolConfig.validate(ToolConfig.defaults.filter { $0.kind != .pen }).isEmpty, "empty kind rejected")
let tmpTools = outDir.appendingPathComponent("tools-old.json")
try JSONEncoder().encode(ToolConfig.defaults.filter { $0.kind != .pen }).write(to: tmpTools)
check(ToolConfig.load(from: tmpTools).filter { $0.kind == .pen }.count == 3, "old tools.json gains default pens")
render(reloaded.page(at: 0)!, to: outDir.appendingPathComponent("annotated-reloaded.png"))
// Original in-memory document still renders pages after its file was replaced
render(doc.page(at: 2)!, to: outDir.appendingPathComponent("after-replace-page3.png"))
check((doc.page(at: 2)!.string ?? "").contains("Page 3 line 1"), "open document still reads after file replaced")
// Save twice more from the same in-memory doc (repeat autosaves)
page.addAnnotation(AnnotationFactory.highlight(tool: tool("marker-yellow"), rects: [NSRect(x: 50, y: 300, width: 100, height: 20)])!)
try SafeSaver.save(doc, to: small)
try SafeSaver.save(doc, to: small)
check(PDFDocument(url: small)!.page(at: 0)!.annotations.count == n + 1, "repeated saves consistent")
check(PDFDocument(url: small)!.page(at: 2)!.string?.contains("Page 3 line 1") == true, "page 3 text intact after repeated saves")

// 3. Large file timing.
let large = outDir.appendingPathComponent("large.pdf")
if !FileManager.default.fileExists(atPath: large.path) { time("generate large (\(largePages) pages)") { makePDF(large, pages: largePages) } }
let size = (try? FileManager.default.attributesOfItem(atPath: large.path)[.size] as? Int) ?? 0
print("INFO large.pdf size \(size / 1_000_000) MB")
let big = time("open large") { PDFDocument(url: large)! }
_ = time("page count") { big.pageCount }
let bp = big.page(at: big.pageCount / 2)!
bp.addAnnotation(AnnotationFactory.highlight(tool: tool("marker-yellow"), rects: [NSRect(x: 50, y: 730, width: 300, height: 20)])!)
let work = outDir.appendingPathComponent("large-work.pdf")
try? FileManager.default.removeItem(at: work)
try FileManager.default.copyItem(at: large, to: work)
let bigw = PDFDocument(url: work)!
bigw.page(at: 10)!.addAnnotation(AnnotationFactory.highlight(tool: tool("marker-yellow"), rects: [NSRect(x: 50, y: 730, width: 300, height: 20)])!)
try time("save large") { try SafeSaver.save(bigw, to: work) }
check(PDFDocument(url: work)!.page(at: 10)!.annotations.count == 1, "large save persisted")

// 4. Heavy "scanned" file: pages that are big noisy JPEG images (opt-in: FOLIO_HEAVY=<pages>).
if let hp = ProcessInfo.processInfo.environment["FOLIO_HEAVY"].flatMap(Int.init) {
    let heavy = outDir.appendingPathComponent("heavy.pdf")
    if !FileManager.default.fileExists(atPath: heavy.path) {
        time("generate heavy (\(hp) pages)") {
            let w = 1240, h = 1754 // A4 @ 150 dpi
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            let ctx = CGContext(heavy as CFURL, mediaBox: &box, nil)!
            for p in 0..<hp {
                // Distinct noise per page so PDF writers can't dedupe the images.
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 1,
                                           hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: w, bitsPerPixel: 8)!
                let px = rep.bitmapData!
                var x = UInt32(p &* 7919 &+ 1)
                for i in stride(from: 0, to: w * h, by: 1) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; px[i] = UInt8(170 + x % 86) }
                let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.5])!
                let img = CGImage(jpegDataProviderSource: CGDataProvider(data: jpeg as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
                ctx.beginPDFPage(nil); ctx.draw(img, in: box); ctx.endPDFPage()
            }
            ctx.closePDF()
        }
    }
    let hsize = (try? FileManager.default.attributesOfItem(atPath: heavy.path)[.size] as? Int) ?? 0
    print("INFO heavy.pdf size \(hsize / 1_000_000) MB")
    let hw = outDir.appendingPathComponent("heavy-work.pdf")
    try? FileManager.default.removeItem(at: hw)
    try FileManager.default.copyItem(at: heavy, to: hw)
    let hd = time("open heavy") { PDFDocument(url: hw)! }
    hd.page(at: 5)!.addAnnotation(AnnotationFactory.highlight(tool: tool("marker-yellow"), rects: [NSRect(x: 50, y: 700, width: 300, height: 20)])!)
    try time("save heavy") { try SafeSaver.save(hd, to: hw) }
    let hsize2 = (try? FileManager.default.attributesOfItem(atPath: hw.path)[.size] as? Int) ?? 0
    print("INFO heavy after save \(hsize2 / 1_000_000) MB")
    check(PDFDocument(url: hw)!.page(at: 5)!.annotations.count == 1, "heavy save persisted")
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
print("Output: \(outDir.path)")
exit(failures == 0 ? 0 : 1)

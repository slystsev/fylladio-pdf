import AppKit
import PDFKit
import FolioCore

protocol AnnotatingPDFViewDelegate: AnyObject {
    func annotationsDidChange()
    func toolShortcutPressed(_ tool: ToolSpec)
    func allTools() -> [ToolSpec]
}

/// PDFView that implements the stationery tools: drag to mark text (or a rectangle on scans),
/// click to write a note, select/delete annotations in pointer mode.
final class AnnotatingPDFView: PDFView, NSTextViewDelegate {
    weak var annotationDelegate: AnnotatingPDFViewDelegate?

    var tool: ToolSpec = .pointer {
        didSet { endTextEntry(commit: true); selectedAnnotation = nil; window?.invalidateCursorRects(for: self) }
    }

    // Drag state (creating)
    private var dragPage: PDFPage?
    private var dragStart: NSPoint = .zero
    private var dragTextMode = false
    private var penPoints: [NSPoint] = []
    private var previews: [(PDFPage, PDFAnnotation)] = []

    // Drag state (moving an existing annotation)
    /// `grab` is the pointer's offset from the bounds origin, so the annotation follows the pointer across pages.
    private struct Move { let ann: PDFAnnotation; let startPage: PDFPage; var page: PDFPage; let grab: NSPoint; let original: NSRect; var moved: Bool }
    private var moving: Move?

    // Drag state (resizing an existing annotation by a handle)
    private struct Resize { let ann: PDFAnnotation; let page: PDFPage; let handle: OutlineOverlay.Handle; let start: NSPoint; let original: AnnotationGeometry; var resized: Bool }
    private var resizing: Resize?

    // Text entry
    private var editor: NSTextView?
    private var editorPage: PDFPage?
    private var editorTopLeft: NSPoint = .zero
    private var editorTool: ToolSpec?
    private var editorReplacing: PDFAnnotation?

    // Selection of an existing annotation (pointer mode)
    private let outline = OutlineOverlay()
    var selectedAnnotation: PDFAnnotation? { didSet { updateSelectionOutline() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        outline.autoresizingMask = [.width, .height]
        outline.frame = bounds
        addSubview(outline)
        NotificationCenter.default.addObserver(self, selector: #selector(viewMoved), name: .PDFViewScaleChanged, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(viewMoved), name: .PDFViewPageChanged, object: self)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clip = enclosingScrollViewInside?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewMoved), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    private var enclosingScrollViewInside: NSScrollView? {
        subviews.lazy.compactMap { $0 as? NSScrollView }.first ?? subviews.lazy.flatMap { $0.subviews }.compactMap { $0 as? NSScrollView }.first
    }

    @objc private func viewMoved() {
        updateSelectionOutline()
        repositionEditor()
    }

    // MARK: Mouse

    private func pagePoint(_ event: NSEvent) -> (PDFPage, NSPoint)? {
        let p = convert(event.locationInWindow, from: nil)
        guard let page = page(for: p, nearest: true) else { return nil }
        return (page, convert(p, to: page))
    }

    /// True when our tool handled mouseDown, so the matching drag/up must not reach PDFKit.
    private var consumedMouse = false

    override func mouseDown(with event: NSEvent) {
        consumedMouse = true
        window?.makeFirstResponder(self)
        if editor != nil { endTextEntry(commit: true); if tool.kind == .text { return } }
        guard let (page, pt) = pagePoint(event) else { consumedMouse = false; return super.mouseDown(with: event) }

        switch tool.kind {
        case .select:
            if let ann = selectedAnnotation, let annPage = ann.page, let h = handle(at: convert(event.locationInWindow, from: nil)) {
                let start = annPage == page ? pt : convert(convert(pt, from: page), to: annPage)
                resizing = Resize(ann: ann, page: annPage, handle: h, start: start, original: .capture(ann), resized: false)
                return
            }
            if let ann = editableAnnotation(on: page, at: pt) {
                selectedAnnotation = ann
                if event.clickCount == 2, ann.type == "FreeText" { beginEditing(ann, on: page); return }
                moving = Move(ann: ann, startPage: page, page: page, grab: NSPoint(x: pt.x - ann.bounds.minX, y: pt.y - ann.bounds.minY),
                              original: ann.bounds, moved: false)
                return
            }
            selectedAnnotation = nil
            consumedMouse = false
            super.mouseDown(with: event)
        case .text:
            if let ann = editableAnnotation(on: page, at: pt), ann.type == "FreeText" {
                beginEditing(ann, on: page)
            } else {
                beginTextEntry(page: page, topLeft: pt, tool: tool, text: "", replacing: nil)
            }
        case .marker, .underline, .squiggly:
            dragPage = page
            dragStart = pt
            dragTextMode = !event.modifierFlags.contains(.option) && AnnotationFactory.hasCharacter(on: page, at: pt)
        case .pen:
            dragPage = page
            dragStart = pt
            penPoints = [pt]
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if var m = moving {
            guard let (p, pt) = pagePoint(event) else { return }
            // Follow the pointer onto another page.
            if p != m.page {
                m.page.removeAnnotation(m.ann)
                annotationsChanged(on: m.page)
                p.addAnnotation(m.ann)
                m.page = p
            }
            var r = m.ann.bounds
            r.origin = NSPoint(x: pt.x - m.grab.x, y: pt.y - m.grab.y)
            // Keep it on the page.
            let pb = p.bounds(for: displayBox)
            r.origin.x = min(max(r.minX, pb.minX - r.width / 2), pb.maxX - r.width / 2)
            r.origin.y = min(max(r.minY, pb.minY - r.height / 2), pb.maxY - r.height / 2)
            m.ann.bounds = r
            m.moved = true
            moving = m
            annotationsChanged(on: p)
            updateSelectionOutline()
            autoscroll(with: event)
            return
        }
        if var z = resizing {
            guard let (p, pt) = pagePoint(event) else { return }
            let local = p == z.page ? pt : convert(convert(pt, from: p), to: z.page)
            let r = resizedRect(z.original.bounds, handle: z.handle, dx: local.x - z.start.x, dy: local.y - z.start.y,
                                keepAspect: event.modifierFlags.contains(.shift))
            z.original.resized(to: r).apply(to: z.ann)
            z.resized = true
            resizing = z
            annotationsChanged(on: z.page)
            updateSelectionOutline()
            autoscroll(with: event)
            return
        }
        guard dragPage != nil else { if !consumedMouse { super.mouseDragged(with: event) }; return }
        autoscroll(with: event)
        updatePreview(event)
    }

    override func mouseUp(with event: NSEvent) {
        if let m = moving {
            moving = nil
            consumedMouse = false
            if m.moved {
                let final = m.ann.bounds
                if m.page != m.startPage {
                    m.page.removeAnnotation(m.ann); annotationsChanged(on: m.page)
                    m.startPage.addAnnotation(m.ann)
                    m.ann.bounds = m.original
                    relocate(m.ann, to: m.page, bounds: final)
                } else {
                    m.ann.bounds = m.original
                    setBounds(m.ann, final, actionName: "Move Annotation")
                }
            }
            return
        }
        if let z = resizing {
            resizing = nil
            consumedMouse = false
            if z.resized {
                let final = AnnotationGeometry.capture(z.ann)
                z.original.apply(to: z.ann)
                setGeometry(z.ann, final, actionName: "Resize Annotation")
            }
            return
        }
        guard dragPage != nil else { if !consumedMouse { super.mouseUp(with: event) }; consumedMouse = false; return }
        consumedMouse = false
        updatePreview(event)
        let made = previews
        previews = []
        penPoints = []
        dragPage = nil
        guard !made.isEmpty else { return }
        for (page, ann) in made { page.removeAnnotation(ann) }
        add(made)
    }

    override func mouseMoved(with event: NSEvent) {
        switch tool.kind {
        case .select:
            if selectedAnnotation != nil, let h = handle(at: convert(event.locationInWindow, from: nil)) {
                h.cursor.set()
            } else if let (page, pt) = pagePoint(event), editableAnnotation(on: page, at: pt) != nil {
                NSCursor.openHand.set()
            } else {
                super.mouseMoved(with: event)
            }
        case .text: NSCursor.iBeam.set()
        case .pen: NSCursor.crosshair.set()
        default:
            if let (page, pt) = pagePoint(event), !event.modifierFlags.contains(.option),
               AnnotationFactory.hasCharacter(on: page, at: pt) {
                NSCursor.iBeam.set()
            } else {
                NSCursor.crosshair.set()
            }
        }
    }

    /// Lines within this angle of horizontal snap flat (Shift always does).
    private let snapAngle: CGFloat = 5 * .pi / 180

    private func updatePreview(_ event: NSEvent) {
        guard let startPage = dragPage, let doc = document, let (curPage, curPt) = pagePoint(event) else { return }
        for (p, a) in previews { p.removeAnnotation(a) }
        previews = []
        let end = curPage == startPage ? curPt : convert(convert(curPt, from: curPage), to: startPage)
        var made: [(PDFPage, PDFAnnotation)] = []

        if tool.kind == .pen {
            penPoints.append(end)
            if let a = AnnotationFactory.freehand(tool: tool, points: penPoints) { made = [(startPage, a)] }
        } else if dragTextMode {
            if let sel = doc.selection(from: startPage, at: dragStart, to: curPage, at: curPt) {
                for (page, rects) in linesByPage(sel) {
                    let a = tool.kind == .marker
                        ? AnnotationFactory.highlight(tool: tool, rects: rects)
                        : AnnotationFactory.line(tool: tool, segments: AnnotationFactory.segmentsUnder(lines: rects, kind: tool.kind))
                    if let a { made.append((page, a)) }
                }
            }
        } else if tool.kind == .marker {
            var r = NSRect(x: min(dragStart.x, end.x), y: min(dragStart.y, end.y),
                           width: abs(end.x - dragStart.x), height: abs(end.y - dragStart.y))
            r = r.intersection(startPage.bounds(for: displayBox))
            if r.width >= 3, r.height >= 3, let a = AnnotationFactory.highlight(tool: tool, rects: [r]) { made = [(startPage, a)] }
        } else {
            // Underline / curly on non-text: a line from where the drag started to where the pointer is.
            var e = end
            let dx = e.x - dragStart.x, dy = e.y - dragStart.y
            if event.modifierFlags.contains(.shift) || abs(dy) <= abs(dx) * tan(snapAngle) { e.y = dragStart.y }
            if let a = AnnotationFactory.line(tool: tool, segments: [(dragStart, e)]) { made = [(startPage, a)] }
        }
        for (page, a) in made { page.addAnnotation(a) }
        previews = made
    }

    private func linesByPage(_ sel: PDFSelection) -> [(PDFPage, [NSRect])] {
        var byPage: [ObjectIdentifier: (PDFPage, [NSRect])] = [:]
        var order: [ObjectIdentifier] = []
        for line in sel.selectionsByLine() {
            for p in line.pages {
                let r = line.bounds(for: p)
                guard r.width > 0.5 else { continue }
                let k = ObjectIdentifier(p)
                if byPage[k] == nil { byPage[k] = (p, []); order.append(k) }
                byPage[k]!.1.append(r)
            }
        }
        return order.map { byPage[$0]! }
    }

    private func editableAnnotation(on page: PDFPage, at pt: NSPoint) -> PDFAnnotation? {
        // Topmost first. Strokes are hit near their path; boxes anywhere inside.
        let tol = max(3, 5 / max(scaleFactor, 0.1))
        return page.annotations.reversed().first { AnnotationFactory.isEditable($0) && AnnotationFactory.hits($0, at: pt, tolerance: tol) }
    }

    // MARK: Resize

    /// The handle of the selection outline under a point in view coordinates.
    private func handle(at viewPoint: NSPoint) -> OutlineOverlay.Handle? {
        outline.handle(at: outline.convert(viewPoint, from: self))
    }

    /// `r` with the edges named by `handle` moved by (dx, dy), at least 4 pt each way.
    /// With `keepAspect`, corner drags keep the original proportions.
    private func resizedRect(_ r: NSRect, handle h: OutlineOverlay.Handle, dx: CGFloat, dy: CGFloat, keepAspect: Bool) -> NSRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        let minSize: CGFloat = 4
        if h.left { minX = min(r.minX + dx, maxX - minSize) }
        if h.right { maxX = max(r.maxX + dx, minX + minSize) }
        if h.bottom { minY = min(r.minY + dy, maxY - minSize) }
        if h.top { maxY = max(r.maxY + dy, minY + minSize) }
        if keepAspect, (h.left || h.right), (h.top || h.bottom), r.width > 0, r.height > 0 {
            let s = max((maxX - minX) / r.width, (maxY - minY) / r.height)
            let w = r.width * s, hgt = r.height * s
            if h.left { minX = maxX - w } else { maxX = minX + w }
            if h.bottom { minY = maxY - hgt } else { maxY = minY + hgt }
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Applies a geometry (bounds plus scaled inner points) with undo.
    func setGeometry(_ ann: PDFAnnotation, _ g: AnnotationGeometry, actionName: String) {
        let old = AnnotationGeometry.capture(ann)
        g.apply(to: ann)
        if let p = ann.page { annotationsChanged(on: p) }
        undoManager?.registerUndo(withTarget: self) { $0.setGeometry(ann, old, actionName: actionName) }
        undoManager?.setActionName(actionName)
        updateSelectionOutline()
        annotationDelegate?.annotationsDidChange()
    }

    /// Moves an annotation to another page (and position) with undo.
    func relocate(_ ann: PDFAnnotation, to page: PDFPage, bounds: NSRect) {
        guard let from = ann.page else { return }
        let oldBounds = ann.bounds
        from.removeAnnotation(ann)
        annotationsChanged(on: from)
        ann.bounds = bounds
        ann.modificationDate = Date()
        page.addAnnotation(ann)
        annotationsChanged(on: page)
        undoManager?.registerUndo(withTarget: self) { $0.relocate(ann, to: from, bounds: oldBounds) }
        undoManager?.setActionName("Move Annotation")
        updateSelectionOutline()
        annotationDelegate?.annotationsDidChange()
    }

    /// Changes an annotation's bounds (i.e. moves it) with undo.
    func setBounds(_ ann: PDFAnnotation, _ r: NSRect, actionName: String) {
        let old = ann.bounds
        ann.bounds = r
        ann.modificationDate = Date()
        if let p = ann.page { annotationsChanged(on: p) }
        undoManager?.registerUndo(withTarget: self) { $0.setBounds(ann, old, actionName: actionName) }
        undoManager?.setActionName(actionName)
        updateSelectionOutline()
        annotationDelegate?.annotationsDidChange()
    }

    // MARK: Add / remove with undo

    func add(_ items: [(PDFPage, PDFAnnotation)]) {
        for (p, a) in items { p.addAnnotation(a) }
        undoManager?.registerUndo(withTarget: self) { $0.remove(items) }
        undoManager?.setActionName("Annotation")
        annotationDelegate?.annotationsDidChange()
    }

    func remove(_ items: [(PDFPage, PDFAnnotation)]) {
        for (p, a) in items { p.removeAnnotation(a) }
        if let sel = selectedAnnotation, items.contains(where: { $0.1 === sel }) { selectedAnnotation = nil }
        undoManager?.registerUndo(withTarget: self) { $0.add(items) }
        undoManager?.setActionName("Annotation")
        annotationDelegate?.annotationsDidChange()
    }

    func replace(_ old: PDFAnnotation, with new: PDFAnnotation, on page: PDFPage) {
        undoManager?.beginUndoGrouping()
        remove([(page, old)])
        add([(page, new)])
        undoManager?.endUndoGrouping()
    }

    func deleteSelectedAnnotation() {
        guard let ann = selectedAnnotation, let page = ann.page else { return }
        remove([(page, ann)])
    }

    // MARK: Text notes

    private func beginEditing(_ ann: PDFAnnotation, on page: PDFPage) {
        let color = ann.fontColor ?? .black
        let all = annotationDelegate?.allTools() ?? []
        let base = all.first { $0.kind == .text && $0.nsColor.isClose(to: color) } ?? (tool.kind == .text ? tool : all.first { $0.kind == .text } ?? tool)
        var t = base
        if let size = ann.font?.pointSize { t.fontSize = Double(size) }
        t.color = color.hexString
        beginTextEntry(page: page, topLeft: NSPoint(x: ann.bounds.minX, y: ann.bounds.maxY), tool: t, text: ann.contents ?? "", replacing: ann)
    }

    private func beginTextEntry(page: PDFPage, topLeft: NSPoint, tool t: ToolSpec, text: String, replacing: PDFAnnotation?) {
        selectedAnnotation = nil
        let tv = NSTextView(frame: .zero)
        tv.string = text
        tv.isRichText = false
        tv.drawsBackground = true
        tv.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85)
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.textColor = t.nsColor
        tv.insertionPointColor = t.nsColor
        tv.delegate = self
        tv.wantsLayer = true
        tv.layer?.borderColor = NSColor.controlAccentColor.cgColor
        tv.layer?.borderWidth = 1
        editor = tv; editorPage = page; editorTopLeft = topLeft; editorTool = t; editorReplacing = replacing
        if let r = replacing { r.shouldDisplay = false }
        addSubview(tv)
        repositionEditor()
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)
    }

    private func repositionEditor() {
        guard let tv = editor, let page = editorPage, let t = editorTool else { return }
        let font = AnnotationFactory.textFont(t)
        tv.font = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scaleFactor)
        let size = AnnotationFactory.textSize(tv.string.isEmpty ? "M" : tv.string, tool: t)
        let topLeft = convert(editorTopLeft, from: page)
        let w = max(size.width * scaleFactor + 12, 60)
        let h = size.height * scaleFactor
        tv.frame = NSRect(x: topLeft.x + 4 * scaleFactor, y: topLeft.y - h + 2 * scaleFactor, width: w, height: h)
    }

    func textDidChange(_ notification: Notification) { repositionEditor() }

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(insertNewline(_:)):
            // Return commits; Option/Shift+Return inserts a line break.
            if let flags = NSApp.currentEvent?.modifierFlags, flags.contains(.option) || flags.contains(.shift) {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            }
            endTextEntry(commit: true); return true
        case #selector(insertLineBreak(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange()); return true
        case #selector(cancelOperation(_:)):
            endTextEntry(commit: false); return true
        default: return false
        }
    }

    func endTextEntry(commit: Bool) {
        guard let tv = editor, let page = editorPage, let t = editorTool else { return }
        let text = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = editorReplacing
        editor = nil; editorPage = nil; editorReplacing = nil; editorTool = nil
        tv.removeFromSuperview()
        old?.shouldDisplay = true
        window?.makeFirstResponder(self)
        guard commit else { return }
        if let old {
            if text.isEmpty { remove([(page, old)]) }
            else if text != old.contents { replace(old, with: AnnotationFactory.freeText(tool: t, text: text, topLeft: editorTopLeft), on: page) }
        } else if !text.isEmpty {
            add([(page, AnnotationFactory.freeText(tool: t, text: text, topLeft: editorTopLeft))])
        }
    }

    // MARK: Selection outline

    private func updateSelectionOutline() {
        if outline.superview === self, subviews.last !== outline { addSubview(outline) } // keep on top
        guard let ann = selectedAnnotation, let page = ann.page, page.document === document else {
            outline.rect = nil; return
        }
        outline.rect = outline.convert(convert(ann.bounds, from: page), from: self).insetBy(dx: -3, dy: -3)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        // Arrow keys nudge the selected annotation: 1 pt, Shift = 10 pt.
        if let ann = selectedAnnotation, [123, 124, 125, 126].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let d: NSPoint = [123: NSPoint(x: -step, y: 0), 124: NSPoint(x: step, y: 0),
                              125: NSPoint(x: 0, y: -step), 126: NSPoint(x: 0, y: step)][event.keyCode]!
            setBounds(ann, ann.bounds.offsetBy(dx: d.x, dy: d.y), actionName: "Move Annotation")
            return
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.isEmpty, let chars = event.charactersIgnoringModifiers {
            if event.keyCode == 53 { // Esc
                if selectedAnnotation != nil { selectedAnnotation = nil } else { annotationDelegate?.toolShortcutPressed(.pointer) }
                return
            }
            if (event.keyCode == 51 || event.keyCode == 117), selectedAnnotation != nil { deleteSelectedAnnotation(); return }
            if let t = annotationDelegate?.allTools().first(where: { $0.key?.lowercased() == chars.lowercased() }) {
                annotationDelegate?.toolShortcutPressed(t); return
            }
            if chars == "v" { annotationDelegate?.toolShortcutPressed(.pointer); return }
        }
        super.keyDown(with: event)
    }

    @objc func delete(_ sender: Any?) { deleteSelectedAnnotation() }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let (page, pt) = pagePoint(event), let ann = editableAnnotation(on: page, at: pt) else { return menu }
        selectedAnnotation = ann
        let extra = NSMenu()
        extra.addItem(withTitle: "Delete Annotation", action: #selector(delete(_:)), keyEquivalent: "").target = self
        let kind = AnnotationFactory.kind(of: ann)
        let same = (annotationDelegate?.allTools() ?? []).filter { $0.kind == kind }
        if same.count > 1 {
            extra.addItem(.separator())
            for t in same {
                let item = NSMenuItem(title: "Change to \(t.name)", action: #selector(recolor(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = t.color
                item.image = swatch(t.nsColor)
                extra.addItem(item)
            }
        }
        extra.addItem(.separator())
        for item in menu.items { menu.removeItem(item); extra.addItem(item) }
        return extra
    }

    @objc private func recolor(_ sender: NSMenuItem) {
        guard let ann = selectedAnnotation, let hex = sender.representedObject as? String, let color = NSColor(hex: hex) else { return }
        setColor(color, of: ann)
    }

    private func setColor(_ color: NSColor, of ann: PDFAnnotation) {
        let isText = ann.type == "FreeText"
        let old = isText ? (ann.fontColor ?? .black) : ann.color
        if isText { ann.fontColor = color } else { ann.color = color }
        undoManager?.registerUndo(withTarget: self) { $0.setColor(old, of: ann) }
        undoManager?.setActionName("Change Color")
        updateSelectionOutline()
        annotationDelegate?.annotationsDidChange()
    }

    private func swatch(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            c.withAlphaComponent(1).setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill(); return true
        }
    }
}

extension NSColor {
    func isClose(to other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) < 0.06
    }
}

/// Draws the dashed outline around the selected annotation and its resize handles; transparent to clicks
/// (the PDF view asks it which handle is under the pointer).
final class OutlineOverlay: NSView {
    struct Handle: Equatable {
        var left = false, right = false, top = false, bottom = false

        var cursor: NSCursor {
            if (left || right) && !(top || bottom) { return .resizeLeftRight }
            if (top || bottom) && !(left || right) { return .resizeUpDown }
            if #available(macOS 15.0, *) {
                let pos: NSCursor.FrameResizePosition = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
                return .frameResize(position: pos, directions: .all)
            }
            return .crosshair
        }
    }

    var rect: NSRect? { didSet { needsDisplay = true } }
    private let handleSize: CGFloat = 7

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Handles shown for the current rect: all eight, or only the two that make sense for a thin shape.
    private var handles: [(Handle, NSPoint)] {
        guard let r = rect else { return [] }
        let thinH = r.height < 18, thinW = r.width < 18
        var out: [(Handle, NSPoint)] = []
        if !thinH || thinW == thinH {
            out.append((Handle(top: true), NSPoint(x: r.midX, y: r.maxY)))
            out.append((Handle(bottom: true), NSPoint(x: r.midX, y: r.minY)))
        }
        if !thinW || thinW == thinH {
            out.append((Handle(left: true), NSPoint(x: r.minX, y: r.midY)))
            out.append((Handle(right: true), NSPoint(x: r.maxX, y: r.midY)))
        }
        if !thinW && !thinH {
            out.append((Handle(left: true, top: true), NSPoint(x: r.minX, y: r.maxY)))
            out.append((Handle(right: true, top: true), NSPoint(x: r.maxX, y: r.maxY)))
            out.append((Handle(left: true, bottom: true), NSPoint(x: r.minX, y: r.minY)))
            out.append((Handle(right: true, bottom: true), NSPoint(x: r.maxX, y: r.minY)))
        }
        return out
    }

    func handle(at p: NSPoint) -> Handle? {
        let reach = handleSize / 2 + 3
        return handles.first { abs($0.1.x - p.x) <= reach && abs($0.1.y - p.y) <= reach }?.0
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let r = rect else { return }
        let path = NSBezierPath(rect: r)
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
        for (_, c) in handles {
            let box = NSRect(x: c.x - handleSize / 2, y: c.y - handleSize / 2, width: handleSize, height: handleSize)
            NSColor.white.setFill(); box.fill()
            NSColor.controlAccentColor.setStroke()
            let b = NSBezierPath(rect: box); b.lineWidth = 1; b.stroke()
        }
    }
}

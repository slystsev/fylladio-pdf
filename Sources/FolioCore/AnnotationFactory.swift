import AppKit
import PDFKit

/// Builds PDF annotations for the stationery tools. No UI dependencies, so it can be checked headlessly.
///
/// - Markers → /Highlight with quad points (text lines or a dragged rectangle).
/// - Underline, curly underline, pen → /Ink with dense polylines. Ink renders in every viewer and lets the
///   width be configured; PDFKit does not render /Squiggly at all.
/// - Text → /FreeText.
/// Every annotation's author (/T) is "Folio/<kind>" so the tool kind survives save/reload
/// (verified: PDFKit drops /NM and custom keys when writing, but keeps /T).
public enum AnnotationFactory {
    public static let authorTag = "Folio"

    // Curly underline shape: a flat sine wave.
    public static let wavePeriod: CGFloat = 8.0
    public static let waveAmplitude: CGFloat = 1.1

    // MARK: Markers

    /// A highlight covering `rects` (page coordinates): real text lines or an arbitrary rectangle on a scan.
    public static func highlight(tool: ToolSpec, rects: [NSRect]) -> PDFAnnotation? {
        let rects = rects.filter { $0.width > 0.5 && $0.height > 0.5 }
        guard let first = rects.first else { return nil }
        let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
        let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        ann.color = tool.nsColor
        var pts: [NSValue] = []
        for r in rects {
            // PDF quad point order: top-left, top-right, bottom-left, bottom-right (relative to bounds origin in PDFKit).
            pts.append(NSValue(point: NSPoint(x: r.minX - bounds.minX, y: r.maxY - bounds.minY)))
            pts.append(NSValue(point: NSPoint(x: r.maxX - bounds.minX, y: r.maxY - bounds.minY)))
            pts.append(NSValue(point: NSPoint(x: r.minX - bounds.minX, y: r.minY - bounds.minY)))
            pts.append(NSValue(point: NSPoint(x: r.maxX - bounds.minX, y: r.minY - bounds.minY)))
        }
        ann.quadrilateralPoints = pts
        stamp(ann, kind: .marker)
        return ann
    }

    // MARK: Lines (underline / curly)

    /// Underline segments under text lines (page coordinates of each line's bounds).
    public static func segmentsUnder(lines rects: [NSRect], kind: ToolKind) -> [(NSPoint, NSPoint)] {
        rects.filter { $0.width > 0.5 }.map { r in
            // Selection line bounds include the descender; the baseline sits roughly 20% up.
            let y = kind == .squiggly ? r.minY + waveAmplitude * 0.5 : r.minY + r.height * 0.12
            return (NSPoint(x: r.minX, y: y), NSPoint(x: r.maxX, y: y))
        }
    }

    /// Straight or wavy line(s), from point to point, for an underline or curly tool.
    public static func line(tool: ToolSpec, segments: [(NSPoint, NSPoint)]) -> PDFAnnotation? {
        let polylines: [[NSPoint]] = segments.compactMap { a, b in
            guard hypot(b.x - a.x, b.y - a.y) >= 2 else { return nil }
            return tool.kind == .squiggly ? wave(from: a, to: b) : [a, b]
        }
        return ink(tool: tool, polylines: polylines, kind: tool.kind)
    }

    /// Dense samples of a sine wave running from a to b.
    static func wave(from a: NSPoint, to b: NSPoint) -> [NSPoint] {
        let len = hypot(b.x - a.x, b.y - a.y)
        let d = NSPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len)
        let n = NSPoint(x: -d.y, y: d.x)
        let step: CGFloat = 0.5
        var pts: [NSPoint] = []
        var s: CGFloat = 0
        while s <= len {
            let off = waveAmplitude * sin(2 * .pi * s / wavePeriod)
            pts.append(NSPoint(x: a.x + d.x * s + n.x * off, y: a.y + d.y * s + n.y * off))
            s += step
        }
        return pts
    }

    // MARK: Pen

    /// A freehand stroke, lightly smoothed so it looks hand-drawn rather than jagged.
    public static func freehand(tool: ToolSpec, points raw: [NSPoint]) -> PDFAnnotation? {
        let pts = smooth(raw)
        guard pts.count >= 2 else {
            // A click: draw a dot.
            guard let p = raw.first else { return nil }
            return ink(tool: tool, polylines: [[p, NSPoint(x: p.x + 0.3, y: p.y)]], kind: .pen)
        }
        return ink(tool: tool, polylines: [pts], kind: .pen)
    }

    /// Drops near-duplicate points, averages out mouse jitter, then interpolates a Catmull-Rom curve
    /// so fast strokes (sparse mouse samples) stay round.
    public static func smooth(_ raw: [NSPoint]) -> [NSPoint] {
        var pts: [NSPoint] = []
        for p in raw where pts.last.map({ hypot(p.x - $0.x, p.y - $0.y) >= 0.8 }) ?? true { pts.append(p) }
        guard pts.count >= 3 else { return pts }
        // Weighted moving average (1-2-1), endpoints kept.
        var avg = pts
        for i in 1..<(pts.count - 1) {
            avg[i] = NSPoint(x: (pts[i - 1].x + 2 * pts[i].x + pts[i + 1].x) / 4,
                             y: (pts[i - 1].y + 2 * pts[i].y + pts[i + 1].y) / 4)
        }
        // Catmull-Rom, ~1pt spacing.
        var out: [NSPoint] = [avg[0]]
        for i in 0..<(avg.count - 1) {
            let p0 = avg[max(i - 1, 0)], p1 = avg[i], p2 = avg[i + 1], p3 = avg[min(i + 2, avg.count - 1)]
            let n = max(1, Int(hypot(p2.x - p1.x, p2.y - p1.y)))
            for k in 1...n {
                let t = CGFloat(k) / CGFloat(n), t2 = t * t, t3 = t2 * t
                func cr(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                out.append(NSPoint(x: cr(p0.x, p1.x, p2.x, p3.x), y: cr(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        return out
    }

    // MARK: Ink builder

    static func ink(tool: ToolSpec, polylines: [[NSPoint]], kind: ToolKind) -> PDFAnnotation? {
        let lines = polylines.filter { $0.count >= 2 }
        guard !lines.isEmpty else { return nil }
        let all = lines.flatMap { $0 }
        let pad = tool.lineWidth + 2
        let minX = all.map(\.x).min()! - pad, maxX = all.map(\.x).max()! + pad
        let minY = all.map(\.y).min()! - pad, maxY = all.map(\.y).max()! + pad
        let bounds = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        for line in lines {
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: line[0].x - minX, y: line[0].y - minY))
            for p in line.dropFirst() { path.line(to: NSPoint(x: p.x - minX, y: p.y - minY)) }
            ann.add(path)
        }
        ann.color = tool.nsColor
        let border = PDFBorder()
        border.lineWidth = tool.lineWidth
        ann.border = border
        stamp(ann, kind: kind)
        return ann
    }

    // MARK: Text

    public static func textFont(_ tool: ToolSpec) -> NSFont {
        let size = CGFloat(tool.fontSize ?? 12)
        if let name = tool.fontName {
            if let f = NSFont(name: name, size: size) { return f }
            if let f = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) { return f }
        }
        return NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
    }

    /// Size the text occupies on the page, including a small padding.
    public static func textSize(_ text: String, tool: ToolSpec) -> NSSize {
        let attr = NSAttributedString(string: text, attributes: [.font: textFont(tool)])
        let r = attr.boundingRect(with: NSSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin])
        return NSSize(width: ceil(r.width) + 8, height: ceil(r.height) + 4)
    }

    /// A free-text note whose top-left corner is at `topLeft` (page coordinates).
    public static func freeText(tool: ToolSpec, text: String, topLeft: NSPoint) -> PDFAnnotation {
        let size = textSize(text, tool: tool)
        let bounds = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        let ann = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        ann.contents = text
        ann.font = textFont(tool)
        ann.fontColor = tool.nsColor
        ann.color = .clear
        ann.alignment = .left
        let border = PDFBorder()
        border.lineWidth = 0
        ann.border = border
        stamp(ann, kind: .text)
        return ann
    }

    // MARK: Identity, hit testing, moving

    /// Tags an annotation as Folio's: author "Folio/<kind>", plus "@<opacity>" for translucent ones (markers).
    /// PDFKit keeps a highlight's opacity only in its appearance stream: after a reload its colour reads as opaque,
    /// and any change (move, resize, recolour) redraws it opaque. The tag lets `restoreOpacity` put it back.
    static func stamp(_ ann: PDFAnnotation, kind: ToolKind) {
        let a = ann.color.alphaComponent
        ann.userName = "\(authorTag)/\(kind.rawValue)" + (a < 0.999 ? String(format: "@%.2f", a) : "")
        ann.modificationDate = Date()
    }

    /// Default marker opacity, assumed for Folio highlights tagged before opacity was recorded.
    public static let legacyMarkerOpacity: CGFloat = 0.4

    /// "Folio/<kind>[@<opacity>]" → (kind, opacity).
    static func parseTag(_ ann: PDFAnnotation) -> (ToolKind, CGFloat?)? {
        guard let t = ann.userName, t.hasPrefix(authorTag + "/") else { return nil }
        let rest = t.dropFirst(authorTag.count + 1)
        let parts = rest.split(separator: "@", maxSplits: 1)
        guard let first = parts.first, let k = ToolKind(rawValue: String(first)) else { return nil }
        let opacity = parts.count > 1 ? Double(parts[1]).map { CGFloat($0) } : nil
        return (k, opacity)
    }

    /// Re-applies a Folio marker's opacity after a reload (see `stamp`). Call before changing an annotation.
    /// Preview's highlights are opaque by design and are left alone.
    public static func restoreOpacity(_ ann: PDFAnnotation) {
        guard ann.type == "Highlight", let (k, opacity) = parseTag(ann), k == .marker, ann.color.alphaComponent > 0.999 else { return }
        ann.color = ann.color.withAlphaComponent(opacity ?? legacyMarkerOpacity)
    }

    /// Sets an annotation's colour, keeping the opacity tag in step.
    public static func setColor(_ color: NSColor, of ann: PDFAnnotation) {
        if ann.type == "FreeText" { ann.fontColor = color } else { ann.color = color }
        if let (k, _) = parseTag(ann) { stamp(ann, kind: k) }
    }

    /// The tool kind an annotation belongs to (Folio's tag, else guessed from its PDF type).
    public static func kind(of ann: PDFAnnotation) -> ToolKind? {
        if let (k, _) = parseTag(ann) { return k }
        switch ann.type {
        case "Highlight": return .marker
        case "Underline", "StrikeOut": return .underline
        case "Squiggly": return .squiggly
        case "Ink": return .pen
        case "FreeText": return .text
        default: return nil
        }
    }

    /// Annotations the user may select, move and delete (not links, form widgets, etc.).
    public static func isEditable(_ ann: PDFAnnotation) -> Bool {
        guard let t = ann.type else { return false }
        return ["Highlight", "Underline", "Squiggly", "StrikeOut", "FreeText", "Square", "Ink", "Text", "Line", "Circle"].contains(t)
    }

    /// Precise hit test: strokes are hit near their path, not anywhere in their bounding box.
    public static func hits(_ ann: PDFAnnotation, at pt: NSPoint, tolerance: CGFloat = 4) -> Bool {
        let b = ann.bounds
        guard b.insetBy(dx: -tolerance, dy: -tolerance).contains(pt) else { return false }
        if ann.type == "Ink", let paths = ann.paths, !paths.isEmpty {
            let local = NSPoint(x: pt.x - b.minX, y: pt.y - b.minY)
            for path in paths {
                let stroke = CGPath.from(path).copy(strokingWithWidth: max(ann.border?.lineWidth ?? 1, 1) + 2 * tolerance,
                                                    lineCap: .round, lineJoin: .round, miterLimit: 10)
                if stroke.contains(local) { return true }
            }
            return false
        }
        return true
    }

    /// Moves an annotation by `delta` (page coordinates). Quad points and ink paths are stored
    /// relative to the bounds in PDFKit, so shifting the bounds moves the whole thing.
    public static func move(_ ann: PDFAnnotation, by delta: NSPoint) {
        var b = ann.bounds
        b.origin.x += delta.x
        b.origin.y += delta.y
        ann.bounds = b
        ann.modificationDate = Date()
    }

    /// True if a real character sits under `point` (characterIndex(at:) alone returns the nearest one).
    public static func hasCharacter(on page: PDFPage, at point: NSPoint) -> Bool {
        let n = page.numberOfCharacters
        let i = page.characterIndex(at: point) // NSNotFound when nothing is near
        if i >= 0, i < n {
            for j in max(0, i - 1)...min(i + 1, n - 1) {
                if page.characterBounds(at: j).insetBy(dx: -2, dy: -2).contains(point) { return true }
            }
        }
        // Fallback: any non-blank text in a small box around the point.
        let probe = NSRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)
        let s = page.selection(for: probe)?.string ?? ""
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension CGPath {
    static func from(_ p: NSBezierPath) -> CGPath {
        let path = CGMutablePath()
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<p.elementCount {
            switch p.element(at: i, associatedPoints: &pts) {
            case .moveTo: path.move(to: pts[0])
            case .lineTo: path.addLine(to: pts[0])
            case .curveTo, .cubicCurveTo: path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo: path.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

import AppKit
import PDFKit

/// Builds PDF annotations for the stationery tools. No UI dependencies, so it can be checked headlessly.
public enum AnnotationFactory {
    public static let authorTag = "Folio"

    static func subtype(for kind: ToolKind) -> PDFAnnotationSubtype? {
        switch kind {
        case .marker: return .highlight
        case .underline: return .underline
        default: return nil
        }
    }

    /// A markup annotation (highlight / underline / squiggly) covering `rects` (page coordinates).
    /// Works for real text lines and for arbitrary rectangles on scanned pages alike.
    public static func markup(tool: ToolSpec, rects: [NSRect]) -> PDFAnnotation? {
        let rects = rects.filter { $0.width > 0.5 && $0.height > 0.5 }
        guard let first = rects.first else { return nil }
        let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
        if tool.kind == .squiggly { return squiggle(tool: tool, rects: rects, bounds: bounds) }
        guard let type = subtype(for: tool.kind) else { return nil }
        let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
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
        stamp(ann)
        return ann
    }

    /// PDFKit does not render /Squiggly annotations, so curly underlines are Ink annotations
    /// (one wavy path per line), which every viewer draws.
    static func squiggle(tool: ToolSpec, rects: [NSRect], bounds: NSRect) -> PDFAnnotation {
        let amp: CGFloat = 1.4
        let period: CGFloat = 4.5
        let outer = bounds.insetBy(dx: -2, dy: -(amp + 2))
        let ann = PDFAnnotation(bounds: outer, forType: .ink, withProperties: nil)
        for r in rects {
            let path = NSBezierPath()
            let baseY = r.minY - outer.minY
            var x = r.minX - outer.minX
            let endX = r.maxX - outer.minX
            var up = true
            path.move(to: NSPoint(x: x, y: baseY))
            while x < endX {
                let nx = min(x + period / 2, endX)
                path.line(to: NSPoint(x: nx, y: baseY + (up ? amp : -amp)))
                up.toggle(); x = nx
            }
            ann.add(path)
        }
        ann.color = tool.nsColor
        let border = PDFBorder()
        border.lineWidth = 1.0
        ann.border = border
        ann.setValue(squiggleMarker, forAnnotationKey: PDFAnnotationKey(rawValue: "/FolioKind"))
        stamp(ann)
        return ann
    }

    static let squiggleMarker = "squiggly"

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

    public static func textFont(_ tool: ToolSpec) -> NSFont {
        NSFont(name: "Helvetica", size: CGFloat(tool.fontSize ?? 12)) ?? .systemFont(ofSize: CGFloat(tool.fontSize ?? 12))
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
        stamp(ann)
        return ann
    }

    static func stamp(_ ann: PDFAnnotation) {
        ann.userName = authorTag
        ann.modificationDate = Date()
    }

    /// Annotations the user may select and delete (not links, form widgets, etc.).
    public static func isEditable(_ ann: PDFAnnotation) -> Bool {
        guard let t = ann.type else { return false }
        return ["Highlight", "Underline", "Squiggly", "StrikeOut", "FreeText", "Square", "Ink", "Text", "Line", "Circle"].contains(t)
    }
}

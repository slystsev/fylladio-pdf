import AppKit
import PDFKit

/// Everything that defines where an annotation sits and how big it is. PDFKit stores quad points, ink paths
/// and line end points relative to the bounds origin, so moving only changes `bounds`, but resizing must
/// scale the inner geometry too. Captured and re-applied for undo.
public struct AnnotationGeometry {
    public var bounds: NSRect
    public var quads: [NSPoint]?
    public var paths: [NSBezierPath]?
    public var lineStart: NSPoint?
    public var lineEnd: NSPoint?

    public static func capture(_ ann: PDFAnnotation) -> AnnotationGeometry {
        var g = AnnotationGeometry(bounds: ann.bounds)
        switch ann.type {
        case "Highlight", "Underline", "StrikeOut", "Squiggly":
            g.quads = ann.quadrilateralPoints?.map(\.pointValue)
        case "Ink":
            g.paths = ann.paths?.map { $0.copy() as! NSBezierPath }
        case "Line":
            g.lineStart = ann.startPoint; g.lineEnd = ann.endPoint
        default: break
        }
        return g
    }

    public func apply(to ann: PDFAnnotation) {
        ann.bounds = bounds
        if let quads { ann.quadrilateralPoints = quads.map { NSValue(point: $0) } }
        if let paths {
            for p in ann.paths ?? [] { ann.remove(p) }
            for p in paths { ann.add(p.copy() as! NSBezierPath) }
        }
        if let lineStart { ann.startPoint = lineStart }
        if let lineEnd { ann.endPoint = lineEnd }
        ann.modificationDate = Date()
    }

    /// Bounding box of the inner geometry in annotation-local coordinates (nil when only `bounds` matters).
    var contentBox: NSRect? {
        var pts: [NSPoint] = quads ?? []
        if let lineStart, let lineEnd { pts += [lineStart, lineEnd] }
        var box: NSRect? = nil
        for p in paths ?? [] where !p.isEmpty { box = box.map { $0.union(p.bounds) } ?? p.bounds }
        guard let f = pts.first else { return box }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let r = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return box.map { $0.union(r) } ?? r
    }

    /// The same annotation stretched to `newBounds`. Inner geometry keeps its margins to the bounds edges
    /// (stroke padding stays the same width) and is scaled in between.
    public func resized(to newBounds: NSRect) -> AnnotationGeometry {
        var g = self
        g.bounds = newBounds
        guard let box = contentBox else { return g }
        let left = box.minX, bottom = box.minY
        let right = bounds.width - box.maxX, top = bounds.height - box.maxY
        let newW = max(newBounds.width - left - right, 0), newH = max(newBounds.height - bottom - top, 0)
        let sx = box.width > 0.01 ? newW / box.width : 1
        let sy = box.height > 0.01 ? newH / box.height : 1
        func map(_ p: NSPoint) -> NSPoint {
            NSPoint(x: left + (p.x - box.minX) * sx, y: bottom + (p.y - box.minY) * sy)
        }
        g.quads = quads?.map(map)
        var t = AffineTransform(translationByX: -box.minX, byY: -box.minY)
        t.append(AffineTransform(scaleByX: sx, byY: sy))
        t.append(AffineTransform(translationByX: left, byY: bottom))
        g.paths = paths?.map { let c = $0.copy() as! NSBezierPath; c.transform(using: t); return c }
        g.lineStart = lineStart.map(map)
        g.lineEnd = lineEnd.map(map)
        return g
    }
}

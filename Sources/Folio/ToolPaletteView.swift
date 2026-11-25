import AppKit
import FolioCore

/// The pencil case: one button per preconfigured tool, plus the pointer.
final class ToolPaletteView: NSStackView {
    var onSelect: ((ToolSpec) -> Void)?
    private var buttons: [(ToolSpec, NSButton)] = []

    var selectedID: String = ToolSpec.pointer.id {
        didSet { for (t, b) in buttons { b.state = t.id == selectedID ? .on : .off } }
    }

    init(tools: [ToolSpec]) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 2
        reload(tools: tools)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Rebuilds the buttons (after the tools were edited in Settings).
    func reload(tools: [ToolSpec]) {
        for v in arrangedSubviews { removeArrangedSubview(v); v.removeFromSuperview() }
        buttons = []
        var last: ToolKind? = nil
        for t in [ToolSpec.pointer] + tools {
            if let l = last, l != t.kind {
                let gap = NSView(); gap.widthAnchor.constraint(equalToConstant: 6).isActive = true
                addArrangedSubview(gap)
            }
            last = t.kind
            let b = NSButton(image: Self.icon(for: t), target: self, action: #selector(clicked(_:)))
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .texturedRounded
            b.isBordered = true
            b.imagePosition = .imageOnly
            b.toolTip = t.key.map { "\(t.name)  (\($0))" } ?? "\(t.name)  (Esc / V)"
            b.widthAnchor.constraint(equalToConstant: 28).isActive = true
            b.tag = buttons.count
            buttons.append((t, b))
            addArrangedSubview(b)
        }
        let keep = selectedID
        selectedID = buttons.contains { $0.0.id == keep } ? keep : ToolSpec.pointer.id
    }

    @objc private func clicked(_ sender: NSButton) {
        let t = buttons[sender.tag].0
        onSelect?(t.id == selectedID && t.kind != .select ? .pointer : t)
    }

    static func icon(for t: ToolSpec) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let solid = t.nsColor.withAlphaComponent(1)
            switch t.kind {
            case .select:
                if let arrow = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) {
                    let r = NSRect(x: (size.width - arrow.size.width) / 2, y: (size.height - arrow.size.height) / 2,
                                   width: arrow.size.width, height: arrow.size.height)
                    NSColor.labelColor.set()
                    arrow.draw(in: r)
                }
            case .marker:
                // Chisel marker stroke
                let r = NSRect(x: 2, y: 5, width: 16, height: 9)
                t.nsColor.withAlphaComponent(max(0.55, t.nsColor.alphaComponent)).setFill()
                NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
                Self.drawLetter("a", in: NSRect(x: 0, y: 2, width: 20, height: 14), color: .labelColor)
            case .underline:
                Self.drawLetter("U", in: NSRect(x: 0, y: 4, width: 20, height: 14), color: .labelColor)
                solid.setFill(); NSRect(x: 3, y: 2, width: 14, height: 2).fill()
            case .squiggly:
                Self.drawLetter("S", in: NSRect(x: 0, y: 4, width: 20, height: 14), color: .labelColor)
                let p = NSBezierPath(); p.lineWidth = 1.5
                p.move(to: NSPoint(x: 2, y: 3))
                var x: CGFloat = 2; var up = true
                while x < 18 { x += 2; p.line(to: NSPoint(x: x, y: up ? 5 : 1.5)); up.toggle() }
                solid.setStroke(); p.stroke()
            case .pen:
                let p = NSBezierPath(); p.lineWidth = 1.8; p.lineCapStyle = .round; p.lineJoinStyle = .round
                p.move(to: NSPoint(x: 3, y: 5))
                p.curve(to: NSPoint(x: 10, y: 10), controlPoint1: NSPoint(x: 5, y: 14), controlPoint2: NSPoint(x: 8, y: 2))
                p.curve(to: NSPoint(x: 17, y: 13), controlPoint1: NSPoint(x: 12, y: 17), controlPoint2: NSPoint(x: 15, y: 6))
                solid.setStroke(); p.stroke()
            case .text:
                Self.drawLetter("T", in: NSRect(x: 0, y: 1, width: 20, height: 16), color: solid, bold: true)
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func drawLetter(_ s: String, in r: NSRect, color: NSColor, bold: Bool = false) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let font = NSFont.systemFont(ofSize: 12, weight: bold ? .bold : .medium)
        (s as NSString).draw(in: r, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }
}

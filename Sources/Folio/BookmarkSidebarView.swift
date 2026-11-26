import AppKit
import FolioCore

/// Ribbon colours, by bookmark position: Current red, then aqua, green, purple.
enum RibbonColor {
    static let all: [NSColor] = [
        NSColor(srgbRed: 0.86, green: 0.15, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.00, green: 0.59, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.66, blue: 0.29, alpha: 1),
        NSColor(srgbRed: 0.58, green: 0.32, blue: 0.80, alpha: 1),
    ]
    static func at(_ i: Int) -> NSColor { all[i % all.count] }
}

/// One bookmark in the sidebar: [ribbon] name / page, [pin]. Click the row to go there (or to place it,
/// if it isn't placed yet); the pin moves it to the current page. The active (following) row is filled
/// with its ribbon colour and its page number updates as you scroll.
final class BookmarkRow: NSView {
    let id: String
    var onClick: (() -> Void)?
    let pin: NSButton
    private let ribbon = RibbonGlyph()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var color: NSColor = .systemRed
    private var active = false
    private var hover = false

    init(id: String, target: AnyObject, pinAction: Selector) {
        self.id = id
        pin = NSButton(image: NSImage(systemSymbolName: "pin", accessibilityDescription: "Move here")!, target: target, action: pinAction)
        super.init(frame: .zero)
        pin.identifier = NSUserInterfaceItemIdentifier(id)
        pin.isBordered = false
        pin.bezelStyle = .recessed
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 0
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        pin.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [ribbon, text, spacer, pin])
        row.spacing = 8; row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            ribbon.widthAnchor.constraint(equalToConstant: 12), ribbon.heightAnchor.constraint(equalToConstant: 20),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(name: String, color: NSColor, active: Bool, placed: Bool, page: String?, shortcut: Int) {
        self.color = color; self.active = active
        ribbon.color = color; ribbon.filled = placed
        title.stringValue = name
        title.font = .systemFont(ofSize: 13, weight: active ? .bold : .medium)
        title.textColor = active ? .white : .labelColor
        if !placed {
            detail.stringValue = "Click to place here"
            detail.textColor = .controlAccentColor
        } else {
            detail.stringValue = "p. \(page ?? "?")" + (active ? "  · with you" : "")
            detail.textColor = active ? NSColor.white.withAlphaComponent(0.9) : .secondaryLabelColor
        }
        pin.contentTintColor = active ? .white : .secondaryLabelColor
        ribbon.outline = active
        toolTip = placed ? (active ? "“\(name)” moves with you as you read (⌃\(shortcut))" : "Go to “\(name)” (⌃\(shortcut))")
                         : "Click to place “\(name)” on this page (⌃\(shortcut))"
        pin.toolTip = "Move “\(name)” to this page; it then moves with you (⌃⌥\(shortcut))"
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        if active { color.setFill(); path.fill() }
        else if hover { NSColor.labelColor.withAlphaComponent(0.06).setFill(); path.fill() }
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    func performClick() { onClick?() }
}

/// A small ribbon glyph (filled when placed, outlined when not).
final class RibbonGlyph: NSView {
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var filled = true { didSet { needsDisplay = true } }
    var outline = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let path = RibbonGlyph.path(in: bounds.insetBy(dx: 1, dy: 1))
        if filled { (outline ? NSColor.white : color).setFill(); path.fill() }
        else { color.setStroke(); path.lineWidth = 1.5; path.stroke() }
    }
    static func path(in r: NSRect) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX, y: r.maxY)); p.line(to: NSPoint(x: r.maxX, y: r.maxY))
        p.line(to: NSPoint(x: r.maxX, y: r.minY)); p.line(to: NSPoint(x: r.midX, y: r.minY + r.width * 0.55))
        p.line(to: NSPoint(x: r.minX, y: r.minY)); p.close()
        return p
    }
}

/// The bookmark section at the top of the left column: header with "+", rows, Back, and a hint when
/// nothing follows you.
final class BookmarkSidebarView: NSView {
    var onGo: ((String) -> Void)?
    var onPin: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onAdd: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onRemove: ((String) -> Void)?

    private let stack = NSStackView()
    private let rowsStack = NSStackView()
    private(set) var rows: [String: BookmarkRow] = [:]
    var pinButtons: [String: NSButton] { rows.mapValues(\.pin) }
    let backButton = NSButton()
    let addButton = NSButton()
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var shownStructure: [String] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        let header = NSTextField(labelWithString: "BOOKMARKS")
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.textColor = .secondaryLabelColor
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add bookmark")
        addButton.isBordered = false
        addButton.target = self; addButton.action = #selector(addPressed)
        addButton.toolTip = "Add a bookmark on this page (⌘D)"
        let headerRow = NSStackView(views: [header, NSView(), addButton])
        headerRow.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 2, right: 10)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 2

        backButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Back")
        backButton.imagePosition = .imageLeading
        backButton.title = "Back"
        backButton.bezelStyle = .recessed
        backButton.controlSize = .small
        backButton.target = self; backButton.action = #selector(backPressed)
        backButton.toolTip = "Back to where you were before the last jump (⌘[). Press again to return."

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemOrange
        statusLabel.preferredMaxLayoutWidth = 140

        let backRow = NSStackView(views: [backButton])
        backRow.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 0, right: 10)
        let statusRow = NSStackView(views: [statusLabel])
        statusRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        for v in [headerRow, rowsStack, backRow, statusRow] { stack.addArrangedSubview(v) }
        for v in [headerRow, rowsStack, statusRow] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func reload(_ state: BookmarkState, pageLabel: (Int) -> String) {
        let structure = state.bookmarks.map { $0.id + "\u{1}" + $0.name } + [state.canAdd ? "+" : ""]
        if structure != shownStructure {
            shownStructure = structure
            rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            rows = [:]
            for b in state.bookmarks {
                let row = BookmarkRow(id: b.id, target: self, pinAction: #selector(pinPressed(_:)))
                row.onClick = { [weak self] in self?.onGo?(b.id) }
                row.menu = contextMenu(for: b)
                rowsStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
                rows[b.id] = row
            }
            addButton.isHidden = !state.canAdd
        }
        for (i, b) in state.bookmarks.enumerated() {
            rows[b.id]?.update(name: b.name, color: RibbonColor.at(i), active: b.id == state.activeID, placed: b.isPlaced,
                               page: b.spot.map { pageLabel($0.page) }, shortcut: i + 1)
        }
        backButton.isEnabled = state.back != nil
        let anyPlaced = state.bookmarks.contains { $0.isPlaced }
        statusLabel.stringValue = !anyPlaced ? "Place “\(state.bookmarks.first?.name ?? "Current")” where you stopped: click it."
            : state.activeID == nil ? "No bookmark moves with you. Click a pin to bring one here." : ""
        statusLabel.isHidden = statusLabel.stringValue.isEmpty
    }

    private func contextMenu(for b: Bookmark) -> NSMenu {
        let m = NSMenu()
        let rename = NSMenuItem(title: "Rename “\(b.name)”…", action: #selector(renamePressed(_:)), keyEquivalent: "")
        rename.representedObject = b.id; rename.target = self
        m.addItem(rename)
        if b.id != BookmarkState.currentID {
            let remove = NSMenuItem(title: "Remove “\(b.name)”", action: #selector(removePressed(_:)), keyEquivalent: "")
            remove.representedObject = b.id; remove.target = self
            m.addItem(remove)
        }
        return m
    }

    @objc private func pinPressed(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onPin?(id) } }
    @objc private func backPressed() { onBack?() }
    @objc private func addPressed() { onAdd?() }
    @objc private func renamePressed(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onRename?(id) } }
    @objc private func removePressed(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onRemove?(id) } }
}

/// Draws each placed bookmark as a ribbon at the right edge of its page; the active one sits at the top of
/// the view, so you can see you're carrying it. Transparent to clicks.
final class RibbonOverlay: NSView {
    struct Ribbon { var point: NSPoint; var color: NSColor; var active: Bool; var name: String }
    var ribbons: [Ribbon] = [] { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        for r in ribbons {
            let w: CGFloat = r.active ? 18 : 14, h: CGFloat = r.active ? 40 : 30
            let rect = NSRect(x: r.point.x - w - 8, y: r.point.y - h, width: w, height: h)
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow(); sh.shadowBlurRadius = 3; sh.shadowOffset = NSSize(width: 0, height: -1)
            sh.shadowColor = NSColor.black.withAlphaComponent(0.3); sh.set()
            r.color.withAlphaComponent(r.active ? 1 : 0.85).setFill()
            RibbonGlyph.path(in: rect).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

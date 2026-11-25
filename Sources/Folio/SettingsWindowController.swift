import AppKit
import FolioCore

/// Settings ▸ Tools: configure the pencil case. 1–5 tools per kind; colour, opacity (markers),
/// line width (underline / curly / pen), font and size (text), name and shortcut key.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onSave: (([ToolSpec]) -> Void)?

    private var tools: [ToolSpec]
    private var rows: [ToolRow] = []
    private let stack = NSStackView()

    static let widths: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3, 4]
    static let fontSizes: [Double] = [8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28]
    static let fonts: [String] = {
        let wanted = ["Helvetica", "Helvetica Neue", "Arial", "Avenir Next", "Gill Sans", "Georgia", "Times New Roman",
                      "Palatino", "Baskerville", "Courier New", "Menlo", "Noteworthy", "Marker Felt", "Chalkboard SE", "Bradley Hand"]
        let have = Set(NSFontManager.shared.availableFontFamilies)
        return wanted.filter { have.contains($0) }
    }()

    init(tools: [ToolSpec]) {
        self.tools = tools
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 800),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Tools"
        w.minSize = NSSize(width: 640, height: 400)
        super.init(window: w)
        w.delegate = self
        w.center()
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func build() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = doc
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let restore = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        let hint = NSTextField(labelWithString: "Changes apply to new annotations. Up to \(ToolConfig.maxPerKind) tools of each kind.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        let bar = NSStackView(views: [restore, hint, NSView(), cancel, save])
        bar.orientation = .horizontal
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(bar)
        window?.contentView = content
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        NSColorPanel.shared.showsAlpha = true
        rebuildRows()
    }

    private func rebuildRows() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        rows = []
        for kind in ToolKind.configurable {
            let header = NSTextField(labelWithString: kind.groupName)
            header.font = .boldSystemFont(ofSize: 13)
            if kind != ToolKind.configurable.first { stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!) }
            stack.addArrangedSubview(header)
            let mine = tools.filter { $0.kind == kind }
            for t in mine {
                let row = ToolRow(tool: t, canRemove: mine.count > 1)
                row.onRemove = { [weak self] r in self?.remove(r) }
                rows.append(row)
                stack.addArrangedSubview(row.view)
            }
            let add = NSButton(title: "Add \(kind.groupName.lowercased().replacingOccurrences(of: "s$", with: "", options: .regularExpression))",
                               target: self, action: #selector(addTool(_:)))
            add.isBordered = false
            add.contentTintColor = .controlAccentColor
            add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            add.imagePosition = .imageLeading
            add.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
            add.isEnabled = mine.count < ToolConfig.maxPerKind
            stack.addArrangedSubview(add)
        }
    }

    // MARK: Actions

    private func collect() -> [ToolSpec] { rows.map { $0.spec() } }

    @objc private func addTool(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let kind = ToolKind(rawValue: raw) else { return }
        tools = collect()
        guard tools.filter({ $0.kind == kind }).count < ToolConfig.maxPerKind else { return }
        let base = ToolConfig.defaults.first { $0.kind == kind }!
        var t = base
        t.id = "\(kind.rawValue)-\(UUID().uuidString.prefix(8).lowercased())"
        t.name = "New \(base.name.lowercased().split(separator: " ").dropFirst().joined(separator: " "))"
        t.key = nil
        let lastIndex = tools.lastIndex { $0.kind == kind } ?? tools.count - 1
        tools.insert(t, at: lastIndex + 1)
        rebuildRows()
    }

    private func remove(_ row: ToolRow) {
        tools = collect().filter { $0.id != row.id }
        rebuildRows()
    }

    @objc private func restoreDefaults() {
        tools = ToolConfig.defaults
        rebuildRows()
    }

    @objc private func cancel() { window?.close() }

    @objc private func save() {
        let t = collect()
        let problems = ToolConfig.validate(t)
        guard problems.isEmpty else {
            let a = NSAlert()
            a.messageText = "Please fix these first"
            a.informativeText = problems.joined(separator: "\n")
            a.beginSheetModal(for: window!)
            return
        }
        do {
            try ToolConfig.save(t)
        } catch {
            NSAlert(error: error).beginSheetModal(for: window!)
            return
        }
        tools = t
        onSave?(ToolConfig.normalized(t))
        window?.close()
    }

    /// Lets tests and the app reuse the window with fresh values.
    func reset(tools: [ToolSpec]) {
        self.tools = tools
        rebuildRows()
    }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// One tool's controls.
private final class ToolRow {
    let id: String
    let kind: ToolKind
    let view: NSStackView
    var onRemove: ((ToolRow) -> Void)?

    private let base: ToolSpec
    private let colorWell = NSColorWell()
    private let name = NSTextField()
    private let key = NSTextField()
    private var opacity: NSSlider?
    private var width: NSPopUpButton?
    private var font: NSPopUpButton?
    private var size: NSPopUpButton?

    init(tool: ToolSpec, canRemove: Bool) {
        base = tool; id = tool.id; kind = tool.kind
        view = NSStackView()
        view.orientation = .horizontal
        view.spacing = 8

        let c = tool.nsColor
        colorWell.color = kind == .marker ? c.withAlphaComponent(1) : c
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        name.stringValue = tool.name
        name.widthAnchor.constraint(equalToConstant: 150).isActive = true
        view.addArrangedSubview(colorWell)
        view.addArrangedSubview(name)

        switch kind {
        case .marker:
            let s = NSSlider(value: Double(c.alphaComponent), minValue: 0.1, maxValue: 0.9, target: nil, action: nil)
            s.widthAnchor.constraint(equalToConstant: 120).isActive = true
            s.toolTip = "Opacity"
            opacity = s
            view.addArrangedSubview(label("Opacity"))
            view.addArrangedSubview(s)
        case .underline, .squiggly, .pen:
            let p = NSPopUpButton()
            for w in SettingsWindowController.widths { p.addItem(withTitle: Self.fmt(w) + " pt") }
            p.selectItem(at: Self.nearest(Double(tool.lineWidth), in: SettingsWindowController.widths))
            width = p
            view.addArrangedSubview(label("Width"))
            view.addArrangedSubview(p)
        case .text:
            let f = NSPopUpButton()
            var fonts = SettingsWindowController.fonts
            let current = tool.fontName ?? "Helvetica"
            if !fonts.contains(current) { fonts.insert(current, at: 0) }
            for n in fonts {
                f.addItem(withTitle: n)
                f.lastItem?.attributedTitle = NSAttributedString(string: n, attributes: [.font: NSFont(name: n, size: 13) ?? NSFont.systemFont(ofSize: 13)])
            }
            f.selectItem(withTitle: current)
            f.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let s = NSPopUpButton()
            for v in SettingsWindowController.fontSizes { s.addItem(withTitle: Self.fmt(v) + " pt") }
            s.selectItem(at: Self.nearest(tool.fontSize ?? 12, in: SettingsWindowController.fontSizes))
            font = f; size = s
            view.addArrangedSubview(f)
            view.addArrangedSubview(s)
        case .select: break
        }

        view.addArrangedSubview(NSView()) // flexible gap
        key.stringValue = tool.key ?? ""
        key.placeholderString = "–"
        key.alignment = .center
        key.widthAnchor.constraint(equalToConstant: 30).isActive = true
        key.toolTip = "Shortcut key (one character, optional)"
        view.addArrangedSubview(label("Key"))
        view.addArrangedSubview(key)
        let rm = NSButton(image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: "Remove")!, target: self, action: #selector(removeClicked))
        rm.isBordered = false
        rm.isEnabled = canRemove
        rm.toolTip = canRemove ? "Remove this tool" : "Each kind needs at least one tool"
        view.addArrangedSubview(rm)
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.textColor = .secondaryLabelColor
        return l
    }

    @objc private func removeClicked() { onRemove?(self) }

    func spec() -> ToolSpec {
        var t = base
        t.name = name.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? base.name : name.stringValue
        var c = colorWell.color
        if let o = opacity { c = c.withAlphaComponent(CGFloat(o.doubleValue)) }
        t.color = c.hexString
        let k = key.stringValue.trimmingCharacters(in: .whitespaces)
        t.key = k.isEmpty ? nil : k.lowercased()
        if let w = width { t.width = SettingsWindowController.widths[w.indexOfSelectedItem] }
        if let f = font { t.fontName = f.titleOfSelectedItem }
        if let s = size { t.fontSize = SettingsWindowController.fontSizes[s.indexOfSelectedItem] }
        return t
    }

    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
    static func nearest(_ v: Double, in list: [Double]) -> Int {
        list.indices.min { abs(list[$0] - v) < abs(list[$1] - v) } ?? 0
    }
}

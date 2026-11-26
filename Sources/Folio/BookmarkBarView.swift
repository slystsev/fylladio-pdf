import AppKit
import FolioCore

/// The ribbon bar under the toolbar: Back, then each bookmark as [name | pin], then "+".
/// Name: go there (one click). Pin: put this bookmark on the current page and let it follow you.
/// The active (following) bookmark is highlighted; when none is, nothing is.
final class BookmarkBarView: NSView {
    var onGo: ((String) -> Void)?
    var onPin: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onAdd: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onRemove: ((String) -> Void)?

    private let stack = NSStackView()
    private(set) var nameButtons: [String: NSButton] = [:]
    private(set) var pinButtons: [String: NSButton] = [:]
    let backButton = NSButton()
    let addButton = NSButton()
    let statusLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 30),
        ])

        backButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Back")
        backButton.imagePosition = .imageLeading
        backButton.title = "Back"
        backButton.bezelStyle = .recessed
        backButton.controlSize = .small
        backButton.target = self
        backButton.action = #selector(backPressed)
        backButton.toolTip = "Back to where you were before the last jump (⌘[). Press again to return."

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add bookmark")
        addButton.bezelStyle = .recessed
        addButton.controlSize = .small
        addButton.target = self
        addButton.action = #selector(addPressed)
        addButton.toolTip = "Add a bookmark here"

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
    }
    required init?(coder: NSCoder) { fatalError() }

    private var shownStructure: [String] = []

    func reload(_ state: BookmarkState, pageLabel: (Int) -> String) {
        // Rebuild only when bookmarks were added, removed or renamed; otherwise update in place (no relayout).
        let structure = state.bookmarks.map { $0.id + "\u{1}" + $0.name } + [state.canAdd ? "+" : ""]
        if structure == shownStructure {
            update(state, pageLabel: pageLabel)
            return
        }
        shownStructure = structure
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        nameButtons = [:]; pinButtons = [:]
        stack.addArrangedSubview(backButton)
        let sep = NSBox(); sep.boxType = .separator
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 16).isActive = true
        stack.addArrangedSubview(sep)
        for (i, b) in state.bookmarks.enumerated() {
            let name = NSButton(title: b.name, target: self, action: #selector(namePressed(_:)))
            name.identifier = NSUserInterfaceItemIdentifier(b.id)
            name.bezelStyle = .recessed
            name.setButtonType(.pushOnPushOff)
            name.controlSize = .small
            name.imagePosition = .imageLeading
            name.menu = contextMenu(for: b)

            let pin = NSButton(image: NSImage(systemSymbolName: "pin", accessibilityDescription: "Move here")!,
                               target: self, action: #selector(pinPressed(_:)))
            pin.identifier = NSUserInterfaceItemIdentifier(b.id)
            pin.bezelStyle = .recessed
            pin.isBordered = false
            pin.controlSize = .small
            pin.toolTip = "Move “\(b.name)” to this page; it then follows your reading (⌃⌥\(i + 1))"

            let pair = NSStackView(views: [name, pin])
            pair.spacing = 0
            stack.addArrangedSubview(pair)
            nameButtons[b.id] = name; pinButtons[b.id] = pin
        }
        if state.canAdd { stack.addArrangedSubview(addButton) }
        stack.addArrangedSubview(statusLabel)
        update(state, pageLabel: pageLabel)
    }

    /// Highlights the active bookmark, refreshes tooltips (page numbers), Back and the status line.
    private func update(_ state: BookmarkState, pageLabel: (Int) -> String) {
        backButton.isEnabled = state.back != nil
        for (i, b) in state.bookmarks.enumerated() {
            guard let name = nameButtons[b.id] else { continue }
            let active = b.id == state.activeID
            name.state = active ? .on : .off
            name.font = active ? .boldSystemFont(ofSize: NSFont.smallSystemFontSize) : .systemFont(ofSize: NSFont.smallSystemFontSize)
            name.image = NSImage(systemSymbolName: active ? "bookmark.fill" : "bookmark", accessibilityDescription: nil)
            name.contentTintColor = active ? .controlAccentColor : nil
            name.toolTip = "Go to “\(b.name)”, page \(pageLabel(b.spot.page)) (⌃\(i + 1))" + (active ? " — follows your reading" : "")
        }
        statusLabel.stringValue = state.activeID == nil ? "No bookmark follows you — pin one to keep your place" : ""
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

    @objc private func namePressed(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onGo?(id) } }
    @objc private func pinPressed(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onPin?(id) } }
    @objc private func backPressed() { onBack?() }
    @objc private func addPressed() { onAdd?() }
    @objc private func renamePressed(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onRename?(id) } }
    @objc private func removePressed(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onRemove?(id) } }
}

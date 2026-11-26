import AppKit
import PDFKit
import FolioCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var controllers: [DocumentWindowController] = []
    private(set) var tools = ToolConfig.load()
    private var settings: SettingsWindowController?
    private var openedAtLaunch = false
    private let openFilesKey = "Folio.openFiles"

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
    }

    var controllersForTest: [DocumentWindowController] { controllers }
    private let isSelfTest = ProcessInfo.processInfo.environment["FOLIO_SELFTEST"] != nil
    private var selfTest: SelfTest?
    private var selfTestActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.info("launch Folio \(version), pid \(ProcessInfo.processInfo.processIdentifier)")
        HangWatchdog.shared.start()
        let env = ProcessInfo.processInfo.environment
        if let out = env["FOLIO_SELFTEST"], let file = env["FOLIO_SELFTEST_FILE"] {
            // Runs in the background: keep App Nap from slowing it down, and watch for hangs anyway.
            selfTestActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Folio self-test")
            HangWatchdog.shared.forceActive()
            open(URL(fileURLWithPath: file))
            selfTest = SelfTest(out: URL(fileURLWithPath: out), app: self)
            selfTest?.run()
            return
        }
        // Restore last session's windows unless the app was launched to open specific files.
        if !openedAtLaunch {
            let paths = FolioDefaults.shared.stringArray(forKey: openFilesKey) ?? []
            for p in paths where FileManager.default.fileExists(atPath: p) { open(URL(fileURLWithPath: p)) }
            if controllers.isEmpty { openDocument(nil) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAtLaunch = true
        for u in urls { open(u) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDocument(nil) }
        return true
    }

    func applicationWillResignActive(_ notification: Notification) { controllers.forEach { $0.flush() } }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controllers.forEach { $0.flush() }
        Log.timed("quit: waiting for saves", threshold: 0) { SaveQueue.waitForAll() }
        JournalQueue.queue.sync {}   // pending journal deletes
        BookmarkStore.shared.flush()
        rememberOpenFiles(controllers.map(\.url))
        terminating = true
        return .terminateNow
    }
    private var terminating = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Documents

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        if let existing = controllers.first(where: { $0.url == url }) {
            existing.window?.makeKeyAndOrderFront(nil); return
        }
        let tools = self.tools
        let opened: DocumentWindowController? = Log.timed("open \(url.lastPathComponent)", threshold: 0) {
            DocumentWindowController(url: url, tools: tools)
        }
        guard let c = opened else {
            Log.info("open failed: \(url.path)")
            let a = NSAlert()
            a.messageText = "Couldn't open “\(url.lastPathComponent)”"
            a.informativeText = "The file is not a readable PDF."
            a.runModal()
            return
        }
        if c.pdfDocument.isLocked {
            let a = NSAlert()
            a.messageText = "“\(url.lastPathComponent)” is password protected"
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            a.accessoryView = field
            a.addButton(withTitle: "Unlock"); a.addButton(withTitle: "Cancel")
            a.window.initialFirstResponder = field
            guard a.runModal() == .alertFirstButtonReturn, c.pdfDocument.unlock(withPassword: field.stringValue) else { return }
        }
        c.onClose = { [weak self] closed in
            guard let self else { return }
            self.controllers.removeAll { $0 === closed }
            if !self.terminating { self.rememberOpenFiles(self.controllers.map(\.url)) }
        }
        controllers.append(c)
        if let key = NSApp.keyWindow, key.tabbingMode != .disallowed, controllers.count > 1 {
            key.addTabbedWindow(c.window!, ordered: .above)
        }
        if isSelfTest { c.window?.alphaValue = 0; c.window?.ignoresMouseEvents = true }
        Log.timed("show window \(url.lastPathComponent)") { c.showWindow(nil) }
        Log.timed("restore position \(url.lastPathComponent)") { c.restorePosition() }
        c.offerRecovery()
        c.window?.makeFirstResponder(c.pdfView)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        rememberOpenFiles(controllers.map(\.url))
    }

    private func rememberOpenFiles(_ urls: [URL]) {
        FolioDefaults.shared.set(urls.map(\.path), forKey: openFilesKey)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(open) }
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        if let u = sender.representedObject as? URL { open(u) }
    }

    @objc func clearRecent(_ sender: Any?) { NSDocumentController.shared.clearRecentDocuments(sender) }

    @objc func showSettings(_ sender: Any?) {
        if settings == nil {
            let s = SettingsWindowController(tools: tools)
            s.onSave = { [weak self] t in self?.apply(tools: t) }
            settings = s
        } else {
            settings?.reset(tools: tools)
        }
        if isSelfTest { settings?.window?.alphaValue = 0; settings?.window?.ignoresMouseEvents = true }
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    func apply(tools newTools: [ToolSpec]) {
        tools = newTools
        controllers.forEach { $0.updateTools(newTools) }
        NSApp.mainMenu = buildMenu()
    }

    @objc func revealToolsFile(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([ToolConfig.fileURL])
    }

    @objc func revealBackups(_ sender: Any?) {
        NSWorkspace.shared.open(SafeSaver.backupDirectory)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { true }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            build(m)
            item.submenu = m
            main.addItem(item)
        }
        func add(_ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            m.addItem(i)
        }

        submenu("Folio") { m in
            add(m, "About Folio", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            m.addItem(.separator())
            add(m, "Settings…", #selector(showSettings(_:)), ",")
            add(m, "Reveal Tools File", #selector(revealToolsFile(_:)))
            add(m, "Show Backups Folder", #selector(revealBackups(_:)))
            m.addItem(.separator())
            add(m, "Hide Folio", #selector(NSApplication.hide(_:)), "h")
            add(m, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            add(m, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
            m.addItem(.separator())
            add(m, "Quit Folio", #selector(NSApplication.terminate(_:)), "q")
        }
        submenu("File") { m in
            add(m, "Open…", #selector(openDocument(_:)), "o")
            let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            let rm = NSMenu(title: "Open Recent")
            rm.delegate = self
            recent.submenu = rm
            m.addItem(recent)
            m.addItem(.separator())
            add(m, "Close", #selector(NSWindow.performClose(_:)), "w")
            add(m, "Save Now", #selector(DocumentWindowController.saveDocument(_:)), "s")
            add(m, "Save a Copy…", #selector(DocumentWindowController.saveCopy(_:)), "s", [.command, .shift])
            m.addItem(.separator())
            add(m, "Print…", #selector(DocumentWindowController.printDocument(_:)), "p")
            add(m, "Print Selected Pages…", #selector(DocumentWindowController.printSelectedPages(_:)), "p", [.command, .option])
        }
        submenu("Edit") { m in
            add(m, "Undo", Selector(("undo:")), "z")
            add(m, "Redo", Selector(("redo:")), "z", [.command, .shift])
            m.addItem(.separator())
            add(m, "Cut", #selector(NSText.cut(_:)), "x")
            add(m, "Copy", #selector(NSText.copy(_:)), "c")
            add(m, "Paste", #selector(NSText.paste(_:)), "v")
            add(m, "Delete", #selector(NSText.delete(_:)))
            add(m, "Select All", #selector(NSText.selectAll(_:)), "a")
            m.addItem(.separator())
            add(m, "Find…", #selector(DocumentWindowController.performFind(_:)), "f")
            add(m, "Find Next", #selector(DocumentWindowController.findNext(_:)), "g")
            add(m, "Find Previous", #selector(DocumentWindowController.findPrevious(_:)), "g", [.command, .shift])
        }
        submenu("View") { m in
            add(m, "Show Thumbnails", #selector(DocumentWindowController.toggleSidebar(_:)), "s", [.command, .option])
            m.addItem(.separator())
            add(m, "Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "+")
            add(m, "Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "=")
            m.items.last?.isAlternate = false; m.items.last?.isHidden = true; m.items.last?.allowsKeyEquivalentWhenHidden = true
            add(m, "Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-")
            add(m, "Actual Size", #selector(DocumentWindowController.actualSize(_:)), "0")
            add(m, "Fit Width", #selector(DocumentWindowController.fitWidth(_:)), "9")
            m.addItem(.separator())
            add(m, "Single Page", #selector(DocumentWindowController.singlePage(_:)), "1")
            add(m, "Two Pages", #selector(DocumentWindowController.twoPages(_:)), "2")
            m.addItem(.separator())
            add(m, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        }
        submenu("Go") { m in
            add(m, "Go to Page…", #selector(DocumentWindowController.goToPage(_:)), "g", [.command, .option])
            m.addItem(.separator())
            add(m, "Next Page", #selector(DocumentWindowController.nextPage(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option])
            add(m, "Previous Page", #selector(DocumentWindowController.previousPage(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option])
            add(m, "First Page", #selector(DocumentWindowController.firstPage(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command])
            add(m, "Last Page", #selector(DocumentWindowController.lastPage(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command])
            m.addItem(.separator())
            add(m, "Back", #selector(DocumentWindowController.goBack(_:)), "[")
            m.addItem(.separator())
            // Bookmark items: titles are filled in with the bookmark names when the menu is shown.
            for n in 1...BookmarkState.maxCount {
                let go = NSMenuItem(title: "Bookmark \(n)", action: #selector(DocumentWindowController.goToBookmark(_:)), keyEquivalent: "\(n)")
                go.keyEquivalentModifierMask = [.control]; go.tag = n
                m.addItem(go)
            }
            m.addItem(.separator())
            for n in 1...BookmarkState.maxCount {
                let pin = NSMenuItem(title: "Move Bookmark \(n) Here", action: #selector(DocumentWindowController.pinBookmark(_:)), keyEquivalent: "\(n)")
                pin.keyEquivalentModifierMask = [.control, .option]; pin.tag = n
                m.addItem(pin)
            }
            add(m, "Add Bookmark Here…", #selector(DocumentWindowController.addBookmark(_:)), "d", [.command])
        }
        submenu("Tools") { m in
            let ptr = NSMenuItem(title: "Pointer\t\tEsc", action: #selector(DocumentWindowController.chooseTool(_:)), keyEquivalent: "")
            ptr.representedObject = ToolSpec.pointer.id
            m.addItem(ptr)
            m.addItem(.separator())
            var last: ToolKind?
            for t in tools {
                if let l = last, l != t.kind { m.addItem(.separator()) }
                last = t.kind
                let i = NSMenuItem(title: t.name + (t.key.map { "\t\t\($0)" } ?? ""), action: #selector(DocumentWindowController.chooseTool(_:)), keyEquivalent: "")
                i.representedObject = t.id
                i.image = ToolPaletteView.icon(for: t)
                m.addItem(i)
            }
            m.addItem(.separator())
            for line in ["⌥-drag: rectangle / free line even over text", "⇧-drag: keep lines horizontal",
                         "Pointer: drag an annotation to move it, arrows nudge"] {
                let tip = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                tip.isEnabled = false
                m.addItem(tip)
            }
            m.addItem(.separator())
            add(m, "Configure Tools…", #selector(showSettings(_:)))
        }
        submenu("Window") { m in
            add(m, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            add(m, "Zoom", #selector(NSWindow.performZoom(_:)))
            m.addItem(.separator())
            add(m, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
            NSApp.windowsMenu = m
        }
        return main
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Open Recent" else { return }
        menu.removeAllItems()
        for u in NSDocumentController.shared.recentDocumentURLs {
            let i = NSMenuItem(title: u.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            i.representedObject = u
            i.target = self
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }
}

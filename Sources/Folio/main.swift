import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// The self-test runs invisibly beside the user's own Folio: no Dock icon or menu bar (accessory), and its
// windows are see-through and ignore clicks (AppDelegate).
app.setActivationPolicy(ProcessInfo.processInfo.environment["FOLIO_SELFTEST"] != nil ? .accessory : .regular)
app.run()

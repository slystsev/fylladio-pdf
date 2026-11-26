import AppKit

import FylladioCore

// First launch after the rename from Folio: bring the user's data over before anything loads it.
let migrated = LegacyMigration.runIfNeeded()
if !migrated.isEmpty { Log.info("migrated from Folio: \(migrated.sorted().joined(separator: ", "))") }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// The self-test runs invisibly beside the user's own Fylladio: no Dock icon or menu bar (accessory), and its
// windows are see-through and ignore clicks (AppDelegate).
app.setActivationPolicy(ProcessInfo.processInfo.environment["FYLLADIO_SELFTEST"] != nil ? .accessory : .regular)
app.run()

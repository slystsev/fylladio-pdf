# Folio: plan & status

Restart guide: read docs/DESIGN.md (decisions, verified facts, testing), then continue at the first unchecked item.
Build: `scripts/build-app.sh` → `dist/Folio.app`. Checks: see "Testing" in DESIGN.md.

## Milestone 1: core app (done 2026-11-25)
- [x] Package skeleton, app bundle script, Info.plist (PDF document type, "Open With")
- [x] FolioCore: ToolSpec + tools.json defaults/loading
- [x] FolioCore: AnnotationFactory (markup from text lines / rect, squiggle-as-ink, free text, char hit test)
- [x] FolioCore: SafeSaver (temp + atomic replace, backups, keeps last 30)
- [x] FolioCore: PositionStore
- [x] App: open, recent, restore last session's windows, tabs, password unlock
- [x] Window: PDFView, thumbnail sidebar, toolbar (page field, zoom, tool palette, search)
- [x] Annotating view: tool modes, live drag preview, Option = rectangle, text entry/edit, select/delete, recolour menu, undo/redo
- [x] Search (async, next/prev, count, highlights)
- [x] Go to page (number or page label), menus and shortcuts
- [x] Print (system panel) + print pages selected in thumbnails
- [x] Autosave (adaptive debounce) + position restore
- [x] FolioCheck + UI self-test: all passing

## Milestone 2: user feedback round 1 (done 2026-11-25)
- [x] Underline/curly on non-text: point-to-point line (snap ≤5°, ⇧ flat)
- [x] Freehand pen tool, smoothed, 3 colours by default (Q/W/E)
- [x] Flatter curly underline (smooth sine, period 8)
- [x] Settings window: per-tool colour/opacity/width/font/size/name/key, 1–5 per kind
- [x] Move selected annotation (drag, arrow nudge), undo
- [x] Tests extended (FolioCheck + UI self-test, 37 checks)

## Milestone 2b: user feedback round 2 (done 2026-11-26)
- [x] Slowdown on big annotated file: save moved to background snapshot writes (D7)
- [x] Log file + hang watchdog with stack samples (D16)
- [x] Resize annotations (handles, ⇧ keeps aspect) and move across pages (D14a), tests (48 UI checks)

## Milestone 2c: user feedback round 3 (done 2026-11-26)
- [x] Pen icon: tilted nib like Preview's Draw (SF Symbol pencil.tip), distinct from the squiggle
- [x] Text tool: click marks the middle of the first line (was the top, so text landed a row lower)
- [x] Blue defaults are Aqua 0096FF; text defaults: blue 11 pt (key 9), red 7 pt between lines (key 0)
- [x] Watchdog: ping/answer, only while active (App Nap false alarms), pause after sampling
- Note: the user's round-3 test ran a Folio launched before the round-2 fixes (12:30 vs 12:43); stalls and the missing cross-page move are expected there. Re-test pending.
- Found: 41 Preview inks in the user's file have a collapsed /Rect (-2,-2,4,4); they are invisible 1 pt dots from Aug–Sep, harmless.

## Milestone 4: bookmarks (done 2026-11-26)
- [x] BookmarkState rules + store (FolioCore), unit-tested in FolioCheck
- [x] Bookmark bar (Back, [name|pin] ×4, +), Go menu items ⌃1–4 / ⌃⌥1–4 / ⌘D, rename/remove via right-click
- [x] Jump detection: page field, first/last, search, links, thumbnails; reading (scroll, Page Up/Down) follows
- [x] UI self-test (61 checks)

## Milestone 3: needs a human / next
- [ ] Hands-on test by the user with real documents (scans, big books); tune marker colours/alpha in tools.json
- [ ] Verify printing from the real dialog (can't be automated: modal panel)
- [ ] DECISION PENDING (asked user 2026-11-26): big-file saves. Option A: incremental-save writer (own PDF parser/writer, xref streams, object streams; appends only changed objects; risky). Option B: crash journal (sidecar of changed pages' annotations, NSSecureCoding) + save big files at most every ~30 s while editing, plus on close/switch/quit. B is much simpler.
- [x] App icon (scripts/make-icon.swift → Resources/Folio.icns)
- [ ] Developer ID signing + notarization (needs the user's Apple Developer account)
- Dropped: TOC sidebar (the user's book has a 1-entry outline; bookmarks cover it); typing digits to jump (digits are tool keys; ⌥⌘G exists)
- [ ] Optional: eraser tool

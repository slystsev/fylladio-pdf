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

## Milestone 3: needs a human / next
- [ ] Hands-on test by the user with real documents (scans, big books); tune marker colours/alpha in tools.json
- [ ] Verify printing from the real dialog (can't be automated: modal panel)
- [ ] Resize annotations; move across pages
- [ ] Incremental-save writer (append only changed objects) so huge files save instantly
- [ ] Crash journal (sidecar) for edits made inside the debounce window
- [ ] App icon; Developer ID signing + notarization for distribution
- [ ] Optional: outline/TOC sidebar, eraser tool, keyboard page-jump by typing digits

# Folio — design & decisions

A fast, lightweight native macOS PDF viewer/annotator that works like a desk of
stationery: a few pre-loaded markers and pens, always one keypress away. No
colour pickers, no per-use settings.

## Requirements (from the user)

- Very fast, low RAM, good with large files. Native Mac app, distributed outside the App Store.
- Navigation and search, plus go to a specific page.
- Print through the system dialog (page ranges, Save as PDF), including selected pages.
- Annotations:
  - Highlight in several colours at once. It must also work where the PDF has no
    real text (scans): a translucent rectangle.
  - Underline, straight and curly, in several colours.
  - Text notes in several colours.
  - Everything preconfigured, like a pencil case.
- Autosave. Never lose edits. Reopen at the last position.

## Decisions (made by Claude; revisit freely)

| # | Decision | Why |
|---|----------|-----|
| D1 | Swift + AppKit + PDFKit, no SwiftUI | PDFKit is Apple's native renderer: lazy, tiled page rendering, low RAM. AppKit gives full control of mouse and keys. |
| D2 | SwiftPM build plus `scripts/build-app.sh` to assemble `Folio.app` (ad-hoc signed) | Only Command Line Tools are installed, not Xcode. |
| D3 | Annotations are standard PDF annotations saved **into the PDF** | Other apps (Preview, Acrobat) see them, and nothing needs syncing. |
| D4 | Markers are /Highlight with quad points. On text, one quad per line. On non-text, one quad equal to the dragged rectangle. | One mechanism covers text and scans. |
| D4a | **Underline, curly underline and pen are all /Ink** (dense polylines). | Verified: PDFKit does not render /Squiggly. Ink renders everywhere and makes the width configurable. Trade-off: other apps list them as "ink". (User feedback, round 2.) |
| D4b | Underline and curly: a drag that starts on text snaps under each text line. Otherwise (or with ⌥) it is a **line from the start point to the end point**. Within 5° of horizontal it snaps flat; ⇧ forces flat. | User: "drawn at the bottom of the rectangle is counterintuitive; expect point to point." Snapping keeps hand-drawn underlines straight. |
| D4c | Curly underline is a smooth sine: period 8 pt, amplitude 1.1 pt (was a 4.5 pt zig-zag). | User asked for flatter waves. Constants are in `AnnotationFactory`. |
| D4d | Pen = freehand Ink: drop points under 0.8 pt apart, 1-2-1 moving average, then a Catmull-Rom curve sampled at about 1 pt. | Looks hand-drawn, not jagged, even for fast strokes. Ink stores only polylines, so curves are pre-sampled. |
| D4e | The tool kind is stored in the author field `/T` = `Folio/<kind>`. | Verified: PDFKit drops /NM and custom keys on save but keeps /T. Needed for recolouring after reopen. |
| D5 | Text vs rectangle is decided by **where the drag starts**: on a character → text mode, otherwise rectangle. Holding **Option** forces rectangle. | Predictable, and avoids the "highlight barely works" problem. |
| D6 | Tools come from `~/Library/Application Support/Folio/tools.json`, edited in **Settings (⌘,)**: colour, opacity (markers), width (lines and pens), font and size (text), name, optional one-key shortcut. **1–5 tools per kind** (assumed meaning of the user's "up to 5 tools"); the defaults are the current set plus 3 pens (Q/W/E). Esc/V = pointer. A tool stays active after use; its key again puts it down. An old tools.json missing a kind gets that kind's defaults. | "All preconfigured", but adjustable once without per-use pickers. |
| D6a | Changing settings affects only new annotations. | Existing marks are part of the document. Right-click recolour exists for single changes. |
| D7 | Autosave: every edit bumps an edit counter. The document is saved after an idle pause (1.5 s, up to 5 s for files that take long to write), on window close, resign-key, app deactivate, and quit. **The save runs in the background**: `PDFDocument.copy()` takes an independent snapshot (about 1 ms), and a serial queue writes it to a temp file and does an atomic replace. Edits made during a save keep the window dirty and trigger a follow-up save. Quit waits for pending saves. | Never lose edits, never leave a half-written file, never freeze. User report (round 3): a 92 MB, 377-page file with 3,400 Preview annotations takes 4–6 s to write, and the old main-thread save froze the window that long after edits. Verified: the snapshot is exact while the original is mutated concurrently (FolioCheck, plus a stress test on the real file). |
| D8 | Before the first save of a file in each session, a backup copy goes to `~/Library/Application Support/Folio/Backups/` (APFS clone, so cheap). Keeps the last 30. | Insurance against PDFKit write bugs corrupting a file. |
| D9 | Position (page, point, zoom) is stored per file path in UserDefaults and restored on open. Open windows are restored on relaunch. | "Keep position." |
| D10 | Search is async (`beginFindString`). Return/⌘G goes to the next result, ⇧Return/⇧⌘G to the previous. | Responsive on huge documents. |
| D11 | Print uses `PDFDocument.printOperation` with the standard panel (page range, PDF menu). "Print Selected Pages…" prints the pages selected in the thumbnail sidebar. | System dialog, as requested. |
| D12 | Thumbnail sidebar is hidden by default. | Saves RAM and CPU on large files. |
| D13 | Single-key tool shortcuts are handled in the PDF view's `keyDown`, not as menu key equivalents. | Menu equivalents without modifiers would swallow typing in the search field. |
| D14 | Pointer mode: click selects (dashed outline, open-hand cursor on hover), **drag moves**, arrows nudge 1 pt (⇧ 10 pt), Delete removes, double-click edits a note, right-click deletes or recolours. Full undo. Strokes are hit-tested near their path, not their bounding box. Moving works by shifting `bounds` (PDFKit stores quads and ink relative to it; verified to persist). | Basic editing without extra modes. |
| D14a | **Resize**: the selected annotation shows handles (8, or only the 2 that make sense for a thin line). A drag scales the bounds and the inner geometry (`AnnotationGeometry`: marker quads, ink paths via affine transform, line end points), keeping stroke padding constant. A corner drag with ⇧ keeps the proportions. **Cross-page move**: while dragging, the annotation follows the pointer onto another page. Both have undo. | User asked for the remaining plan items. |
| D14b | Preview's shapes saved as /Stamp (`/Name /Draft` plus the private `AAPL:AKExtras`, no /AP) are **not editable**. | Verified on the user's file (1,367 of them): PDFKit draws them from Apple's private data, and after any bounds change they vanish. Preview's Line, Ink, Square, Circle and FreeText resize fine. |
| D14c | Text tool: the click marks the **middle of the first line** (the I-beam's row), not the top of the box. | User: input appeared one row below the pointer. |
| D17 | **Bookmarks like ribbons in a book.** Up to 4 per file: Current (can't be removed), Review, plus 2 of your own (e.g. Answers). They sit in a bar under the toolbar, each as [name, pin]. Rules (`BookmarkState`): (1) at most one bookmark is *active*, the one you arrived through, and it follows your reading (scrolling, Page Up/Down); (2) going to a bookmark makes it active; (3) any other jump (page number, first/last page, search result, link, thumbnail) leaves none active, the bar says so, and nothing moves by accident; (4) the **pin** puts a bookmark here and makes it active (one click after "go to page N"); (5) **Back** (⌘[) toggles between the spot before the last jump and here, restoring which bookmark was active at each; (6) clicking the active bookmark does nothing. ⌃1–4 go to a bookmark, ⌃⌥1–4 pin, ⌘D adds one. A spot is measured 12 px below the visible top, so it lands on the page you see, not the gap between pages. | User: "simulation of a physical book"; one click to go, one click to move a bookmark here, always a way back to Current. |
| D17a | Bookmarks are stored by Folio (`bookmarks.json`, keyed by path; a moved or renamed file is matched by name when its old path is gone), **not in the PDF**. | The active bookmark changes as you scroll; writing that into a 92 MB PDF would mean constant saves and iCloud uploads. Trade-off: other apps and other Macs don't see them. |
| D17b | The window no longer uses a full-size content view (the document doesn't run under the toolbar). | PDFKit's "current destination" is the top of the whole view; under a translucent toolbar that's hidden, which put bookmarks one page early. |
| D15 | Minimum macOS 13. | Current SDK, broad enough. |
| D16 | Diagnostics: `~/Library/Logs/Folio/folio.log` (launch, opens, slow operations, every save with its duration), also in the unified log (subsystem `app.folio.pdf`). A watchdog thread pings the main queue every 0.25 s and, only while Folio is the active app (App Nap delays a background app and caused false alarms), logs any stall over 1 s with the current activity, and runs `/usr/bin/sample` to write the main thread's stack to `hang-*.txt` (at most 5 per session, 20 kept). | User saw a few-second stall early in a session that could not be reproduced. The next one will leave evidence. |

## Default tools (`tools.json`)

| Key | Tool |
|-----|------|
| 1 | Yellow marker |
| 2 | Green marker |
| 3 | Pink marker |
| 4 | Blue marker |
| 5 | Red underline |
| 6 | Blue underline |
| 7 | Red squiggle |
| 8 | Blue squiggle |
| 9 | Blue text, 11 pt (about body size in an A4 study book) |
| 0 | Red text, 7 pt (fits between printed lines) |

Blue everywhere is Apple's "Aqua" (0096FF), at the user's request.

## Verified facts (by experiment, 2026-11-25)

- PDFKit renders Highlight, Underline, Ink and FreeText, and they persist through save and reload.
- `PDFPage.characterIndex(at:)` returns `NSNotFound` (not -1) and, when not `NSNotFound`, the *nearest* character, so the hit test also checks `characterBounds`.
- Replacing the file on disk while its `PDFDocument` is open is safe. Pages still read after repeated saves.
- 2000-page text PDF: opens instantly, saves in about 1.4 s. 240 MB / 300-page image PDF: opens instantly, saves in about 2.3 s, with peak RSS around 600 MB during the save.
- `NSView.cacheDisplay` does not capture PDFKit's tiled page layers, so self-test snapshots also render the page directly.

## Testing

- `scripts/test-ui.sh <outDir>`: builds a separate app copy (.build/test/Folio.app) and runs the UI self-test with its own settings suite (`app.folio.pdf.selftest`), bookmark store and log folder, so it never touches the user's state or a running Folio.
- `swift run -c release FolioCheck [outDir] [pages]`: headless core checks plus timings. `FOLIO_HEAVY=300` adds the 240 MB test.
- UI self-test drives the real window with synthetic events and writes PNGs and `report.txt`:
  `FOLIO_SELFTEST=<outDir> FOLIO_SELFTEST_FILE=<copy-of-a-50-page-FolioCheck-large.pdf> dist/Folio.app/Contents/MacOS/Folio`
  (it uses page coordinates from FolioCheck's generated PDF). Note: synthetic clicks in pointer mode on empty space
  would enter PDFKit's mouse-tracking loop and hang, so the test avoids them.

## Known risks / limits

- PDFKit's `write(to:)` rewrites the whole file (about 5 s and full CPU for a 92 MB file). It runs in the
  background, but files in iCloud Drive are re-uploaded after each save. A future option is an
  incremental-update writer that appends only changed objects.
- PDFKit can lose some exotic PDF features when rewriting (rare). D8 backups mitigate this.
- Locked or encrypted PDFs, and read-only locations: the save fails, an alert offers "Save a Copy…", and the edits stay in memory.
- Preview "shape" stamps can't be moved or resized in Folio (see D14b).
- Toolbar palette grows with tool count (up to 25 + pointer); on narrow windows NSToolbar puts overflow in a » menu.

## Layout

```
Package.swift
Sources/FolioCore/   tools, annotation factory, persistence (testable, no UI)
Sources/Folio/       AppKit app
Sources/FolioCheck/  headless self-check: builds PDFs, annotates, saves, reloads, renders PNGs, times large files
scripts/build-app.sh builds release + assembles dist/Folio.app
```

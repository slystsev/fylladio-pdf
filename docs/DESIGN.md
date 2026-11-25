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
| D4 | Highlight and underline are *markup annotations with quad points*. On text, one quad per line. On non-text, one quad equal to the dragged rectangle. | One mechanism covers both cases. Scanned pages get a translucent box or a line under the box, which is valid PDF that every viewer renders. |
| D4a | **Curly underline is an Ink annotation** (one wavy path per line), not /Squiggly. | Verified: PDFKit does not render /Squiggly at all. Ink renders everywhere. Trade-off: other apps list it as "ink", not "squiggly". |
| D5 | Text vs rectangle is decided by **where the drag starts**: on a character → text mode, otherwise rectangle. Holding **Option** forces rectangle. | Predictable, and avoids the "highlight barely works" problem. |
| D6 | Tools are a fixed list loaded from `~/Library/Application Support/Folio/tools.json` (written with defaults on first run). Keys 1–9 and 0 select tools, Esc returns to the pointer. A tool stays active after use, like holding a pen. | "All preconfigured." The file allows customisation without a settings UI. |
| D7 | Autosave: every edit marks the document dirty, and it is written after an idle pause, on window close, on window resign-key, on app deactivate, and on quit. The write goes to a temp file and then an atomic replace. The pause is 1.5 s, or 3× the last save's duration for big files (capped at 10 s). The debounce uses GCD, not `Timer`. | Never lose edits, and never leave a half-written file. GCD fires during mouse tracking and scrolling. Verified: a 240 MB scan-like file takes about 2.3 s to save, so autosave must not interrupt active work. |
| D8 | Before the first save of a file in each session, a backup copy goes to `~/Library/Application Support/Folio/Backups/` (APFS clone, so cheap). Keeps the last 30. | Insurance against PDFKit write bugs corrupting a file. |
| D9 | Position (page, point, zoom) is stored per file path in UserDefaults and restored on open. Open windows are restored on relaunch. | "Keep position." |
| D10 | Search is async (`beginFindString`). Return/⌘G goes to the next result, ⇧Return/⇧⌘G to the previous. | Responsive on huge documents. |
| D11 | Print uses `PDFDocument.printOperation` with the standard panel (page range, PDF menu). "Print Selected Pages…" prints the pages selected in the thumbnail sidebar. | System dialog, as requested. |
| D12 | Thumbnail sidebar is hidden by default. | Saves RAM and CPU on large files. |
| D13 | Single-key tool shortcuts are handled in the PDF view's `keyDown`, not as menu key equivalents. | Menu equivalents without modifiers would swallow typing in the search field. |
| D14 | Annotations are selected and deleted in pointer mode: click selects (dashed outline), Delete removes it, double-click a text note edits it, and right-click offers delete or recolour. Full undo/redo. | Basic editing without extra modes. |
| D15 | Minimum macOS 13. | Current SDK, broad enough. |

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
| 9 | Black text |
| 0 | Red text |

## Verified facts (by experiment, 2026-11-25)

- PDFKit renders Highlight, Underline, Ink and FreeText, and they persist through save and reload.
- `PDFPage.characterIndex(at:)` returns `NSNotFound` (not -1) and, when not `NSNotFound`, the *nearest* character, so the hit test also checks `characterBounds`.
- Replacing the file on disk while its `PDFDocument` is open is safe. Pages still read after repeated saves.
- 2000-page text PDF: opens instantly, saves in about 1.4 s. 240 MB / 300-page image PDF: opens instantly, saves in about 2.3 s, with peak RSS around 600 MB during the save.
- `NSView.cacheDisplay` does not capture PDFKit's tiled page layers, so self-test snapshots also render the page directly.

## Testing

- `swift run -c release FolioCheck [outDir] [pages]`: headless core checks plus timings. `FOLIO_HEAVY=300` adds the 240 MB test.
- UI self-test drives the real window with synthetic events and writes PNGs and `report.txt`:
  `FOLIO_SELFTEST=<outDir> FOLIO_SELFTEST_FILE=<copy-of-a-50-page-FolioCheck-large.pdf> dist/Folio.app/Contents/MacOS/Folio`
  (it uses page coordinates from FolioCheck's generated PDF). Note: synthetic clicks in pointer mode on empty space
  would enter PDFKit's mouse-tracking loop and hang, so the test avoids them.

## Known risks / limits

- PDFKit's `write(to:)` rewrites the whole file. On very large files the save
  takes time and runs on the main thread, though only after 1.5 s of idle. A future
  option is an incremental-update writer that appends only changed objects.
- PDFKit can lose some exotic PDF features when rewriting (rare). D8 backups mitigate this.
- Locked or encrypted PDFs, and read-only locations: the save fails, an alert offers "Save a Copy…", and the edits stay in memory.
- Moving or resizing existing annotations is not supported in v1 (delete and redo instead).

## Layout

```
Package.swift
Sources/FolioCore/   tools, annotation factory, persistence (testable, no UI)
Sources/Folio/       AppKit app
Sources/FolioCheck/  headless self-check: builds PDFs, annotates, saves, reloads, renders PNGs, times large files
scripts/build-app.sh builds release + assembles dist/Folio.app
```

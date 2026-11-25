# Folio

A fast, lightweight native macOS PDF reader and annotator built like a pencil case:
a few pre-loaded markers and pens, each one keypress away.

## Build & run

    scripts/build-app.sh          # → dist/Folio.app (needs only Xcode Command Line Tools)
    open dist/Folio.app
    cp -R dist/Folio.app /Applications/   # optional; then "Open With → Folio" in Finder

## Use

| Key | Tool |
|-----|------|
| Esc / V | Pointer (select text, click an annotation to select it, Delete removes it, double-click edits a note) |
| 1–4 | Markers: yellow, green, pink, blue |
| 5–6 | Underline: red, blue |
| 7–8 | Curly underline: red, blue |
| 9, 0 | Text: black, red. Click, type, Return to finish (⌥/⇧Return for a new line) |

- Drag starting on text marks the text line by line. Drag starting elsewhere, or with **⌥** held, marks a rectangle (scans, images).
- Pressing the active tool's key again puts the pen down (back to the pointer).
- Right-click an annotation to delete it or switch it to another colour of the same tool.
- ⌘F search (Return / ⌘G next, ⇧Return / ⇧⌘G previous), ⌥⌘G go to page, ⌥⌘S thumbnails,
  ⌘P print (page ranges and Save as PDF in the system dialog), ⌥⌘P print pages selected in thumbnails.
- Saves automatically into the PDF. The first change to a file in each session makes a backup
  (Folio ▸ Show Backups Folder). Reopens files where you left off.
- Customise tools: Folio ▸ Edit Tools File… (`~/Library/Application Support/Folio/tools.json`), then relaunch.
  Colours are `RRGGBB` or `RRGGBBAA`.

See docs/DESIGN.md for decisions and docs/PLAN.md for status.

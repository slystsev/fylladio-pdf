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
| Q, W, E | Pens: black, red, blue (freehand) |
| 9, 0 | Text: blue (11 pt, body size), red (7 pt, fits between lines). Click, type, Return to finish (⌥/⇧Return for a new line) |

- Markers: a drag starting on text marks it line by line. A drag starting elsewhere, or with **⌥** held, marks a rectangle (scans, images).
- Underlines: a drag starting on text underlines it line by line. Elsewhere (or with ⌥) they draw from point to point; nearly horizontal lines snap flat, and ⇧ forces flat.
- Pointer: drag an annotation to move it, including onto another page; arrow keys nudge (⇧ ×10). Drag the square handles of a selected annotation to resize it (⇧ on a corner keeps proportions). Preview's shape stamps can't be edited in Folio.
- Pressing the active tool's key again puts the pen down (back to the pointer).
- Right-click an annotation to delete it or switch it to another colour of the same tool.
- ⌘F search (Return / ⌘G next, ⇧Return / ⇧⌘G previous), ⌥⌘G go to page, ⌥⌘S thumbnails,
  ⌘P print (page ranges and Save as PDF in the system dialog), ⌥⌘P print pages selected in thumbnails.
- Saves automatically into the PDF. The first change to a file in each session makes a backup
  (Folio ▸ Show Backups Folder). Reopens files where you left off.
- Customise tools: Folio ▸ Settings… (⌘,). Colour, opacity, width, font and size, name and shortcut, 1–5 tools per kind.

See docs/DESIGN.md for decisions and docs/PLAN.md for status.

## Bookmarks

The left column holds up to 4 bookmarks in page order, each with its own ribbon colour. A new file starts with one, **Current**, not yet placed: click it to put it where you are.

- Click a bookmark to go there. It's then highlighted ("p. N · with you") and **moves with you as you read**. Its ribbon hangs from the top of the page view.
- Other bookmarks show as ribbons on the edge of their pages.
- Click the **pin** next to a bookmark to move it to this page; it then moves with you.
- Going to a page number, a search result, a link or a thumbnail leaves every bookmark where it was, and the column reminds you that no bookmark moves with you. Pin one if you meant to bring it along.
- **Back** (⌘[) toggles between where you were before the last jump and where you are, e.g. Current ⇄ Answers.
- **+** adds a bookmark on this page (⌘D). Keys: ⌃1–⌃4 go to a bookmark (top to bottom), ⌃⌥1–⌃⌥4 pin it here. Right-click to rename or remove.
- Thumbnails (⌥⌘S) appear below the bookmarks. Drag the column edge to resize it.

## Saving and recovery

- Edits save automatically in the background. Big files (over 20 MB) save at most every 30 s while you edit, and always when you close the window, switch apps or quit.
- Every edit also goes straight into a small recovery file. If Folio ever closes unexpectedly, it offers your unsaved annotations back the next time you open the file.
- Backups of each file before Folio's first save in a session: Folio menu ▸ Show Backups Folder.

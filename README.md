<img src="docs/assets/icon-512.png" width="128" alt="Inkdown icon">

# Inkdown

A calm, native Markdown editor for macOS: **edit, create, view and Quick Look** `.md` files.
The look follows [Downright](https://downright.cc). The goal is that every feature just works.

**Website:** https://tapariapurv.github.io/inkdown/

![Inkdown in Document mode](docs/assets/document.jpg)

## Install

**One line.** Paste into Terminal:

```sh
curl -fsSL https://tapariapurv.github.io/inkdown/install.sh | bash
```

This downloads the [latest release](https://github.com/tapariapurv/inkdown/releases/latest), installs it into `/Applications`, turns on the Quick Look extension and opens the app. ([Read the script](docs/install.sh).)

**Or** download [`Inkdown.dmg`](https://github.com/tapariapurv/inkdown/releases/latest/download/Inkdown.dmg) and drag the app into Applications. The build isn't notarized yet, so on first launch go to **System Settings › Privacy & Security › Open Anyway**.

Requires macOS 14 Sonoma or later (Apple silicon or Intel). To uninstall, drag Inkdown to the Trash.

## Features

- **Document mode**: syntax hides while you read and reappears on the line you're editing. Headings, bold/italic, code, links, bullets (•/◦), clickable task checkboxes, quote bars, rules and table grids all render inline. An `H1`–`H6` badge marks the caret's heading.
- **Source mode**: plain monospace text with line numbers.
- **Side-by-side preview** (`⌘\`): GitHub-flavored rendering via cmark-gfm, kept in sync with the editor's scroll position.
- **Smart editing**
  - Return continues bullets, numbered lists, tasks and quotes. Return on an empty item ends the list (or outdents a nested one).
  - Tab / Shift-Tab nest and outdent list items, and numbered lists renumber themselves.
  - Tables: Tab and Shift-Tab move between cells and reformat the source, Return adds a row, and Return on an empty row leaves the table.
  - Backspace right after a list marker or heading prefix removes it.
  - Pasting a URL over selected text makes a link. ⌘-click opens a link.
- **Files**: a sidebar lists every Markdown file in the document's folder (`⌘P`, fuzzy filter, keyboard navigation, a **+** button for new files). An outline (`⇧⌘O`) jumps to any heading.
- **Quick Look extension**: press Space on a `.md` file in Finder to see it rendered.
- **Plain files only**: no database, no library, no sidecar files. It uses the macOS document architecture, so you get autosave, Versions, Rename/Move from the title bar, and live reload when another app edits the file.
- Export to HTML or PDF, Print, Reveal in Finder, light/dark/system theme, and font size controls (`⌘=` / `⌘-`).

## Keyboard shortcuts

| Action | Keys | Action | Keys |
| --- | --- | --- | --- |
| Bold / Italic | ⌘B / ⌘I | Heading 1–6 / Body | ⌘1–⌘6 / ⌘0 |
| Strikethrough | ⇧⌘X | Bulleted / Numbered list | ⇧⌘8 / ⇧⌘7 |
| Inline code | ⌃` | Task list / Toggle done | ⇧⌘9 / ⌘L |
| Link | ⌘K | Quote / Code block | ⌥⌘Q / ⌥⌘C |
| Insert table | ⌥⌘T | Indent / Outdent | ⌘] / ⌘[ |
| Move line up / down | ⌃⌘↑ / ⌃⌘↓ | Duplicate line | ⇧⌘D |
| Document / Source | ⌃⌘1 / ⌃⌘2 | Side-by-side preview | ⌘\ |
| Go to file / heading | ⌘P / ⇧⌘O | Find / Replace | ⌘F / ⌥⌘F |
| Toggle sidebar | ⌃⌘S | Reveal in Finder | ⌥⌘R |
| Export PDF / HTML | File menu | Print | ⌥⌘P |

All standard macOS text-editing shortcuts (word and line navigation, Emacs bindings, undo/redo) work too.

## Build

Maintainers can cut a release (it builds, packages a DMG and zip, tags, and publishes with notes from `release-notes/vX.Y.Z.md`) with:

```sh
scripts/release.sh 1.0.1
```

To build from source yourself:

Requires macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen                                   # generates Inkdown.xcodeproj from project.yml
xcodebuild -scheme Inkdown -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/Inkdown.app /Applications/
```

Set `DEVELOPMENT_TEAM` in `project.yml` to your own team ID to sign with your certificate.

### Quick Look

The extension registers when the app is first launched from `/Applications`. If another app (for example Downright) also previews Markdown, macOS uses whichever extension is enabled. Pick Inkdown in **System Settings › General › Login Items & Extensions › Quick Look**, or from the terminal:

```sh
pluginkit -e use -i com.purvt.InkdownQuickLook
qlmanage -r
```

## Mac App Store

Inkdown runs in the App Sandbox and includes a privacy manifest (no data collected). The App Store listing (metadata, keywords, captioned screenshots, review notes) is in [`appstore/`](appstore/), along with [`scripts/appstore.sh`](scripts/appstore.sh) for archiving and uploading. Submitting requires a paid Apple Developer Program membership; see [appstore/README.md](appstore/README.md).

## Tests

The editing rules (lists, renumbering, tables, toggles, code fences) are pure functions with a runnable self-check:

```sh
swiftc App/MarkdownLogic.swift Tests/main.swift -o /tmp/mdtest && /tmp/mdtest
```

## Project layout

| Path | What |
| --- | --- |
| `App/MarkdownLogic.swift` | Pure line-level rules: list continuation/renumbering, toggles, GFM table formatting and navigation, fence detection |
| `App/Styling.swift` | Live styler (Document/Source) and the layout manager that hides syntax, swaps bullets, and draws checkboxes, grids, quote bars and margins |
| `App/Editor.swift` | `NSTextView` subclass (smart keys, format commands) and the editor controller |
| `App/Window.swift` | `NSDocument`, window/toolbar, preview (`WKWebView`), export and print |
| `App/Sidebar.swift` | SwiftUI files & outline sidebar |
| `Shared/Renderer.swift` | cmark-gfm → HTML plus CSS, shared by the preview and Quick Look |
| `QuickLook/` | Data-based Quick Look preview extension |
| `docs/` | Website (GitHub Pages) |

## License

MIT

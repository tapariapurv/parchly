#if DEBUG
import AppKit
import WebKit

/// Keeps the self-test out of the user's Open Recent list (it shares the app's container).
final class NoRecentsController: NSDocumentController {
    override func noteNewRecentDocument(_ document: NSDocument) {}
    override func noteNewRecentDocumentURL(_ url: URL) {}
}

/// `Parchly --selftest` drives the real app stack (documents, windows, preview, sidebar, Home) in-process
/// without activating the app, then exits non-zero on any failure. Run by scripts/test.sh.
enum SelfTest {
    static var failures = 0
    static func check(_ ok: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
        if !ok() { failures += 1; print("FAIL selftest line \(line): \(msg)") }
    }
    static func spin(_ s: Double = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    static func wait(_ s: Double = 3, until cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(s)
        while !cond(), Date() < end { spin(0.02) }
        return cond()
    }
    static func js(_ web: WKWebView, _ script: String) -> String {
        var out: String?
        web.evaluateJavaScript(script, in: nil, in: .defaultClient) { r in out = (try? r.get()).map { "\($0)" } ?? "" }
        _ = wait { out != nil }
        return out ?? ""
    }

    /// Menu commands that open panels, other apps or quit; everything else is fired at a live document.
    static let skipped: Set<String> = ["orderFrontStandardAboutPanel:", "checkForUpdates:", "showSettings:", "hide:", "hideOtherApplications:",
        "unhideAllApplications:", "terminate:", "clearRecentDocuments:", "newDocument:", "openDocument:", "performClose:", "save:", "saveDocument:",
        "duplicate:", "duplicateDocument:", "renameDocument:", "moveDocument:", "rename:", "move:", "revertToSaved:", "revertDocumentToSaved:", "revealInFinder:", "exportHTML:", "exportPDF:", "printMarkdown:", "performMiniaturize:",
        "performZoom:", "arrangeInFront:", "showGuide:", "showHome:", "showGuessPanel:", "checkSpelling:", "toggleContinuousSpellChecking:",
        "cut:", "copy:", "paste:", "delete:", "undo:", "redo:", "performFindPanelAction:", "submenuAction:"]

    static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { $0.submenu.map(menuItems) ?? ($0.action == nil ? [] : [$0]) }
    }

    static func run(menu: NSMenu) -> Never {
        _ = NoRecentsController()
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parchly-selftest-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = dir.appendingPathComponent("Plan.md")
        try! Data("# Plan\n\n## Today\n\n- [ ] buy milk\n\nSee [[Other]] and [today](#today).\n".utf8).write(to: note)
        try! Data("# Other\n".utf8).write(to: dir.appendingPathComponent("Other.md"))

        // Open a file: text, outline, sidebar folder listing.
        var doc: Document?
        NSDocumentController.shared.openDocument(withContentsOf: note, display: true) { d, _, _ in doc = d as? Document }
        check(wait { doc != nil }, "document opens")
        guard let doc, let wc = doc.controller else { finish() }
        let ed = wc.editor, tv = ed.textView!
        check(ed.text.hasPrefix("# Plan"), "editor shows the file")
        check(!(HomeWindowController.shared.window?.isVisible ?? false), "Home hidden while a document is open")
        check(wait { wc.sidebar.files.map(\.lastPathComponent) == ["Other.md", "Plan.md"] }, "sidebar lists folder: \(wc.sidebar.files)")
        check(wait { wc.sidebar.headings.map(\.title) == ["Plan", "Today"] }, "outline: \(wc.sidebar.headings)")
        check(wc.sidebar.visibleFiles.first?.lastPathComponent == "Other.md" || { wc.sidebar.query = "oth"; return wc.sidebar.visibleFiles.first?.lastPathComponent == "Other.md" }(), "quick open filter")
        wc.sidebar.query = "tod"
        check(wc.sidebar.visibleHeadings.map(\.title) == ["Today"], "heading filter")
        wc.sidebar.query = ""

        // Typing marks the document edited, undo restores, save writes to disk.
        tv.setSelectedRange(NSRange(location: (ed.text as NSString).length, length: 0))
        for ch in "\n[] call mum" { tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        check(ed.text.hasSuffix("\n- [ ] call mum"), "task shortcut in a real document: \(ed.text.debugDescription)")
        check(wait { doc.isDocumentEdited }, "typing marks edited")
        var didSave = false
        doc.save(to: note, ofType: doc.fileType!, for: .saveOperation) { _ in didSave = true }
        check(wait { didSave } && (try? String(contentsOf: note, encoding: .utf8))?.hasSuffix("- [ ] call mum") == true, "save writes the file")

        // External change reloads.
        try! Data("# Changed\n".utf8).write(to: note)
        try? doc.revert(toContentsOf: note, ofType: doc.fileType!)
        check(wait { ed.text == "# Changed\n" }, "revert reloads from disk: \(ed.text.debugDescription)")
        ed.setText("# Plan\n\n## Today\n\nx\n")

        // Anchor link jumps to the heading; wiki link creates and opens a missing note.
        for (source, want) in [(false, 11), (true, 8)] {   // Document mode lands after the hidden "## "
            source ? wc.showSource(nil) : wc.showDocument(nil)
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.openLink("#today")
            check(tv.selectedRange().location == want, "anchor jump (source \(source)): \(tv.selectedRange())")
        }
        tv.openLink("wiki:Brand New")
        check(wait { FileManager.default.fileExists(atPath: dir.appendingPathComponent("Brand New.md").path) }, "wiki link creates the note")
        check(wait { NSDocumentController.shared.documents.contains { $0.fileURL?.lastPathComponent == "Brand New.md" } }, "wiki link opens the note")

        // Sidebar "+" makes Untitled.md in the folder and opens it; pasted images are saved next to the note.
        wc.sidebar.newFile()
        check(wait { NSDocumentController.shared.documents.contains { $0.fileURL?.lastPathComponent == "Untitled.md" } }, "sidebar + creates and opens Untitled.md")
        check(wait { wc.sidebar.files.contains { $0.lastPathComponent == "Untitled.md" } }, "new file appears in the sidebar")
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
        let saved = tv.saveImage(png)
        check(saved.map { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.removingPercentEncoding!).path) } == true, "pasted image saved beside the note: \(saved ?? "nil")")

        // Find bar opens.
        wc.find(nil)
        check(ed.scrollView.isFindBarVisible, "find bar shows")
        ed.scrollView.isFindBarVisible = false

        // Source / Document modes.
        wc.showSource(nil); check(!ed.styler.wysiwyg, "source mode")
        wc.showDocument(nil); check(ed.styler.wysiwyg, "document mode")

        // Preview renders tasks, math and code once shown; hidden preview stays cheap.
        let wasShown = UserDefaults.standard.bool(forKey: "preview")
        if !wasShown { wc.togglePreview(nil) }
        ed.setText("- [x] done\n\n$a^2$\n\n```js\nlet x\n```\n")
        ed.onChange()
        let html = { js(wc.preview.web, "document.getElementById('c').innerHTML") }
        check(wait(5) { html().contains("checkbox") && html().contains("katex") && html().contains("tok-kw") }, "preview renders tasks, math, code: \(html().prefix(300))")
        wc.togglePreview(nil)
        if wasShown { wc.togglePreview(nil) }

        // Themes and text size apply without crashing, then restore.
        let theme = Theme.id, size = Settings.fontSize
        for t in Theme.choices { Theme.id = t.id; spin(0.01) }
        Theme.id = theme
        wc.biggerFont(nil); check(Settings.fontSize == size + 1, "bigger text"); wc.actualSizeFont(nil); Settings.fontSize = size

        // Settings reach the open editor, then restore.
        let prefs = (Settings.formatBar, Settings.lineNumbers, Settings.spellCheck)
        let lm = tv.layoutManager as? MDLayoutManager
        Settings.formatBar = false; check(ed.formatBar.isHidden, "hide formatting bar")
        Settings.formatBar = true; check(!ed.formatBar.isHidden, "show formatting bar")
        Settings.spellCheck = !prefs.2; check(tv.isContinuousSpellCheckingEnabled == !prefs.2, "spelling setting")
        wc.showSource(nil); Settings.lineNumbers = true; check(lm?.lineNumbers == true, "line numbers in Source mode")
        wc.showDocument(nil); check(lm?.lineNumbers == false, "no line numbers in Document mode")
        Settings.fontSize = 20; check(ed.styler.fontSize == 20 && (tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { $0.pointSize >= 20 } == true, "text size applies")
        (Settings.formatBar, Settings.lineNumbers, Settings.spellCheck) = prefs

        // Every formatting-bar button and every menu command: works on a selection and undoes exactly.
        wc.showDocument(nil)
        let original = "alpha beta\ngamma delta\n"
        func fire(_ name: String, _ perform: () -> Void) {
            ed.setText(original); tv.setSelectedRange(NSRange(location: 6, length: 4)); spin()
            perform(); spin()
            check(tv.selectedRange().upperBound <= (ed.text as NSString).length, "\(name): caret in bounds")
            if ed.text != original {
                doc.undoManager?.undo(); spin()
                check(ed.text == original, "\(name) undoes: \(ed.text.debugDescription)")
            }
        }
        var buttons: [NSButton] = []
        func collect(_ v: NSView) { if let b = v as? NSButton { buttons.append(b) }; v.subviews.forEach(collect) }
        collect(ed.formatBar)
        check(buttons.count == 13, "format bar has 13 buttons: \(buttons.count)")
        for b in buttons where b.target is MarkdownTextView {
            fire(b.toolTip ?? "button") { b.performClick(nil) }
        }
        let changes = buttons.filter { b in b.target is MarkdownTextView }.map { b -> Bool in
            ed.setText(original); tv.setSelectedRange(NSRange(location: 6, length: 4)); b.performClick(nil); return ed.text != original
        }
        check(!changes.contains(false), "every format button edits the text: \(changes)")
        let items = menuItems(menu)
        var fired = 0
        for item in items {
            // Window-list entries carry their own target.
            guard let action = item.action, item.target == nil, !skipped.contains(NSStringFromSelector(action)) else { continue }
            let split = wc.window?.contentViewController
            let target: AnyObject? = tv.responds(to: action) ? tv : wc.responds(to: action) ? wc : split?.responds(to: action) == true ? split : nil
            guard let target else { check(false, "no target for menu \(item.title)"); continue }
            fired += 1
            fire("menu \(item.title)") {
                NSApp.sendAction(action, to: target, from: item)
                if target === wc || target === split, item.title != "Bigger", item.title != "Smaller" { spin(); NSApp.sendAction(action, to: target, from: item) }   // toggles back
            }
        }
        Settings.fontSize = size
        check(fired > 35, "fired \(fired) menu commands")
        wc.showDocument(nil)
        if UserDefaults.standard.bool(forKey: "preview") != wasShown { wc.togglePreview(nil) }

        // Closing every document brings Home back; opening one hides it.
        for d in NSDocumentController.shared.documents { d.updateChangeCount(.changeCleared); d.close() }
        check(wait { HomeWindowController.shared.window?.isVisible == true }, "Home shows after the last document closes")
        let pb = NSPasteboard.general, clip = pb.string(forType: .string)
        pb.clearContents(); pb.setString("# From clipboard", forType: .string)
        HomeModel().newFromClipboard()
        let fresh = NSDocumentController.shared.documents.first as? Document
        check(fresh?.controller?.editor.text == "# From clipboard" && wait { fresh?.isDocumentEdited == true }, "new from clipboard is an edited document")
        check(wait { HomeWindowController.shared.window?.isVisible == false }, "Home hides when a document opens")
        pb.clearContents(); if let clip { pb.setString(clip, forType: .string) }
        fresh?.updateChangeCount(.changeCleared); fresh?.close()
        finish()
    }

    static func finish() -> Never {
        print(failures == 0 ? "selftest: all checks passed" : "selftest: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif

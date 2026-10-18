import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Sparkle: checks the appcast daily and installs signed updates (works inside the sandbox via its installer service).
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var settings = SettingsWindowController(updater: updater.updater)

    @objc func showSettings(_ sender: Any?) { settings.showWindow(nil); settings.window?.makeKeyAndOrderFront(nil) }
    @objc func checkForUpdates(_ sender: Any?) { updater.checkForUpdates(sender) }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = buildMenu()
        Theme.apply()
        FolderAccess.restore()
    }

    private var firstLaunch: Bool { !UserDefaults.standard.bool(forKey: "launchedBefore") }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !firstLaunch }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if firstLaunch {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            if NSDocumentController.shared.documents.isEmpty { showGuide(nil) }
        }
    }

    /// Opens the guide as a fresh untitled document (closing it never asks to save).
    @objc func showGuide(_ sender: Any?) {
        guard let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? Document else { return }
        doc.controller?.editor.setText(Guide.text)
    }
}

private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
    i.keyEquivalentModifierMask = mods
    i.tag = tag
    return i
}

private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let m = NSMenu(title: title)
    items.forEach(m.addItem)
    let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    top.submenu = m
    return top
}

private func key(_ scalar: Int) -> String { String(Character(UnicodeScalar(scalar)!)) }

private func buildMenu() -> NSMenu {
    let sep = { NSMenuItem.separator() }
    let main = NSMenu()
    let tv = MarkdownTextView.self, wc = WindowController.self

    main.addItem(menu("Parchly", [
        item("About Parchly", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
        item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))),
        sep(),
        item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
        sep(),
        item("Hide Parchly", #selector(NSApplication.hide(_:)), "h"),
        item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
        item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
        sep(),
        item("Quit Parchly", #selector(NSApplication.terminate(_:)), "q"),
    ]))

    let recent = menu("Open Recent", [item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))])
    main.addItem(menu("File", [
        item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
        item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
        recent,
        item("Quick Open…", #selector(wc.quickOpen(_:)), "p"),
        sep(),
        item("Close", #selector(NSWindow.performClose(_:)), "w"),
        item("Save…", #selector(NSDocument.save(_:)), "s"),
        item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]),
        item("Rename…", #selector(NSDocument.rename(_:))),
        item("Move To…", #selector(NSDocument.move(_:))),
        item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))),
        item("Reveal in Finder", #selector(wc.revealInFinder(_:)), "r", [.command, .option]),
        sep(),
        item("Export as HTML…", #selector(wc.exportHTML(_:))),
        item("Export as PDF…", #selector(wc.exportPDF(_:))),
        item("Print…", #selector(wc.printMarkdown(_:)), "p", [.command, .option]),
    ]))

    main.addItem(menu("Edit", [
        item("Undo", Selector(("undo:")), "z"),
        item("Redo", Selector(("redo:")), "z", [.command, .shift]),
        sep(),
        item("Cut", #selector(NSText.cut(_:)), "x"),
        item("Copy", #selector(NSText.copy(_:)), "c"),
        item("Paste", #selector(NSText.paste(_:)), "v"),
        item("Delete", #selector(NSText.delete(_:))),
        item("Select All", #selector(NSText.selectAll(_:)), "a"),
        sep(),
        menu("Find", [
            item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: 1),
            item("Find and Replace…", #selector(NSTextView.performFindPanelAction(_:)), "f", [.command, .option], tag: 12),
            item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: 2),
            item("Find Previous", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift], tag: 3),
            item("Use Selection for Find", #selector(NSTextView.performFindPanelAction(_:)), "e", tag: 7),
            item("Jump to Selection", #selector(NSTextView.centerSelectionInVisibleArea(_:)), "j"),
        ]),
        menu("Spelling", [
            item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"),
            item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"),
            item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))),
        ]),
        sep(),
        item("Move Line Up", #selector(tv.moveLineUp(_:)), key(NSUpArrowFunctionKey), [.command, .control]),
        item("Move Line Down", #selector(tv.moveLineDown(_:)), key(NSDownArrowFunctionKey), [.command, .control]),
        item("Duplicate Line", #selector(tv.duplicateLine(_:)), "d", [.command, .shift]),
    ]))

    var headings = (1...6).map { item("Heading \($0)", #selector(tv.setHeading(_:)), "\($0)", tag: $0) }
    headings.append(item("Body Text", #selector(tv.setHeading(_:)), "0", tag: 0))
    main.addItem(menu("Format", [
        item("Bold", #selector(tv.toggleBold(_:)), "b"),
        item("Italic", #selector(tv.toggleItalic(_:)), "i"),
        item("Strikethrough", #selector(tv.toggleStrike(_:)), "x", [.command, .shift]),
        item("Inline Code", #selector(tv.toggleInlineCode(_:)), "`", .control),
        item("Link", #selector(tv.insertLink(_:)), "k"),
        sep(),
    ] + headings + [
        sep(),
        item("Bulleted List", #selector(tv.toggleBullets(_:)), "8", [.command, .shift]),
        item("Numbered List", #selector(tv.toggleNumbers(_:)), "7", [.command, .shift]),
        item("Task List", #selector(tv.toggleTasks(_:)), "9", [.command, .shift]),
        item("Toggle Task Done", #selector(tv.toggleTaskDone(_:)), "l"),
        item("Quote", #selector(tv.toggleQuote(_:)), "q", [.command, .option]),
        item("Code Block", #selector(tv.insertCodeBlock(_:)), "c", [.command, .option]),
        item("Table", #selector(tv.insertTable(_:)), "t", [.command, .option]),
        sep(),
        item("Indent", #selector(tv.indentLines(_:)), "]"),
        item("Outdent", #selector(tv.outdentLines(_:)), "["),
    ]))

    main.addItem(menu("View", [
        item("Document", #selector(wc.showDocument(_:)), "1", [.command, .control]),
        item("Source", #selector(wc.showSource(_:)), "2", [.command, .control]),
        item("Toggle Source", #selector(wc.toggleSource(_:)), "e", [.command, .shift]),
        item("Side-by-Side Preview", #selector(wc.togglePreview(_:)), "\\"),
        item("Formatting Bar", #selector(wc.toggleFormatBar(_:)), "b", [.command, .shift]),
        sep(),
        item("Toggle Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]),
        item("Go to File…", #selector(wc.quickOpen(_:)), "p"),
        item("Go to Heading…", #selector(wc.goToHeading(_:)), "o", [.command, .shift]),
        sep(),
        item("Bigger", #selector(wc.biggerFont(_:)), "="),
        item("Smaller", #selector(wc.smallerFont(_:)), "-"),
        item("Actual Size", #selector(wc.actualSizeFont(_:)), "0", [.command, .option]),
        sep(),
    ]))

    let window = menu("Window", [
        item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        item("Zoom", #selector(NSWindow.performZoom(_:))),
        sep(),
        item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
    ])
    main.addItem(window)
    NSApp.windowsMenu = window.submenu
    let help = menu("Help", [item("Markdown Guide", #selector(AppDelegate.showGuide(_:)))])
    main.addItem(help)
    NSApp.helpMenu = help.submenu
    return main
}

// Test hook: `Parchly --render-html < file.md` prints the preview HTML and exits (stdin works inside the sandbox).
if CommandLine.arguments.contains("--render-html") {
    print(Renderer.html(String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self))); exit(0)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

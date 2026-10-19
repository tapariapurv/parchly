import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

final class Document: NSDocument {
    var text = ""
    var controller: WindowController? { windowControllers.first as? WindowController }

    override class var autosavesInPlace: Bool { true }
    override func makeWindowControllers() { addWindowController(WindowController()) }

    override func data(ofType typeName: String) throws -> Data { Data((controller?.editor.text ?? text).utf8) }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = s
        controller?.editor.setText(s)   // external change / revert
    }

    override var fileURL: URL? {
        didSet { DispatchQueue.main.async { self.controller?.urlChanged() } }
    }
}

// MARK: - Preview

final class PreviewController: NSViewController, WKNavigationDelegate {
    private(set) var web: WKWebView!
    var openLink: (URL) -> Void = { _ in }
    private var loaded = false
    private var html = ""
    private var base: URL?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.setURLSchemeHandler(LocalFiles(), forURLScheme: LocalFiles.scheme)
        // KaTeX + Mermaid run as app scripts (page JavaScript stays disabled); window.__render re-typesets after each edit.
        for name in ["katex.min.js", "mermaid.min.js"] {
            if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "vendor"), let js = try? String(contentsOf: url, encoding: .utf8) {
                config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
            }
        }
        config.userContentController.addUserScript(WKUserScript(source: Self.renderScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 600), configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")   // no white flash before CSS paints
        web.underPageBackgroundColor = .paper
        view = web
        reload()
    }


    func setBase(_ url: URL?) {
        guard url != base else { return }
        base = url
        if isViewLoaded { reload() }
    }

    /// Page based in the document's folder (via LocalFiles) so relative images resolve; content is then
    /// swapped in place to keep scroll position.
    private func reload() {
        loaded = false
        let page = Renderer.page("").replacingOccurrences(of: "<article id=\"c\"></article>", with: "<article id=\"c\">\(html)</article>")
            .replacingOccurrences(of: "</head>", with: "<style>\(Self.katexCSS)</style><style id=\"theme\">\(Self.themeCSS)</style></head>")
        web.loadHTMLString(page, baseURL: base.map(LocalFiles.url) ?? URL(string: "\(LocalFiles.scheme):///")!)
    }

    func update(_ markdown: String, then: (() -> Void)? = nil) {
        html = Renderer.html(markdown)
        guard loaded else { then?(); return }
        web.evaluateJavaScript("document.getElementById('c').innerHTML = \(Self.js(html)); window.__render && __render()", in: nil, in: .defaultClient) { _ in then?() }
    }

    static let renderScript = """
    window.__render = function () {
      if (window.katex) document.querySelectorAll('.math').forEach(function (el) {
        try { katex.render(el.textContent, el, { displayMode: el.classList.contains('math-display'), throwOnError: false }); } catch (e) {}
      });
      if (window.mermaid) {
        var dark = matchMedia('(prefers-color-scheme: dark)').matches || /color-scheme:dark/.test(document.getElementById('theme').textContent);
        mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'neutral', securityLevel: 'strict' });
        mermaid.run({ querySelector: 'pre.mermaid' }).catch(function () {});
      }
    };
    __render();
    """

    /// KaTeX's stylesheet with its fonts inlined as data URIs (no file or network access needed).
    static let katexCSS: String = {
        guard let dir = Bundle.main.url(forResource: "vendor", withExtension: nil),
              var css = try? String(contentsOf: dir.appendingPathComponent("katex.min.css"), encoding: .utf8) else { return "" }
        css = css.replacingOccurrences(of: #"url\((fonts/[^)]+\.woff2)\) format\("woff2"\)"#, with: "url(__$1__) format(\"woff2\")", options: .regularExpression)
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("fonts").path)) ?? [] {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("fonts/\(f)")) else { continue }
            css = css.replacingOccurrences(of: "__fonts/\(f)__", with: "data:font/woff2;base64,\(data.base64EncodedString())")
        }
        return css.replacingOccurrences(of: #",url\(fonts/[^)]+\) format\("(woff|truetype)"\)"#, with: "", options: .regularExpression)
    }()

    /// Fixed themes override the page's light/dark palette; Paper (Auto) uses the built-in CSS.
    static var themeCSS: String { Theme.all.contains { $0.id == Theme.id } ? Theme.current.css : "" }

    func applyTheme() {
        guard loaded else { return }
        web.evaluateJavaScript("document.getElementById('theme').textContent = \(Self.js(Self.themeCSS))", in: nil, in: .defaultClient) { _ in }
    }

    func scroll(to fraction: CGFloat) {
        guard loaded else { return }
        web.evaluateJavaScript("window.scrollTo(0, \(fraction) * (document.documentElement.scrollHeight - window.innerHeight))", in: nil, in: .defaultClient) { _ in }
    }

    static func js(_ s: String) -> String { String(data: try! JSONEncoder().encode(s), encoding: .utf8)! }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        web.evaluateJavaScript("document.getElementById('c').innerHTML = \(Self.js(html)); window.__render && __render()", in: nil, in: .defaultClient) { _ in }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        guard url.scheme == LocalFiles.scheme else { return openLink(url) }
        let file = URL(fileURLWithPath: url.path)
        if let fragment = url.fragment, file.standardizedFileURL.path == base?.standardizedFileURL.path {
            web.evaluateJavaScript("document.getElementById(\(Self.js(fragment)))?.scrollIntoView()", in: nil, in: .defaultClient) { _ in }
        } else {
            openLink(file)
        }
    }

    func printOperation(_ info: NSPrintInfo) -> NSPrintOperation {
        let op = web.printOperation(with: info)
        op.view?.frame = NSRect(x: 0, y: 0, width: info.paperSize.width, height: info.paperSize.height)
        return op
    }
}

/// Serves local files (images next to the document) to the preview from the app process, which holds
/// the sandbox permission for the document and any granted folders.
final class LocalFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "parchly-file"
    static func url(_ dir: URL) -> URL { URL(string: "\(scheme)://" + (dir.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "") + "/")! }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let data = try? Data(contentsOf: URL(fileURLWithPath: url.path)) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - Window

final class WindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let editor = EditorController()
    let preview = PreviewController()
    let sidebar = SidebarModel()
    private let split = NSSplitViewController()
    private var sidebarItem: NSSplitViewItem!
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem!
    private let modeControl = ModeSwitch()
    private var source = UserDefaults.standard.bool(forKey: "source")
    private var showsPreview = UserDefaults.standard.bool(forKey: "preview")
    private var renderWork: DispatchWorkItem?
    private static let modeItem = NSToolbarItem.Identifier("mode")
    private static let previewItem = NSToolbarItem.Identifier("preview")
    private static let searchItem = NSToolbarItem.Identifier("search")
    private static let moreItem = NSToolbarItem.Identifier("more")
    private static let formatItem = NSToolbarItem.Identifier("format")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "ParchlyDocument"
        window.minSize = NSSize(width: 520, height: 320)
        window.backgroundColor = .titleBand
        window.titlebarSeparatorStyle = .shadow

        editor.loadViewIfNeeded()
        preview.loadViewIfNeeded()
        sidebarItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SidebarView(model: sidebar)))
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 380
        sidebarItem.isCollapsed = !UserDefaults.standard.bool(forKey: "sidebarShown")
        editorItem = NSSplitViewItem(viewController: editor)
        previewItem = NSSplitViewItem(viewController: preview)
        for item in [editorItem!, previewItem!] { item.canCollapse = true; item.minimumThickness = 260 }
        split.splitViewItems = [sidebarItem, editorItem, previewItem]
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1120, height: 760))
        if !window.setFrameUsingName("ParchlyWindow") { window.center() }

        let toolbar = NSToolbar(identifier: "ParchlyToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [Self.modeItem]
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        editor.onChange = { [weak self] in self?.scheduleRender() }
        editor.onScroll = { [weak self] f in if self?.showsPreview == true { self?.preview.scroll(to: f) } }
        editor.textView.openLink = { [weak self] in self?.open(link: $0) }
        editor.textView.fileLink = { [weak self] url in
            let path: String
            if let root = self?.sidebar.root?.standardizedFileURL.path, url.standardizedFileURL.path.hasPrefix(root + "/") {
                path = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
            } else { path = url.path }
            return path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        }
        editor.textView.saveImage = { [weak self] data in
            guard let self, let root = sidebar.root else { return nil }
            guard FolderAccess.canRead(root) else { grantFolderAccess(); return nil }   // paste again once allowed
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let name = "Pasted Image \(f.string(from: Date())).png"
            guard (try? data.write(to: root.appendingPathComponent(name), options: .withoutOverwriting)) != nil else { return nil }
            return name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        }
        preview.openLink = { [weak self] in self?.open(url: $0) }
        sidebar.open = { [weak self] in self?.open(url: $0) }
        sidebar.jump = { [weak self] in self?.editor.jump(to: $0) }
        editor.onOutline = { [weak self] in self?.toggleOutline() }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.changed, object: nil)
        modeControl.onChange = { [weak self] in self?.setSource($0 == 1) }
        sidebar.newFile = { [weak self] in self?.newFileInFolder() }
        sidebar.grant = { [weak self] in self?.grantFolderAccess() }
        sidebar.done = { [weak self] in self?.focusContent() }
        editor.setWysiwyg(!source)
        applyLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var document: AnyObject? {
        didSet {
            guard let doc = document as? Document else { return }
            editor.undoSource = doc
            editor.setText(doc.text)
            render()
            urlChanged()
            DispatchQueue.main.async { self.focusContent() }
        }
    }

    func urlChanged() {
        let url = (document as? Document)?.fileURL
        sidebar.current = url
        let root = url?.deletingLastPathComponent()
        window?.subtitle = root?.lastPathComponent ?? ""
        preview.setBase(root)
        if editor.styler.baseURL != root { editor.styler.baseURL = root; editor.textView.textStorage.map(editor.styler.restyleAll) }
        if sidebar.root != root { sidebar.root = root; sidebar.reload() }
    }

    // MARK: Rendering

    private func scheduleRender() {
        renderWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.render() }
        renderWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
    }

    private func render(then: (() -> Void)? = nil) {
        renderWork?.cancel()
        let text = editor.text
        preview.update(text, then: then)
        sidebar.headings = MD.headings(text as NSString, code: editor.styler.code)
    }

    // MARK: Modes

    private func applyLayout() {
        previewItem.isCollapsed = !showsPreview
        modeControl.selected = source ? 1 : 0
        if showsPreview {
            split.view.layoutSubtreeIfNeeded()
            let left = sidebarItem.isCollapsed ? 0 : sidebarItem.viewController.view.frame.maxX + split.splitView.dividerThickness
            split.splitView.setPosition((left + (split.splitView.bounds.width - left) / 2).rounded(), ofDividerAt: 1)
        }
    }

    private func setSource(_ on: Bool) {
        source = on
        UserDefaults.standard.set(on, forKey: "source")
        editor.setWysiwyg(!on)
        applyLayout()
        focusContent()
    }

    private func focusContent() { window?.makeFirstResponder(editor.textView) }

    @objc func showDocument(_ sender: Any?) { setSource(false) }
    @objc func showSource(_ sender: Any?) { setSource(true) }
    @objc func toggleSource(_ sender: Any?) { setSource(!source) }
    private func toggleOutline() {
        if sidebarItem.isCollapsed { reveal(.outline) } else { sidebarItem.isCollapsed = true; focusContent() }
    }

    @objc func revealInFinder(_ sender: Any?) {
        if let url = (document as? Document)?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc func toggleFormatBar(_ sender: Any?) { Settings.formatBar.toggle() }

    @objc func setTheme(_ sender: NSMenuItem) { Theme.id = Theme.choices[sender.tag].id }

    @objc private func themeChanged() {
        window?.backgroundColor = .titleBand
        editor.textView.needsDisplay = true
        editor.view.subviews.forEach { $0.needsDisplay = true }
        modeControl.needsDisplay = true
        preview.applyTheme()
    }
    @objc func togglePreview(_ sender: Any?) {
        showsPreview.toggle()
        UserDefaults.standard.set(showsPreview, forKey: "preview")
        if showsPreview { render() }
        applyLayout()
    }
    @objc func find(_ sender: Any?) {
        focusContent()
        let item = NSMenuItem(); item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        editor.textView.performFindPanelAction(item)
    }

    @objc func quickOpen(_ sender: Any?) { reveal(.files) }
    @objc func goToHeading(_ sender: Any?) { reveal(.outline) }

    private func reveal(_ tab: SidebarModel.Tab) {
        sidebarItem.isCollapsed = false
        sidebar.tab = tab
        sidebar.query = ""
        sidebar.focusTick += 1
    }

    @objc func biggerFont(_ sender: Any?) { Settings.fontSize += 1 }
    @objc func smallerFont(_ sender: Any?) { Settings.fontSize -= 1 }
    @objc func actualSizeFont(_ sender: Any?) { Settings.fontSize = 16 }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showDocument(_:)): item.state = source ? .off : .on
        case #selector(showSource(_:)): item.state = source ? .on : .off
        case #selector(togglePreview(_:)): item.state = showsPreview ? .on : .off
        case #selector(toggleFormatBar(_:)): item.state = Settings.formatBar ? .on : .off
        case #selector(setTheme(_:)): item.state = Theme.id == Theme.choices[item.tag].id ? .on : .off
        case #selector(revealInFinder(_:)): return (document as? Document)?.fileURL != nil
        default: break
        }
        return true
    }

    // MARK: Files & links

    /// Follows a link from the editor: URLs, relative files, `#heading` anchors and `[[wiki]]` cross-references.
    private func open(link: String) {
        var link = link, isWiki = false
        if link.hasPrefix("wiki:") { link = Renderer.wikiHref(String(link.dropFirst(5))); isWiki = true }
        if let url = URL(string: link), url.scheme != nil { return open(url: url) }
        let parts = link.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let path = parts[0].removingPercentEncoding ?? parts[0]
        if path.isEmpty, parts.count > 1 { return jump(toAnchor: parts[1]) }
        guard let root = sidebar.root, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
        if isWiki, FolderAccess.canRead(root), !FileManager.default.fileExists(atPath: url.path) {
            // A wiki link to a note that doesn't exist yet creates it, like Bear and Obsidian.
            try? Data("# \(url.deletingPathExtension().lastPathComponent)\n\n".utf8).write(to: url, options: .withoutOverwriting)
            sidebar.reload()
        }
        open(url: url)
    }

    private func jump(toAnchor anchor: String) {
        let text = editor.text as NSString
        if let h = MD.headings(text, code: editor.styler.code).first(where: { Renderer.slug($0.title) == anchor.lowercased() }) {
            editor.jump(to: h.location)
        }
    }

    /// Asks once for a folder (App Sandbox), then remembers it across launches.
    private func grantFolderAccess(then: (() -> Void)? = nil) {
        guard let window, let root = sidebar.root else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        panel.prompt = "Allow Access"
        panel.message = "Parchly needs access to this folder to list its Markdown files, open links and show images."
        panel.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let url = panel.url, let self else { return }
            FolderAccess.add(url)
            sidebar.reload()
            preview.setBase(nil); preview.setBase(root)
            then?()
        }
    }

    private func open(url: URL) {
        if url.isFileURL, !FileManager.default.isReadableFile(atPath: url.path), sidebar.root != nil {
            return grantFolderAccess { [weak self] in self?.open(url: url) }
        }
        if url.isFileURL, SidebarModel.extensions.contains(url.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func newFileInFolder() {
        guard let root = sidebar.root else { return NSDocumentController.shared.newDocument(nil) }
        guard FolderAccess.canRead(root) else { return grantFolderAccess { [weak self] in self?.newFileInFolder() } }
        var url = root.appendingPathComponent("Untitled.md"), n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = root.appendingPathComponent("Untitled \(n).md"); n += 1 }
        do {
            try Data().write(to: url, options: .withoutOverwriting)
            sidebar.reload()
            open(url: url)
        } catch { presentError(error) }
    }

    // MARK: Export & print

    private var baseName: String { (document as? Document)?.displayName.replacingOccurrences(of: ".md", with: "") ?? "Untitled" }

    @objc func exportHTML(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = baseName + ".html"
        // Standalone pages load KaTeX/Mermaid from a CDN when the note uses them (the app bundles its own copies).
        let page = Renderer.page(editor.text).replacingOccurrences(of: "</body>", with: Renderer.exportScripts + "</body>")
        panel.beginSheetModal(for: window) { r in
            guard r == .OK, let url = panel.url else { return }
            do { try page.write(to: url, atomically: true, encoding: .utf8) } catch { self.presentError(error) }
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = baseName + ".pdf"
        panel.beginSheetModal(for: window) { r in
            guard r == .OK, let url = panel.url else { return }
            let info = self.printInfo()
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            self.runPrint(info, panel: false)
        }
    }

    @objc func printMarkdown(_ sender: Any?) { runPrint(printInfo(), panel: true) }

    private func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 48; info.bottomMargin = 48; info.leftMargin = 48; info.rightMargin = 48
        return info
    }

    private func runPrint(_ info: NSPrintInfo, panel: Bool) {
        render { [weak self] in
            guard let self, let window else { return }
            let op = preview.printOperation(info)
            op.showsPrintPanel = panel
            op.showsProgressPanel = panel
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    // MARK: Window & toolbar delegates

    func windowDidBecomeKey(_ notification: Notification) { sidebar.reload() }

    func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: "ParchlyWindow")
        UserDefaults.standard.set(!sidebarItem.isCollapsed, forKey: "sidebarShown")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.modeItem, .flexibleSpace, Self.formatItem, Self.searchItem, Self.previewItem, Self.moreItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ symbol: String, _ label: String, _ tip: String, _ action: Selector) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.label = label
            item.toolTip = tip
            item.action = action
            item.target = self
            item.isBordered = true
            return item
        }
        switch id {
        case Self.modeItem:
            let item = NSToolbarItem(itemIdentifier: id)
            modeControl.selected = source ? 1 : 0
            item.view = glass(modeControl, cornerRadius: 13)
            item.label = "Mode"
            return item
        case Self.formatItem: return button("textformat", "Format", "Show or hide the formatting bar", #selector(toggleFormatBar(_:)))
        case Self.searchItem: return button("magnifyingglass", "Find", "Find  ⌘F", #selector(find(_:)))
        case Self.previewItem: return button("rectangle.split.2x1", "Preview", "Side-by-side preview  ⌘\\", #selector(togglePreview(_:)))
        case Self.moreItem:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
            item.label = "More"
            item.showsIndicator = false
            let menu = NSMenu()
            let theme = NSMenu()
            for (i, t) in Theme.choices.enumerated() {
                let m = NSMenuItem(title: t.name, action: #selector(setTheme(_:)), keyEquivalent: ""); m.tag = i; theme.addItem(m)
            }
            let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: ""); themeItem.submenu = theme
            for (title, action) in [("Side-by-Side Preview", #selector(togglePreview(_:))), ("Files & Outline", #selector(quickOpen(_:))),
                                    ("-", nil), ("Export as PDF…", #selector(exportPDF(_:))), ("Export as HTML…", #selector(exportHTML(_:))),
                                    ("Print…", #selector(printMarkdown(_:))), ("Reveal in Finder", #selector(revealInFinder(_:))), ("-", nil)] as [(String, Selector?)] {
                menu.addItem(title == "-" ? .separator() : NSMenuItem(title: title, action: action, keyEquivalent: ""))
            }
            menu.addItem(themeItem)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ""))
            item.menu = menu
            return item
        default:
            return nil
        }
    }
}

/// Downright-style "Document | Source" pill: plain labels, accent underline under the active one.
final class ModeSwitch: NSView {
    var onChange: (Int) -> Void = { _ in }
    var selected = 0 { didSet { update() } }
    private let buttons = ["Document", "Source"].map { NSButton(title: $0, target: nil, action: nil) }
    private let underline = NSView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 214, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        for (i, b) in buttons.enumerated() {
            b.isBordered = false
            b.tag = i
            b.target = self
            b.action = #selector(clicked(_:))
            b.frame = NSRect(x: 8 + CGFloat(i) * 99, y: 4, width: 99, height: 26)
            addSubview(b)
        }
        underline.wantsLayer = true
        underline.layer?.cornerRadius = 1
        addSubview(underline)
        update()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 214, height: 34) }

    override func updateLayer() {
        let glassy: Bool
        if #available(macOS 26.0, *) { glassy = true } else { glassy = false }
        layer?.backgroundColor = glassy ? NSColor.clear.cgColor : NSColor.surface.cgColor
        layer?.borderColor = glassy ? NSColor.clear.cgColor : NSColor.rule.cgColor
        underline.layer?.backgroundColor = NSColor.accent.withAlphaComponent(0.8).cgColor
    }
    override var wantsUpdateLayer: Bool { true }

    @objc private func clicked(_ b: NSButton) {
        guard b.tag != selected else { return }
        selected = b.tag
        onChange(b.tag)
    }

    private func update() {
        for (i, b) in buttons.enumerated() {
            let on = i == selected
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: on ? .semibold : .regular),
                .foregroundColor: on ? NSColor.labelColor : NSColor.tertiaryLabelColor])
        }
        let b = buttons[selected].frame
        underline.frame = NSRect(x: b.midX - 17, y: 5, width: 34, height: 2)
        needsDisplay = true
    }
}


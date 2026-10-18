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
    private lazy var shell = FileManager.default.temporaryDirectory.appendingPathComponent("inkdown-\(UUID().uuidString).html")

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 600), configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")   // no white flash before CSS paints
        web.underPageBackgroundColor = .paper
        view = web
        reload()
    }

    deinit { try? FileManager.default.removeItem(at: shell) }

    func setBase(_ url: URL?) {
        guard url != base else { return }
        base = url
        if isViewLoaded { reload() }
    }

    /// Shell page with a <base> so relative images resolve; content is then swapped in place to keep scroll position.
    private func reload() {
        loaded = false
        let page = Renderer.page("", base: base).replacingOccurrences(of: "<article id=\"c\"></article>", with: "<article id=\"c\">\(html)</article>")
        try? page.write(to: shell, atomically: true, encoding: .utf8)
        web.loadFileURL(shell, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func update(_ markdown: String, then: (() -> Void)? = nil) {
        html = Renderer.html(markdown)
        guard loaded else { then?(); return }
        web.evaluateJavaScript("document.getElementById('c').innerHTML = \(Self.js(html))", in: nil, in: .defaultClient) { _ in then?() }
    }

    func scroll(to fraction: CGFloat) {
        guard loaded else { return }
        web.evaluateJavaScript("window.scrollTo(0, \(fraction) * (document.documentElement.scrollHeight - window.innerHeight))", in: nil, in: .defaultClient) { _ in }
    }

    static func js(_ s: String) -> String { String(data: try! JSONEncoder().encode(s), encoding: .utf8)! }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        web.evaluateJavaScript("document.getElementById('c').innerHTML = \(Self.js(html))", in: nil, in: .defaultClient) { _ in }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        let samePage = url.isFileURL && (url.path == shell.path || url.path == base?.path || url.path + "/" == base?.path)
        if let fragment = url.fragment, samePage {
            web.evaluateJavaScript("document.getElementById(\(Self.js(fragment)))?.scrollIntoView()", in: nil, in: .defaultClient) { _ in }
        } else {
            openLink(url)
        }
    }

    func printOperation(_ info: NSPrintInfo) -> NSPrintOperation {
        let op = web.printOperation(with: info)
        op.view?.frame = NSRect(x: 0, y: 0, width: info.paperSize.width, height: info.paperSize.height)
        return op
    }
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
    private let modeControl = NSSegmentedControl(labels: ["Document", "Source"], trackingMode: .selectOne, target: nil, action: nil)
    private var source = UserDefaults.standard.bool(forKey: "source")
    private var showsPreview = UserDefaults.standard.bool(forKey: "preview")
    private var renderWork: DispatchWorkItem?
    private static let modeItem = NSToolbarItem.Identifier("mode")
    private static let previewItem = NSToolbarItem.Identifier("preview")
    private static let searchItem = NSToolbarItem.Identifier("search")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "InkdownDocument"
        window.minSize = NSSize(width: 520, height: 320)
        window.backgroundColor = .paper

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
        if !window.setFrameUsingName("InkdownWindow") { window.center() }

        let toolbar = NSToolbar(identifier: "InkdownToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [Self.modeItem]
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        editor.onChange = { [weak self] in self?.scheduleRender() }
        editor.onScroll = { [weak self] f in if self?.showsPreview == true { self?.preview.scroll(to: f) } }
        editor.textView.openLink = { [weak self] in self?.open(link: $0) }
        preview.openLink = { [weak self] in self?.open(url: $0) }
        sidebar.open = { [weak self] in self?.open(url: $0) }
        sidebar.jump = { [weak self] in self?.editor.jump(to: $0) }
        sidebar.newFile = { [weak self] in self?.newFileInFolder() }
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
        modeControl.selectedSegment = source ? 1 : 0
        if showsPreview {
            split.view.layoutSubtreeIfNeeded()
            let a = editor.view.frame, b = preview.view.frame
            split.splitView.setPosition(a.minX + (b.maxX - a.minX) / 2, ofDividerAt: 1)
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
    @objc private func modeClicked(_ sender: NSSegmentedControl) { setSource(sender.selectedSegment == 1) }
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
        default: break
        }
        return true
    }

    // MARK: Files & links

    private func open(link: String) {
        if let url = URL(string: link), url.scheme != nil { return open(url: url) }
        guard let root = sidebar.root else { return }
        let path = link.components(separatedBy: "#")[0].removingPercentEncoding ?? link
        guard !path.isEmpty else { return }
        open(url: URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL)
    }

    private func open(url: URL) {
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
        let page = Renderer.page(editor.text)
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
        window?.saveFrame(usingName: "InkdownWindow")
        UserDefaults.standard.set(!sidebarItem.isCollapsed, forKey: "sidebarShown")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.modeItem, .flexibleSpace, Self.previewItem, Self.searchItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.modeItem:
            modeControl.segmentStyle = .automatic
            modeControl.selectedSegment = source ? 1 : 0
            modeControl.target = self
            modeControl.action = #selector(modeClicked(_:))
            modeControl.setToolTip("Document  ⌃⌘1", forSegment: 0)
            modeControl.setToolTip("Source  ⌃⌘2", forSegment: 1)
            for i in 0..<2 { modeControl.setWidth(96, forSegment: i) }
            item.view = modeControl
            item.label = "Mode"
        case Self.previewItem:
            item.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Preview")
            item.label = "Preview"
            item.toolTip = "Side-by-side preview  ⌘\\"
            item.action = #selector(togglePreview(_:))
            item.target = self
        case Self.searchItem:
            item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
            item.label = "Find"
            item.toolTip = "Find  ⌘F"
            item.action = #selector(find(_:))
            item.target = self
        default:
            return nil
        }
        return item
    }
}

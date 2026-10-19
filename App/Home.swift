import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The start window: new / open actions on the left, recent documents on the right. Shown at launch,
/// when the last document closes, and from Window ▸ Home.
final class HomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = HomeWindowController()
    private let model = HomeModel()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Parchly"
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: HomeView(model: model))
        window.setContentSize(NSSize(width: 780, height: 480))
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        model.reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() { window?.orderOut(nil) }

    /// Shows Home once no document windows are left (after the closing one is gone).
    static func showIfNoDocuments() {
        DispatchQueue.main.async {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.windowController is WindowController }) { shared.show() }
        }
    }
}

final class HomeModel: ObservableObject {
    struct Recent: Hashable { var url: URL; var folder: String; var date: Date? }
    @Published var recents: [Recent] = []
    @Published var hasClipboardText = false

    func reload() {
        recents = NSDocumentController.shared.recentDocumentURLs.prefix(12).map { url in
            let dirs = url.deletingLastPathComponent().pathComponents.suffix(2)
            return Recent(url: url, folder: dirs.joined(separator: " › "),
                          date: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
        hasClipboardText = !(NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func newDocument() { NSDocumentController.shared.newDocument(nil) }
    func open() { NSDocumentController.shared.openDocument(nil) }
    func guide() { (NSApp.delegate as? AppDelegate)?.showGuide(nil) }

    func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    /// New document holding the clipboard text, as an ordinary unsaved edit (undoable, asks to save).
    func newFromClipboard() {
        guard let s = NSPasteboard.general.string(forType: .string),
              let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? Document,
              let tv = doc.controller?.editor.textView else { return }
        tv.replace(NSRange(location: 0, length: 0), with: s, select: NSRange(location: 0, length: 0))
    }
}

struct HomeView: View {
    @ObservedObject var model: HomeModel
    @State private var dropping = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Parchly").font(.system(size: 30, weight: .semibold, design: .serif)).padding(.top, 10)
                Text("Write, read and organise Markdown.").foregroundStyle(.secondary).padding(.top, 2)
                VStack(spacing: 4) {
                    HomeAction(symbol: "square.and.pencil", title: "New Document", key: "⌘N", run: model.newDocument)
                    HomeAction(symbol: "folder", title: "Open…", key: "⌘O", run: model.open)
                    if model.hasClipboardText {
                        HomeAction(symbol: "doc.on.clipboard", title: "New from Clipboard", key: "", run: model.newFromClipboard)
                    }
                    HomeAction(symbol: "book", title: "Markdown Guide", key: "", run: model.guide)
                }
                .padding(.top, 28)
                Spacer(minLength: 0)
                Text("Drop Markdown files anywhere here to open them.").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(EdgeInsets(top: 44, leading: 32, bottom: 22, trailing: 24))
            .frame(width: 300, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Recent").font(.headline).foregroundStyle(.secondary).padding(.leading, 10)
                if model.recents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 26)).foregroundStyle(.tertiary)
                        Text("No Recent Documents").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) { ForEach(model.recents, id: \.self) { RecentRow(item: $0, open: model.open) } }
                    }
                }
            }
            .padding(EdgeInsets(top: 44, leading: 14, bottom: 18, trailing: 18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .surface).opacity(0.6))
        }
        .background(Color(nsColor: .paper))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(6)
                .opacity(dropping ? 1 : 0).animation(.easeOut(duration: 0.15), value: dropping)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { model.open(url) } }
                }
            }
            return true
        }
        .ignoresSafeArea()
        .frame(width: 780, height: 480)
    }
}

private struct HomeAction: View {
    let symbol: String, title: String, key: String, run: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(Color.accentColor)
                Text(title)
                Spacer()
                Text(key).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

private struct RecentRow: View {
    let item: HomeModel.Recent, open: (URL) -> Void
    @State private var hover = false

    var body: some View {
        Button { open(item.url) } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.deletingPathExtension().lastPathComponent).lineLimit(1)
                    Text(item.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 8)
                if let d = item.date { Text(d, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .contextMenu {
            Button("Open") { open(item.url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }
}

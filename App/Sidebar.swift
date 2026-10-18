import SwiftUI

final class SidebarModel: ObservableObject {
    enum Tab: Hashable { case files, outline }
    @Published var tab: Tab = .files
    @Published var query = ""
    @Published var files: [URL] = []
    @Published var headings: [MD.Heading] = []
    @Published var current: URL?
    @Published var focusTick = 0
    @Published var needsAccess = false
    var root: URL?
    var grant: () -> Void = {}
    var open: (URL) -> Void = { _ in }
    var jump: (Int) -> Void = { _ in }
    var newFile: () -> Void = {}
    var done: () -> Void = {}

    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]

    func reload() {
        guard let root else { files = []; needsAccess = false; return }
        needsAccess = !FolderAccess.canRead(root)
        guard !needsAccess else { files = []; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan(root)
            DispatchQueue.main.async { if self.root == root, self.files != found { self.files = found } }
        }
    }

    // ponytail: depth 5 / 20k entries caps scanning of huge folders (e.g. a doc in ~); index with FSEvents if that ever bites.
    static func scan(_ root: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = [], seen = 0
        for case let url as URL in en {
            seen += 1
            if seen > 20_000 { break }
            if en.level > 5 || ["node_modules", "DerivedData", "Pods", "build"].contains(url.lastPathComponent) { en.skipDescendants(); continue }
            if extensions.contains(url.pathExtension.lowercased()) { out.append(url.standardizedFileURL) }
        }
        let base = root.standardizedFileURL.path
        return out.sorted { $0.path.dropFirst(base.count).localizedStandardCompare($1.path.dropFirst(base.count)) == .orderedAscending }
    }

    func relative(_ url: URL) -> String {
        guard let root else { return url.lastPathComponent }
        let base = root.standardizedFileURL.path
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count + 1)) : url.lastPathComponent
    }

    var visibleFiles: [URL] {
        let q = query.lowercased()
        guard !q.isEmpty else { return files }
        func subsequence(_ s: String) -> Bool {
            var it = s.makeIterator()
            return q.allSatisfy { c in while let x = it.next() { if x == c { return true } }; return false }
        }
        return files.compactMap { url -> (Int, URL)? in
            let name = url.lastPathComponent.lowercased(), rel = relative(url).lowercased()
            let score = name.hasPrefix(q) ? 0 : name.contains(q) ? 1 : rel.contains(q) ? 2 : subsequence(rel) ? 3 : nil
            return score.map { ($0, url) }
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    var visibleHeadings: [MD.Heading] {
        query.isEmpty ? headings : headings.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

struct SidebarView: View {
    @ObservedObject var model: SidebarModel
    @FocusState private var searching: Bool
    @State private var highlight = 0

    private var count: Int { model.tab == .files ? model.visibleFiles.count : model.visibleHeadings.count }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text("Files").tag(SidebarModel.Tab.files)
                Text("Outline").tag(SidebarModel.Tab.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.top, 6)

            TextField(model.tab == .files ? "Go to file  ⌘P" : "Go to heading  ⇧⌘O", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searching)
                .padding(10)
                .onSubmit { activate(highlight) }
                .onKeyPress(.downArrow) { highlight = min(highlight + 1, max(0, count - 1)); return .handled }
                .onKeyPress(.upArrow) { highlight = max(highlight - 1, 0); return .handled }
                .onKeyPress(.escape) { model.query = ""; model.done(); return .handled }

            ScrollViewReader { proxy in
                List {
                    if model.tab == .files { fileRows } else { headingRows }
                }
                .overlay { if model.tab == .files && model.needsAccess { accessPrompt } }
                .listStyle(.sidebar)
                .onChange(of: highlight) { proxy.scrollTo(highlight) }
            }

            if model.tab == .files {
                Divider()
                HStack {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(model.root?.lastPathComponent ?? "Unsaved document").lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: model.newFile) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("New file in this folder")
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onChange(of: model.focusTick) { searching = true; highlight = 0 }
        .onChange(of: model.query) { highlight = 0 }
        .onChange(of: model.tab) { highlight = 0 }
    }

    private func activate(_ i: Int) {
        if model.tab == .files {
            let files = model.visibleFiles
            if files.indices.contains(i) { model.open(files[i]) }
        } else {
            let hs = model.visibleHeadings
            if hs.indices.contains(i) { model.jump(hs[i].location) }
        }
        model.query = ""
    }

    private func rowBackground(_ i: Int) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(searching && i == highlight ? Color.accentColor.opacity(0.18) : .clear)
    }

    /// Sandboxed builds can only read folders the user has granted.
    private var accessPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("See the other Markdown files in “\(model.root?.lastPathComponent ?? "this folder")”.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Allow Access…", action: model.grant)
        }
        .font(.callout)
        .padding(20)
    }

    private var fileRows: some View {
        ForEach(Array(model.visibleFiles.enumerated()), id: \.element) { i, url in
            let isCurrent = url == model.current?.standardizedFileURL
            let rel = model.relative(url)
            let dir = (rel as NSString).deletingLastPathComponent
            Button { model.open(url) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text").foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.deletingPathExtension().lastPathComponent).fontWeight(isCurrent ? .semibold : .regular).lineLimit(1)
                        if !dir.isEmpty { Text(dir).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(rowBackground(i))
            .id(i)
        }
    }

    private var headingRows: some View {
        ForEach(Array(model.visibleHeadings.enumerated()), id: \.element) { i, h in
            Button { model.jump(h.location) } label: {
                Text(h.title)
                    .fontWeight(h.level == 1 ? .semibold : .regular)
                    .foregroundStyle(h.level > 3 ? .secondary : .primary)
                    .lineLimit(1)
                    .padding(.leading, CGFloat(h.level - 1) * 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(rowBackground(i))
            .id(i)
        }
    }
}

/// Folder permissions for the App Sandbox, remembered as security-scoped bookmarks.
enum FolderAccess {
    private static let key = "folderBookmarks"

    static func canRead(_ dir: URL) -> Bool { (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) != nil }

    static func restore() {
        for data in UserDefaults.standard.array(forKey: key) as? [Data] ?? [] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
            }
        }
    }

    static func add(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set((UserDefaults.standard.array(forKey: key) as? [Data] ?? []) + [data], forKey: key)
    }
}

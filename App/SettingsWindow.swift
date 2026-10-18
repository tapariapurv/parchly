import SwiftUI
import Sparkle

/// Settings (⌘,): theme, editor options and updates.
struct SettingsView: View {
    let updater: SPUUpdater
    @AppStorage("themeID") private var themeID = "paper"
    @AppStorage("lineNumbers") private var lineNumbers = false
    @AppStorage("formatBar") private var formatBar = true
    @AppStorage("spellCheck") private var spellCheck = false
    @AppStorage("fontSize") private var fontSize = 16.0
    @State private var autoCheck = true
    @State private var autoInstall = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Theme") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(Theme.choices, id: \.id) { choice in
                            ThemeSwatch(choice: choice, selected: themeID == choice.id) { Theme.id = choice.id; themeID = choice.id }
                        }
                    }
                }
                section("Editor") {
                    HStack {
                        Text("Text size")
                        Slider(value: Binding(get: { fontSize }, set: { Settings.fontSize = $0.rounded(); fontSize = Settings.fontSize }), in: 12...26, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    Toggle("Show the formatting bar", isOn: Binding(get: { formatBar }, set: { Settings.formatBar = $0; formatBar = $0 }))
                    Toggle("Show line numbers in Source mode", isOn: Binding(get: { lineNumbers }, set: { Settings.lineNumbers = $0; lineNumbers = $0 }))
                    Toggle("Check spelling while typing", isOn: Binding(get: { spellCheck }, set: { Settings.spellCheck = $0; spellCheck = $0 }))
                }
                section("Updates") {
                    Toggle("Automatically check for updates", isOn: $autoCheck)
                        .onChange(of: autoCheck) { updater.automaticallyChecksForUpdates = autoCheck }
                    Toggle("Download and install updates automatically", isOn: $autoInstall)
                        .onChange(of: autoInstall) { updater.automaticallyDownloadsUpdates = autoInstall }
                        .disabled(!autoCheck)
                    HStack {
                        Button("Check Now") { updater.checkForUpdates() }
                        Spacer()
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 560, height: 600)
        .onAppear {
            autoCheck = updater.automaticallyChecksForUpdates
            autoInstall = updater.automaticallyDownloadsUpdates
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        }
    }
}

private struct ThemeSwatch: View {
    let choice: (id: String, name: String)
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        let p = Theme.all.first { $0.id == choice.id }
        let bg = p.map { Color(nsColor: $0.color(0)) } ?? Color(nsColor: Theme.all[0].color(0))
        let fg = p.map { Color(nsColor: $0.color(5)) } ?? Color(nsColor: Theme.all[0].color(5))
        let accent = p.map { Color(nsColor: $0.color(7)) } ?? Color(nsColor: Theme.all[0].color(7))
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if p == nil {   // Paper (Auto): half light, half dark
                        HStack(spacing: 0) { Color(nsColor: Theme.all[0].color(0)); Color(nsColor: Theme.all[1].color(0)) }
                    } else { bg }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aa").font(.system(size: 18, weight: .bold, design: .serif)).foregroundStyle(fg)
                        Capsule().fill(fg.opacity(0.35)).frame(width: 60, height: 4)
                        Capsule().fill(accent).frame(width: 34, height: 4)
                    }.padding(10)
                }
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1))
                Text(choice.name).font(.callout).fontWeight(selected ? .semibold : .regular)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Liquid Glass on macOS 26, a quiet material card before that.
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init(updater: SPUUpdater) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(updater: updater)))
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        self.init(window: window)
        window.center()
    }
}

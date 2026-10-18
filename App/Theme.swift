import AppKit

/// Editor/preview colours. The first five match Downright's built-in themes; the rest are Parchly's own.
struct Palette {
    let id, name: String
    let dark: Bool
    // background, surface, text, secondary, faint, heading, marker, accent, link, rule, selection,
    // code block, inline code, quote bar | keyword, string, number, comment, type, function
    let hex: [String]

    init(id: String, name: String, dark: Bool, hex: String) {
        self.id = id; self.name = name; self.dark = dark
        self.hex = hex.split(separator: " ").map(String.init)
    }

    func color(_ i: Int) -> NSColor {
        let v = UInt32(hex[i].dropFirst(), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    /// CSS custom properties for the HTML preview.
    var css: String {
        let names = ["bg", "surface", "fg", "muted", "faint", "heading", "marker", "accent", "link", "line", "selection", "code", "inline-code", "quote",
                     "kw", "str", "num", "com", "type", "fn"]
        return ":root{" + zip(names, hex).map { "--\($0):\($1);" }.joined() + "color-scheme:\(dark ? "dark" : "light")}"
    }
}

enum Theme {
    static let all: [Palette] = [
        Palette(id: "paper-light", name: "Paper Light", dark: false, hex: "#f7f4ee #fffdfa #292522 #685f56 #8b8178 #181513 #71665c #307afe #245fb8 #d9d2c8 #d9e7fc #eeeae3 #e8e2d9 #c9b294 #8e4f7d #456f58 #1a659e #8b817c #1d6ca4 #2a5db0"),
        Palette(id: "warm-dark", name: "Warm Dark", dark: true, hex: "#171614 #24211e #e3ddd5 #aca297 #7f776f #f4eee5 #bdb2a6 #6ea8ff #8ab8ff #3d3832 #253a56 #231f1a #2d2822 #625344 #e0879f #a8c08a #8fb8d9 #726a61 #e7c77d #8fb8d9"),
        Palette(id: "nord", name: "Nord", dark: true, hex: "#2e3440 #3b4252 #d8dee9 #aeb8c8 #747e90 #eceff4 #b7c0d0 #88c0d0 #81a1c1 #3b4252 #434c5e #2b303b #353b48 #4c566a #81a1c1 #a3be8c #b48ead #6e7a91 #8fbcbb #88c0d0"),
        Palette(id: "solarized-light", name: "Solarized Light", dark: false, hex: "#fdf6e3 #eee8d5 #526b72 #526b72 #849090 #586e75 #526b72 #268bd2 #006d9c #eee8d5 #e6dfc6 #eee8d5 #eee8d5 #93a1a1 #606e00 #1e736d #ba3073 #7b8686 #836300 #1e6ca4"),
        Palette(id: "high-contrast", name: "High Contrast", dark: false, hex: "#ffffff #f2f2f2 #000000 #2a2a2a #4a4a4a #000000 #5a5a5a #0000cc #0000cc #000000 #ffd400 #f2f2f2 #e8e8e8 #000000 #7a0080 #006600 #0000cc #4a4a4a #005a6e #00308f"),
        Palette(id: "sepia", name: "Sepia", dark: false, hex: "#f3e9d7 #faf3e6 #3f3226 #6f5b47 #927d66 #2c2118 #8a6d4f #b4652b #9a4f1c #dbc9ab #ecd6b3 #eadcc3 #e6d5b8 #c49a6c #9b3d5a #5b7a3a #2f6a8f #9a8670 #7a5a1e #2f5f8f"),
        Palette(id: "solarized-dark", name: "Solarized Dark", dark: true, hex: "#002b36 #073642 #93a1a1 #839496 #586e75 #eee8d5 #839496 #268bd2 #2aa1e6 #0f4a57 #0d4f5f #01323e #073f4c #586e75 #859900 #2aa198 #d33682 #657b83 #b58900 #268bd2"),
        Palette(id: "forest", name: "Forest", dark: true, hex: "#151c18 #1e2722 #d6dfd5 #a3b3a2 #73836f #eef4ea #a9bba4 #7cc48b #8fd19b #2f3b33 #24432f #1b241f #243029 #4f6b52 #d99a6c #a8cf8e #8ec5c9 #6c7b6a #e3c97a #8fc7e8"),
        Palette(id: "midnight", name: "Midnight", dark: true, hex: "#10131c #181d2a #d7dcea #a2abc2 #6e7792 #f1f3fa #a8b1cc #8b9cff #a5b2ff #2a3145 #2c3560 #161b27 #1f2536 #4a5480 #c792ea #c3e88d #f78c6c #676e95 #ffcb6b #82aaff"),
    ]

    /// "paper" follows macOS: Paper Light by day, Warm Dark at night (Downright's "System").
    static let choices: [(id: String, name: String)] = [("paper", "Paper (Auto)")] + all.map { ($0.id, $0.name) }

    static let changed = Notification.Name("ParchlyThemeChanged")
    static var id: String {
        get { UserDefaults.standard.string(forKey: "themeID") ?? "paper" }
        set { UserDefaults.standard.set(newValue, forKey: "themeID"); apply() }
    }

    static func palette(dark: Bool) -> Palette {
        if let fixed = all.first(where: { $0.id == id }) { return fixed }
        return all[dark ? 1 : 0]
    }

    static var current: Palette { palette(dark: NSApp.effectiveAppearance.isDark) }

    /// Fixed themes pin the app's appearance so system controls match them.
    static func apply() {
        if let fixed = all.first(where: { $0.id == id }) {
            NSApp.appearance = NSAppearance(named: fixed.dark ? .darkAqua : .aqua)
        } else {
            NSApp.appearance = nil
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// A colour that always resolves against the current theme and appearance.
    static func color(_ i: Int) -> NSColor {
        NSColor(name: nil) { palette(dark: $0.isDark).color(i) }
    }

    static func mix(_ a: Int, _ b: Int, _ t: CGFloat) -> NSColor {
        NSColor(name: nil) {
            let p = palette(dark: $0.isDark)
            return p.color(a).blended(withFraction: t, of: p.color(b)) ?? p.color(a)
        }
    }
}

extension NSColor {
    static let paper = Theme.color(0)
    static let surface = Theme.color(1)
    static let ink = Theme.color(2)
    static let inkSecondary = Theme.color(3)
    static let syntax = Theme.color(4)
    static let heading = Theme.color(5)
    static let marker = Theme.color(6)
    static let accent = Theme.color(7)
    static let link = Theme.color(8)
    static let rule = Theme.color(9)
    static let selection = Theme.color(10)
    static let codeFill = Theme.color(11)
    static let inlineCodeFill = Theme.color(12)
    static let quoteBar = Theme.color(13)
    static let titleBand = Theme.mix(0, 2, 0.07)
    static func code(_ k: Int) -> NSColor { Theme.color(14 + k) }   // keyword, string, number, comment, type, function
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

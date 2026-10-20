import AppKit

/// Wraps a view in Liquid Glass (macOS 26+), or a soft material before that.
func glass(_ content: NSView, cornerRadius: CGFloat) -> NSView {
    if #available(macOS 26.0, *) {
        let g = NSGlassEffectView()
        g.contentView = content
        g.cornerRadius = cornerRadius
        return g
    }
    let v = NSVisualEffectView()
    v.material = .popover
    v.blendingMode = .withinWindow
    v.state = .active
    v.wantsLayer = true
    v.layer?.cornerRadius = cornerRadius
    v.layer?.masksToBounds = true
    content.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: v.leadingAnchor), content.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        content.topAnchor.constraint(equalTo: v.topAnchor), content.bottomAnchor.constraint(equalTo: v.bottomAnchor),
    ])
    return v
}

/// Bear-style floating formatting bar: every Markdown tool as a button, for people who don't know the syntax.
/// Buttons never take focus, so actions go down the responder chain to the editor.
enum FormatBar {
    private static let items: [(symbol: String, tip: String, action: Selector)] = [
        ("bold", "Bold  ⌘B", #selector(MarkdownTextView.toggleBold(_:))),
        ("italic", "Italic  ⌘I", #selector(MarkdownTextView.toggleItalic(_:))),
        ("strikethrough", "Strikethrough  ⇧⌘X", #selector(MarkdownTextView.toggleStrike(_:))),
        ("highlighter", "Highlight  ⇧⌘M", #selector(MarkdownTextView.toggleHighlight(_:))),
        ("chevron.left.forwardslash.chevron.right", "Inline code  ⌃`", #selector(MarkdownTextView.toggleInlineCode(_:))),
        ("link", "Link  ⌘K", #selector(MarkdownTextView.insertLink(_:))),
        ("|", "", #selector(NSObject.description)),
        ("list.bullet", "Bulleted list  ⇧⌘8", #selector(MarkdownTextView.toggleBullets(_:))),
        ("list.number", "Numbered list  ⇧⌘7", #selector(MarkdownTextView.toggleNumbers(_:))),
        ("checklist", "Task list  ⇧⌘9", #selector(MarkdownTextView.toggleTasks(_:))),
        ("text.quote", "Quote  ⌥⌘Q", #selector(MarkdownTextView.toggleQuote(_:))),
        ("|", "", #selector(NSObject.description)),
        ("curlybraces", "Code block  ⌥⌘C", #selector(MarkdownTextView.insertCodeBlock(_:))),
        ("tablecells", "Table  ⌥⌘T", #selector(MarkdownTextView.insertTable(_:))),
        ("minus", "Divider", #selector(MarkdownTextView.insertRule(_:))),
    ]

    static func make() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.addArrangedSubview(headingButton())
        stack.addArrangedSubview(separator())
        for item in items {
            guard item.symbol != "|" else { stack.addArrangedSubview(separator()); continue }
            stack.addArrangedSubview(button(item.symbol, item.tip, item.action))
        }
        // Narrow panes (sidebar + split view) drop tools from the right end instead of overflowing; the menu keeps them all.
        for (i, v) in stack.arrangedSubviews.enumerated() { stack.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: 900 - Float(i)), for: v) }
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        return glass(stack, cornerRadius: 20)
    }

    /// Aims the buttons at this editor, so they work even while the sidebar or Find field has focus.
    static func connect(_ bar: NSView, to tv: NSTextView) {
        for v in bar.subviews {
            if let b = v as? NSButton, b.target == nil { b.target = tv }
            connect(v, to: tv)
        }
    }

    private static func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: nil, action: action)
        b.isBordered = false
        b.bezelStyle = .accessoryBarAction
        b.showsBorderOnlyWhileMouseInside = true
        b.refusesFirstResponder = true
        b.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        b.contentTintColor = .ink
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private static func headingButton() -> NSButton {
        let b = button("textformat.size", "Heading  ⌘1–⌘6", #selector(HeadingMenu.show(_:)))
        b.target = HeadingMenu.shared
        return b
    }

    private static func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.widthAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }
}

/// Pops a heading-level menu under the bar's heading button.
final class HeadingMenu: NSObject {
    static let shared = HeadingMenu()
    @objc func show(_ sender: NSButton) {
        let menu = NSMenu()
        for (title, level) in [("Heading 1", 1), ("Heading 2", 2), ("Heading 3", 3), ("Heading 4", 4), ("Body Text", 0)] {
            let item = NSMenuItem(title: title, action: #selector(MarkdownTextView.setHeading(_:)), keyEquivalent: "\(level)")
            item.keyEquivalentModifierMask = .command
            item.tag = level
            item.target = sender.window.flatMap { Self.editor(in: $0.contentView) }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    static func editor(in v: NSView?) -> MarkdownTextView? {
        guard let v else { return nil }
        return v as? MarkdownTextView ?? v.subviews.lazy.compactMap { editor(in: $0) }.first
    }
}

/// Downright's outline glyph: three rules, the top one darker.
final class OutlineGlyph: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, mid = bounds.midY
        for (i, (len, alpha)) in [(1.0, 0.9), (0.78, 0.45), (0.78, 0.45)].enumerated() {
            NSColor.marker.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: NSRect(x: (w - w * len) / 2, y: mid - 8 + CGFloat(i) * 7, width: w * len, height: 2), xRadius: 1, yRadius: 1).fill()
        }
    }
    override var isFlipped: Bool { true }
}

/// Fades from the title band's shadow into the page.
final class ShadeView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor.black.withAlphaComponent(0.06), NSColor.black.withAlphaComponent(0)])?.draw(in: bounds, angle: isFlipped ? 90 : -90)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

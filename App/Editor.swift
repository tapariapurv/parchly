import AppKit

// MARK: - Text view

final class MarkdownTextView: NSTextView {
    var styler: Styler!
    var openLink: (String) -> Void = { _ in }

    private var ns: NSString { string as NSString }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let column = styler.fontSize * (styler.wysiwyg ? 36 : 42)
        let inset = max(64, ((newSize.width - column) / 2).rounded())
        if textContainerInset.width != inset { textContainerInset = NSSize(width: inset, height: 92) }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager as? MDLayoutManager, let tc = textContainer else { return }
        let origin = textContainerOrigin
        let glyphs = lm.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -1000, dy: 0), in: tc)
        lm.drawMargins(glyphs, at: origin)
    }

    // MARK: Typing helpers

    private static let wrappers: [String: String] = ["*": "*", "_": "_", "`": "`", "~": "~", "=": "=", "\"": "\"", "(": ")", "[": "]", "{": "}"]
    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]

    /// Typing a marker with text selected wraps it (select "word", type * → *word*); brackets auto-close.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let s = string as? String, s.count == 1, !hasMarkedText(), replacementRange.location == NSNotFound else {
            return super.insertText(string, replacementRange: replacementRange)
        }
        let sel = selectedRange()
        if sel.length > 0, let close = Self.wrappers[s], !ns.substring(with: sel).contains("\n") {
            breakUndoCoalescing()
            let text = ns.substring(with: sel)
            return replace(sel, with: s + text + close, select: NSRange(location: sel.location + 1, length: (text as NSString).length))
        }
        if sel.length == 0, !styler.inCode(sel.location) {
            let next = sel.location < ns.length ? ns.substring(with: NSRange(location: sel.location, length: 1)) : ""
            if Self.pairs.values.contains(s), next == s {   // type over an auto-inserted closer
                return setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            }
            if let close = Self.pairs[s], next.isEmpty || next.rangeOfCharacter(from: .whitespacesAndNewlines.union(.punctuationCharacters)) != nil, next != "(" {
                super.insertText(s + close, replacementRange: replacementRange)
                return setSelectedRange(NSRange(location: selectedRange().location - 1, length: 0))
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: Edit primitives

    /// One undoable replacement. Selection is given in post-edit coordinates.
    func replace(_ range: NSRange, with text: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage!.replaceCharacters(in: range, with: text)
        didChangeText()
        if let select { setSelectedRange(select) }
    }

    /// Content range (no newline) and text of the line containing `loc`.
    func line(at loc: Int) -> (range: NSRange, text: String) {
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
        let r = NSRange(location: start, length: contentsEnd - start)
        return (r, ns.substring(with: r))
    }

    /// Contiguous lines around `loc` (current line always included) whose text satisfies `include`.
    func lines(around loc: Int, _ include: (String) -> Bool) -> [(range: NSRange, text: String)] {
        let cur = line(at: loc)
        var out = [cur]
        var l = cur
        while l.range.location > 0 {
            let p = line(at: l.range.location - 1)
            guard include(p.text), !styler.inCode(p.range.location) else { break }
            out.insert(p, at: 0); l = p
        }
        l = cur
        while true {
            var end = 0
            ns.getLineStart(nil, end: &end, contentsEnd: nil, for: l.range)
            guard end < ns.length else { break }
            let n = line(at: end)
            guard include(n.text), !styler.inCode(n.range.location) else { break }
            out.append(n); l = n
        }
        return out
    }

    /// Replaces whole selected lines with `transform(lines)` as one edit.
    func transformLines(_ transform: ([String]) -> [String]) {
        let sel = selectedRange()
        let first = line(at: sel.location)
        let last = line(at: sel.length > 0 ? max(sel.location, sel.upperBound - 1) : sel.location)
        let r = NSUnionRange(first.range, last.range)
        let old = ns.substring(with: r)
        let new = transform(old.components(separatedBy: "\n")).joined(separator: "\n")
        guard new != old else { return }
        let len = (new as NSString).length
        if first.range == last.range {
            // Single line: keep the caret the same distance from the line end.
            let fromEnd = r.upperBound - sel.upperBound
            let caret = max(r.location, r.location + len - fromEnd)
            replace(r, with: new, select: NSRange(location: caret - min(sel.length, caret - r.location), length: min(sel.length, caret - r.location)))
        } else {
            replace(r, with: new, select: NSRange(location: r.location, length: len))
        }
    }

    private func renumberList(at loc: Int) {
        guard loc <= ns.length else { return }
        let block = lines(around: min(loc, ns.length), MD.inList)
        let new = MD.renumbered(block.map(\.text))
        var sel = selectedRange()
        for (l, n) in zip(block, new).reversed() where l.text != n {
            let delta = (n as NSString).length - l.range.length
            if sel.location > l.range.location { sel.location = max(l.range.location, sel.location + delta) }
            replace(l.range, with: n)
        }
        setSelectedRange(sel)
    }

    private func table(at loc: Int) -> (range: NSRange, rows: [String], row: Int)? {
        guard !styler.inCode(loc) else { return nil }
        let cur = line(at: loc)
        guard cur.text.contains("|") else { return nil }
        let block = lines(around: loc) { $0.contains("|") }
        guard block.count >= 2, MD.isSeparator(block[1].text), let row = block.firstIndex(where: { $0.range == cur.range }) else { return nil }
        return (NSUnionRange(block[0].range, block[block.count - 1].range), block.map(\.text), row)
    }

    private func apply(_ e: MD.TableEdit, replacing range: NSRange) {
        let text = e.lines.joined(separator: "\n")
        let rowStart = e.lines[..<e.row].reduce(0) { $0 + ($1 as NSString).length + 1 }
        replace(range, with: text, select: NSRange(location: range.location + rowStart + e.selection.location, length: e.selection.length))
    }

    // MARK: Keys

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length == 0, !hasMarkedText(), !NSEvent.modifierFlags.contains(.shift) else { return super.insertNewline(sender) }
        breakUndoCoalescing()
        let cur = line(at: sel.location)
        if styler.inCode(sel.location) {
            return replace(sel, with: "\n" + MD.leadingWhitespace(cur.text), select: nil)
        }
        if let t = table(at: sel.location) {
            return apply(MD.tableReturn(t.rows, row: t.row), replacing: t.range)
        }
        let prefix = Styler.prefixLength(cur.text)
        if prefix > 0, MD.parse(cur.text) == nil, sel.location == cur.range.location + prefix, cur.range.length > prefix {
            return replace(NSRange(location: cur.range.location, length: 0), with: "\n", select: NSRange(location: sel.location + 1, length: 0))
        }
        switch MD.returnEdit(line: cur.text, cursor: sel.location - cur.range.location) {
        case .insert(let s):
            replace(sel, with: s, select: NSRange(location: sel.location + (s as NSString).length, length: 0))
            if MD.parse(cur.text)?.number != nil { renumberList(at: selectedRange().location) }
        case .replaceLine(let s):
            replace(cur.range, with: s, select: NSRange(location: cur.range.location + (s as NSString).length, length: 0))
            renumberList(at: cur.range.location)
        }
        scrollRangeToVisible(selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else { return super.insertTab(sender) }
        let sel = selectedRange()
        if let t = table(at: sel.location) {
            breakUndoCoalescing()
            return apply(MD.tableTab(t.rows, row: t.row, cursor: sel.location - line(at: sel.location).range.location, backward: false), replacing: t.range)
        }
        let multi = ns.substring(with: sel).contains("\n")
        guard multi || MD.parse(line(at: sel.location).text).map({ !$0.isQuote }) == true, !styler.inCode(sel.location) else { return super.insertTab(sender) }
        indentLines(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        let sel = selectedRange()
        if let t = table(at: sel.location) {
            breakUndoCoalescing()
            return apply(MD.tableTab(t.rows, row: t.row, cursor: sel.location - line(at: sel.location).range.location, backward: true), replacing: t.range)
        }
        outdentLines(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length == 0, !hasMarkedText(), !styler.inCode(sel.location) else { return super.deleteBackward(sender) }
        // Backspace inside an empty auto-closed pair removes both halves.
        if sel.location > 0, sel.location < ns.length, let close = Self.pairs[ns.substring(with: NSRange(location: sel.location - 1, length: 1))],
           ns.substring(with: NSRange(location: sel.location, length: 1)) == close {
            return replace(NSRange(location: sel.location - 1, length: 2), with: "", select: NSRange(location: sel.location - 1, length: 0))
        }
        let cur = line(at: sel.location)
        let prefix = Styler.prefixLength(cur.text)
        if prefix > 0, MD.parse(cur.text) == nil, sel.location - cur.range.location == prefix {
            // Backspace at the start of a heading turns it into body text.
            breakUndoCoalescing()
            return replace(NSRange(location: cur.range.location, length: prefix), with: "", select: NSRange(location: cur.range.location, length: 0))
        }
        guard let p = MD.parse(cur.text), p.length > 0, sel.location - cur.range.location == p.length else { return super.deleteBackward(sender) }
        breakUndoCoalescing()
        // Backspace right after a marker: outdent a nested item, otherwise drop the marker.
        let new = !p.isQuote && !p.indent.isEmpty ? MD.outdent(cur.text) : (cur.text as NSString).substring(from: p.length)
        let keep = (new as NSString).length - (cur.range.length - p.length)
        replace(cur.range, with: new, select: NSRange(location: cur.range.location + max(0, keep), length: 0))
        renumberList(at: cur.range.location)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: point)
        if idx <= ns.length, let lm = layoutManager, let tc = textContainer {
            let cur = line(at: min(idx, ns.length))
            if let p = MD.parse(cur.text), p.task != nil, !styler.inCode(cur.range.location) {
                let boxStart = (cur.text as NSString).range(of: "[", range: NSRange(location: (p.indent as NSString).length, length: p.length - (p.indent as NSString).length)).location
                let box = NSRange(location: cur.range.location + boxStart, length: 3)
                var rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: box, actualCharacterRange: nil), in: tc)
                rect = rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y).insetBy(dx: -3, dy: -2)
                if rect.contains(point) {
                    breakUndoCoalescing()
                    replace(NSRange(location: box.location + 1, length: 1), with: p.task! ? " " : "x")
                    return
                }
            }
            if event.modifierFlags.contains(.command), idx < ns.length, let url = textStorage?.attribute(.mdURL, at: idx, effectiveRange: nil) as? String {
                return openLink(url)
            }
        }
        super.mouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0, let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.contains(where: \.isWhitespace), let u = URL(string: s), ["http", "https"].contains(u.scheme ?? ""),
           !ns.substring(with: sel).contains("\n") {
            let label = ns.substring(with: sel)
            breakUndoCoalescing()
            return replace(sel, with: "[\(label)](\(s))", select: NSRange(location: sel.location + (label as NSString).length + (s as NSString).length + 4, length: 0))
        }
        pasteAsPlainText(sender)
    }

    // MARK: Format commands (menu targets)

    private func wrap(_ m: String) {
        breakUndoCoalescing()
        let sel = selectedRange(), mlen = (m as NSString).length
        let text = ns.substring(with: sel)
        if text.count >= 2 * m.count, text.hasPrefix(m), text.hasSuffix(m) {
            let inner = (text as NSString).substring(with: NSRange(location: mlen, length: sel.length - 2 * mlen))
            return replace(sel, with: inner, select: NSRange(location: sel.location, length: (inner as NSString).length))
        }
        if sel.location >= mlen, sel.upperBound + mlen <= ns.length,
           ns.substring(with: NSRange(location: sel.location - mlen, length: mlen)) == m,
           ns.substring(with: NSRange(location: sel.upperBound, length: mlen)) == m {
            // "*" next to "**" is bold, not italic: only unwrap an odd run of stars.
            var stars = 0
            while m == "*", sel.location - stars - 1 >= 0, ns.character(at: sel.location - stars - 1) == 42 { stars += 1 }
            if m != "*" || stars % 2 == 1 {
                return replace(NSRange(location: sel.location - mlen, length: sel.length + 2 * mlen), with: text, select: NSRange(location: sel.location - mlen, length: sel.length))
            }
        }
        replace(sel, with: m + text + m, select: NSRange(location: sel.location + mlen, length: sel.length))
    }

    @objc func toggleBold(_ sender: Any?) { wrap("**") }
    @objc func toggleItalic(_ sender: Any?) { wrap("*") }
    @objc func toggleStrike(_ sender: Any?) { wrap("~~") }
    @objc func toggleInlineCode(_ sender: Any?) { wrap("`") }

    @objc func insertLink(_ sender: Any?) {
        breakUndoCoalescing()
        let sel = selectedRange(), text = ns.substring(with: sel)
        if let u = URL(string: text), u.scheme != nil, !text.contains(" ") {
            replace(sel, with: "[](\(text))", select: NSRange(location: sel.location + 1, length: 0))
        } else {
            let label = "[\(text)]("
            replace(sel, with: label + ")", select: NSRange(location: sel.location + (label as NSString).length, length: 0))
        }
    }

    @objc func setHeading(_ sender: NSMenuItem) { breakUndoCoalescing(); transformLines { $0.map { MD.setHeading($0, level: sender.tag) } } }
    @objc func toggleBullets(_ sender: Any?) { breakUndoCoalescing(); transformLines { MD.toggleList($0, .bullet) } }
    @objc func toggleNumbers(_ sender: Any?) { breakUndoCoalescing(); transformLines { MD.toggleList($0, .ordered) } }
    @objc func toggleTasks(_ sender: Any?) { breakUndoCoalescing(); transformLines { MD.toggleList($0, .task) } }
    @objc func toggleTaskDone(_ sender: Any?) { breakUndoCoalescing(); transformLines { $0.map(MD.toggleTask) } }

    @objc func toggleQuote(_ sender: Any?) {
        breakUndoCoalescing()
        transformLines { lines in
            let quoted = lines.allSatisfy { $0.hasPrefix(">") || $0.isEmpty }
            return lines.map { l in quoted ? String(l.dropFirst(l.hasPrefix("> ") ? 2 : (l.hasPrefix(">") ? 1 : 0))) : "> " + l }
        }
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        breakUndoCoalescing()
        let sel = selectedRange()
        let r = NSUnionRange(line(at: sel.location).range, line(at: max(sel.location, sel.upperBound - (sel.length > 0 ? 1 : 0))).range)
        let body = ns.substring(with: r)
        replace(r, with: "```\n\(body)\n```", select: NSRange(location: r.location + 4, length: (body as NSString).length))
    }

    @objc func insertTable(_ sender: Any?) {
        breakUndoCoalescing()
        let cur = line(at: selectedRange().location)
        let blankLine = cur.text.trimmingCharacters(in: .whitespaces).isEmpty
        let lead = blankLine ? "" : "\n\n"
        let at = blankLine ? cur.range : NSRange(location: cur.range.upperBound, length: 0)
        replace(at, with: lead + MD.tableTemplate.joined(separator: "\n"), select: NSRange(location: at.location + (lead as NSString).length + 2, length: 8))
    }

    @objc func indentLines(_ sender: Any?) {
        breakUndoCoalescing()
        let loc = selectedRange().location
        transformLines { $0.map { $0.isEmpty ? $0 : MD.indent($0) } }
        renumberList(at: line(at: min(loc, ns.length)).range.location)
    }

    @objc func outdentLines(_ sender: Any?) {
        breakUndoCoalescing()
        let loc = selectedRange().location
        transformLines { $0.map(MD.outdent) }
        renumberList(at: line(at: min(loc, ns.length)).range.location)
    }

    @objc func moveLineUp(_ sender: Any?) { moveLines(up: true) }
    @objc func moveLineDown(_ sender: Any?) { moveLines(up: false) }

    private func moveLines(up: Bool) {
        let sel = selectedRange()
        let block = ns.lineRange(for: sel.length > 0 ? NSRange(location: sel.location, length: sel.length - 1) : sel)
        guard up ? block.location > 0 : block.upperBound < ns.length else { return }
        breakUndoCoalescing()
        let other = ns.lineRange(for: NSRange(location: up ? block.location - 1 : block.upperBound, length: 0))
        let total = NSUnionRange(block, other)
        var text = ns.substring(with: total)
        let trailing = text.hasSuffix("\n")
        if trailing { text.removeLast() }
        var lines = text.components(separatedBy: "\n")
        let moved = up ? lines.removeFirst() : lines.removeLast()
        lines = up ? lines + [moved] : [moved] + lines
        let shift = (moved as NSString).length + 1
        replace(total, with: lines.joined(separator: "\n") + (trailing ? "\n" : ""), select: NSRange(location: sel.location + (up ? -shift : shift), length: sel.length))
        scrollRangeToVisible(selectedRange())
    }

    @objc func insertRule(_ sender: Any?) {
        breakUndoCoalescing()
        let cur = line(at: selectedRange().location)
        let blank = cur.text.trimmingCharacters(in: .whitespaces).isEmpty
        let text = blank ? "---\n" : "\n\n---\n"
        let at = blank ? cur.range : NSRange(location: cur.range.upperBound, length: 0)
        replace(at, with: text, select: NSRange(location: at.location + (text as NSString).length, length: 0))
    }

    @objc func duplicateLine(_ sender: Any?) {
        breakUndoCoalescing()
        let sel = selectedRange()
        let r = NSUnionRange(line(at: sel.location).range, line(at: max(sel.location, sel.upperBound - (sel.length > 0 ? 1 : 0))).range)
        let text = ns.substring(with: r)
        replace(NSRange(location: r.upperBound, length: 0), with: "\n" + text, select: NSRange(location: sel.location + r.length + 1, length: sel.length))
    }
}

// MARK: - Editor view controller

final class EditorController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    let styler = Styler()
    private(set) var textView: MarkdownTextView!
    let scrollView = NSScrollView()
    private let status = NSTextField(labelWithString: "")
    weak var undoSource: NSDocument?
    var onChange: () -> Void = {}
    var onScroll: (CGFloat) -> Void = { _ in }
    var onOutline: () -> Void = {}
    let formatBar = FormatBar.make()
    private var statusWork: DispatchWorkItem?

    override func loadView() {
        styler.fontSize = Settings.fontSize
        let storage = NSTextStorage()
        let lm = MDLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        lm.addTextContainer(container)
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        tv.styler = styler
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = Settings.spellCheck
        tv.selectedTextAttributes = [.backgroundColor: NSColor.selection]
        tv.smartInsertDeleteEnabled = false
        tv.backgroundColor = .paper
        tv.insertionPointColor = .accent
        tv.typingAttributes = [.font: styler.body, .foregroundColor: NSColor.ink]
        tv.delegate = self
        storage.delegate = self
        textView = tv

        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .paper
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 64, right: 0)   // room above the format bar
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.changed, object: nil)

        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .syntax
        status.alignment = .right

        // Floating outline button in the left margin, like Downright.
        let outline = OutlineGlyph(title: "", target: self, action: #selector(outlineClicked))
        outline.isBordered = false
        outline.toolTip = "Files & Outline  ⇧⌘O"
        outline.setAccessibilityLabel("Files and Outline")

        // Soft shadow under the title band, as in Downright.
        let shade = ShadeView()
        let statusPill = glass(status, cornerRadius: 10)
        formatBar.isHidden = !Settings.formatBar

        let root = NSView()
        for v in [scrollView, shade, statusPill, outline, formatBar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shade.topAnchor.constraint(equalTo: root.topAnchor),
            shade.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            shade.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shade.heightAnchor.constraint(equalToConstant: 14),
            statusPill.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            statusPill.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            status.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 10),
            status.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -10),
            status.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 4),
            status.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -4),
            outline.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            outline.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            outline.widthAnchor.constraint(equalToConstant: 30),
            outline.heightAnchor.constraint(equalToConstant: 30),
            formatBar.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            formatBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        root.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        view = root
    }

    var text: String { textView.string }

    /// Replaces the whole text (open / external reload). Not undoable, so undo history is cleared.
    func setText(_ s: String) {
        guard s != textView.string else { return }
        let sel = textView.selectedRange()
        let scroll = scrollView.contentView.bounds.origin
        textView.string = s
        undoSource?.undoManager?.removeAllActions()
        let len = (s as NSString).length
        textView.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        scrollView.contentView.scroll(to: scroll)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        onChange()
        updateStatus()
        updateReveal()
    }

    func jump(to loc: Int) {
        let r = NSRange(location: min(loc, (text as NSString).length), length: 0)
        textView.setSelectedRange(r)
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: tc)
            let y = max(0, rect.minY + textView.textContainerOrigin.y - 40)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(y, max(0, textView.frame.height - scrollView.contentView.bounds.height))))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        view.window?.makeFirstResponder(textView)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), textView?.hasMarkedText() != true else { return }
        styler.restyle(textStorage, edited: editedRange, delta: delta)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undoSource?.undoManager }

    func textDidChange(_ notification: Notification) { onChange(); scheduleStatus() }

    func textViewDidChangeSelection(_ notification: Notification) {
        scheduleStatus()
        // Reveal inline markers on the caret's lines; deferred so we never restyle mid-edit.
        DispatchQueue.main.async { [weak self] in self?.updateReveal() }
    }

    private func updateReveal() {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        guard sel.upperBound <= ns.length else { return }
        let lines = ns.lineRange(for: sel)
        let lm = textView.layoutManager as? MDLayoutManager
        if lm?.caretLine != lines { lm?.caretLine = lines; textView.needsDisplay = true }
        guard styler.wysiwyg, lines != styler.revealed else { return }
        let old = styler.revealed
        styler.revealed = lines
        let storage = textView.textStorage!
        if old.location != NSNotFound { styler.restyleLines(storage, old) }
        styler.restyleLines(storage, lines)
    }

    /// Document mode keeps the caret out of hidden block prefixes.
    func textView(_ tv: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
        guard styler.wysiwyg, new.length == 0, !tv.hasMarkedText() else { return new }
        let ns = tv.string as NSString
        guard new.location <= ns.length else { return new }
        let cur = textView.line(at: new.location)
        let start = cur.range.location
        let prefix = styler.inCode(start) ? 0 : Styler.prefixLength(cur.text)
        guard prefix > 0, new.location < start + prefix else { return new }
        if old.length == 0, old.location == start + prefix, new.location == old.location - 1, start > 0 {
            return NSRange(location: start - 1, length: 0)   // ← from content start goes to the previous line
        }
        return NSRange(location: start + prefix, length: 0)
    }

    func setWysiwyg(_ on: Bool) {
        guard styler.wysiwyg != on || textView.string.isEmpty else { return }
        styler.wysiwyg = on
        (textView.layoutManager as? MDLayoutManager)?.lineNumbers = !on && Settings.lineNumbers
        styler.revealed = NSRange(location: NSNotFound, length: 0)
        textView.typingAttributes[.font] = styler.body
        styler.restyleAll(textView.textStorage!)
        updateReveal()
        textView.setSelectedRange(textView.selectedRange())   // re-clamp the caret
    }

    private func scheduleStatus() {
        statusWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.updateStatus() }
        statusWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: w)
    }

    private func updateStatus() {
        let u = Array(textView.string.utf16)
        let cursor = min(textView.selectedRange().location, u.count)
        var words = 0, inWord = false, line = 1, lineStart = 0
        for (i, c) in u.enumerated() {
            let space = c == 32 || c == 10 || c == 9 || c == 13
            if !space && !inWord { words += 1 }
            inWord = !space
            if c == 10 && i < cursor { line += 1; lineStart = i + 1 }
        }
        let sel = textView.selectedRange().length
        status.stringValue = (sel > 0 ? "\(sel) selected · " : "") + "\(words) words · Ln \(line), Col \(cursor - lineStart + 1)"
    }

    @objc private func outlineClicked() { onOutline() }

    @objc private func scrolled() {
        let clip = scrollView.contentView
        let range = textView.frame.height - clip.bounds.height
        onScroll(range > 0 ? min(1, max(0, clip.bounds.minY / range)) : 0)
    }

    @objc private func settingsChanged() {
        (textView.layoutManager as? MDLayoutManager)?.lineNumbers = !styler.wysiwyg && Settings.lineNumbers
        textView.isContinuousSpellCheckingEnabled = Settings.spellCheck
        formatBar.isHidden = !Settings.formatBar
        textView.needsDisplay = true
        guard styler.fontSize != Settings.fontSize else { return }
        styler.fontSize = Settings.fontSize
        textView.typingAttributes[.font] = styler.body
        styler.restyleAll(textView.textStorage!)
        textView.setFrameSize(textView.frame.size)
    }
}

enum Settings {
    static let changed = Notification.Name("ParchlySettingsChanged")
    private static func post() { NotificationCenter.default.post(name: changed, object: nil) }

    static var fontSize: CGFloat {
        get { let v = UserDefaults.standard.double(forKey: "fontSize"); return v > 0 ? v : 16 }
        set { UserDefaults.standard.set(min(32, max(11, newValue)), forKey: "fontSize"); post() }
    }
    /// Line numbers in Source mode (off by default, like Downright's reading setup).
    static var lineNumbers: Bool {
        get { UserDefaults.standard.bool(forKey: "lineNumbers") }
        set { UserDefaults.standard.set(newValue, forKey: "lineNumbers"); post() }
    }
    /// Bear-style formatting bar at the bottom of the editor (on by default).
    static var formatBar: Bool {
        get { UserDefaults.standard.object(forKey: "formatBar") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "formatBar"); post() }
    }
    static var spellCheck: Bool {
        get { UserDefaults.standard.bool(forKey: "spellCheck") }
        set { UserDefaults.standard.set(newValue, forKey: "spellCheck"); post() }
    }
}

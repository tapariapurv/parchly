import AppKit

extension NSAttributedString.Key {
    static let mdBlock = NSAttributedString.Key("mdBlock")       // 1 code, 2 quote, 4 rule
    static let mdURL = NSAttributedString.Key("mdURL")
    static let mdHide = NSAttributedString.Key("mdHide")         // glyph not drawn, zero width
    static let mdBullet = NSAttributedString.Key("mdBullet")     // glyph replaced by • / ◦
    static let mdCheckbox = NSAttributedString.Key("mdCheckbox") // "[ ]" drawn as a box (Bool = checked)
    static let mdHeading = NSAttributedString.Key("mdHeading")   // heading level, for the margin badge
    static let mdTableRow = NSAttributedString.Key("mdTableRow") // 1 header, 2 separator, 3 body
    static let mdPipe = NSAttributedString.Key("mdPipe")
    static let mdInlineCode = NSAttributedString.Key("mdInlineCode")   // pill: 1 inline code, 2 ==highlight==
    static let mdImage = NSAttributedString.Key("mdImage")             // ImageBox drawn under its line
}

/// Live Markdown styling of the source text.
/// Document mode hides syntax (except inline markers on the caret's line); Source mode shows everything.
final class Styler {
    var fontSize: CGFloat = 16
    /// Folder of the open document, for drawing relative images inline.
    var baseURL: URL?
    private var images: [String: NSImage?] = [:]

    private static let setextRE = try! NSRegularExpression(pattern: #"^ {0,3}(=+|-+)[ \t]*$"#)
    private static let imageLineRE = try! NSRegularExpression(pattern: #"^\s*!\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)\s*$"#)
    private static let refDefRE = try! NSRegularExpression(pattern: #"^ {0,3}\[\^?[^\]]+\]:"#)
    private static let alertRE = try! NSRegularExpression(pattern: #"\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]"#, options: .caseInsensitive)
    private static let wikiRE = try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(\|[^\]]+)?\]\]"#)
    private static let mathRE = try! NSRegularExpression(pattern: #"\$\$[^$]+\$\$|(?<![\\$\w])\$(?=\S)[^$\n]+?(?<=\S)\$(?![\w$])"#)
    private static let footRE = try! NSRegularExpression(pattern: #"\[\^[^\]\s]+\]"#)
    private static let htmlRE = try! NSRegularExpression(pattern: #"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>"#)
    private static let markRE = try! NSRegularExpression(pattern: #"==(?=\S)([^=\n]+?)(?<=\S)=="#)

    /// Image for an inline `![](path)` line, scaled to the column (nil when it can't be read, e.g. no folder access).
    func image(_ path: String) -> NSImage? {
        if let cached = images[path] { return cached }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseURL.map { URL(fileURLWithPath: path.removingPercentEncoding ?? path, relativeTo: $0) }
        let img = url.flatMap { $0.isFileURL ? NSImage(contentsOf: $0) : nil }
        images[path] = img
        return img
    }
    var wysiwyg = true
    /// Whole lines holding the selection; their inline markers stay visible in Document mode.
    var revealed = NSRange(location: NSNotFound, length: 0)
    private(set) var code: [NSRange] = []

    private func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }
    var body: NSFont { wysiwyg ? serif(fontSize) : .monospacedSystemFont(ofSize: fontSize * 0.9, weight: .regular) }
    private var mono: NSFont { .monospacedSystemFont(ofSize: fontSize * 0.84, weight: .regular) }
    private var lineSpacing: CGFloat { fontSize * (wysiwyg ? 0.72 : 0.6) }

    private static let headingRE = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let quoteRE = try! NSRegularExpression(pattern: #"^ {0,3}>[ \t]?"#)
    private static let codeSpanRE = try! NSRegularExpression(pattern: #"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let linkRE = try! NSRegularExpression(pattern: #"!?\[([^\]\n]*)\]\(([^)\s]*)(?:[ \t]+"[^"\n]*")?\)"#)
    private static let urlRE = try! NSRegularExpression(pattern: #"<?\bhttps?://[^\s<>()]+[^\s<>().,;:!?'"]>?"#)
    private static let boldRE = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicRE = try! NSRegularExpression(pattern: #"(?<![*\w\\])\*(?=[^\s*])(.+?)(?<=[^\s*\\])\*(?![*\w])|(?<![_\w\\])_(?=[^\s_])(.+?)(?<=[^\s_\\])_(?![_\w])"#)
    private static let strikeRE = try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#)

    /// Length of the block prefix ("## ", "- [ ] ", "> ", "3. ") that Document mode hides or draws itself.
    static func prefixLength(_ line: String) -> Int {
        if let m = headingRE.firstMatch(in: line, range: MD.full(line)) { return m.range.length }
        return MD.parse(line)?.length ?? 0
    }

    /// Call from `textStorage(_:didProcessEditing:...)` (willProcess would widen the edited range and drag the caret along). Restyles the edited block unless fence structure changed.
    func restyle(_ s: NSTextStorage, edited: NSRange, delta: Int) {
        let ns = s.string as NSString
        let oldEnd = edited.upperBound - delta
        let predicted = code.map { r -> NSRange in
            if r.upperBound <= edited.location { return r }
            if r.location >= oldEnd { return NSRange(location: r.location + delta, length: r.length) }
            return NSRange(location: r.location, length: r.length + delta)
        }
        // An insertion can only change fences on a line that is, or was, a fence line,
        // so ordinary typing skips rescanning the whole document.
        var fenceSafe = false
        if delta > 0, edited.length < 4096 {
            let lines = ns.lineRange(for: edited)
            let touchesBoundary = predicted.contains { NSLocationInRange($0.location, lines) || NSLocationInRange(max($0.location, $0.upperBound - 1), lines) }
            fenceSafe = !touchesBoundary && MD.fenceRE.firstMatch(in: ns as String, range: lines) == nil
        }
        let newCode = fenceSafe ? predicted : MD.codeBlocks(ns)
        let structural = predicted != newCode
        code = newCode
        style(s, range: structural ? NSRange(location: 0, length: ns.length) : block(around: edited, in: ns))
    }

    func restyleAll(_ s: NSTextStorage) {
        code = MD.codeBlocks(s.string as NSString)
        s.beginEditing()
        style(s, range: NSRange(location: 0, length: s.length))
        s.endEditing()
    }

    /// Restyle just these lines (caret moved to another line).
    func restyleLines(_ s: NSTextStorage, _ r: NSRange) {
        guard r.location != NSNotFound, r.location <= s.length else { return }
        let clamped = NSRange(location: r.location, length: min(r.length, s.length - r.location))
        s.beginEditing()
        style(s, range: block(around: clamped, in: s.string as NSString))
        s.endEditing()
    }

    func inCode(_ loc: Int) -> Bool { code.contains { NSLocationInRange(loc, $0) } }

    /// Lines expanded to blank-line boundaries (tables need their header/separator context).
    private func block(around r: NSRange, in ns: NSString) -> NSRange {
        var lines = ns.lineRange(for: r)
        func blank(_ lr: NSRange) -> Bool { ns.substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        while lines.location > 0 {
            let prev = ns.lineRange(for: NSRange(location: lines.location - 1, length: 0))
            if blank(prev) { break }
            lines = NSUnionRange(prev, lines)
        }
        while lines.upperBound < ns.length {
            let next = ns.lineRange(for: NSRange(location: lines.upperBound, length: 0))
            if blank(next) { break }
            lines = NSUnionRange(lines, next)
        }
        return lines
    }

    private func style(_ s: NSTextStorage, range: NSRange) {
        let ns = s.string as NSString
        guard ns.length > 0 else { return }
        var lines: [(full: NSRange, content: NSRange)] = []
        var loc = range.location
        repeat {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
            lines.append((NSRange(location: start, length: end - start), NSRange(location: start, length: contentsEnd - start)))
            loc = end
        } while loc < range.upperBound && loc < ns.length

        var table = Array(repeating: 0, count: lines.count)   // 0 none, 1 header, 2 separator, 3 body
        var i = 0
        while i < lines.count {
            var j = i
            while j < lines.count, !inCode(lines[j].content.location), ns.substring(with: lines[j].content).contains("|") { j += 1 }
            if j - i >= 2, MD.isSeparator(ns.substring(with: lines[i + 1].content)) {
                for k in i..<j { table[k] = k == i ? 1 : (k == i + 1 ? 2 : 3) }
            }
            i = max(j, i + 1)
        }
        // Document mode lays table cells on shared tab stops so columns align whatever the source spacing.
        var stops = Array(repeating: [CGFloat](), count: lines.count)
        if wysiwyg {
            var k = 0
            while k < lines.count {
                guard table[k] == 1 else { k += 1; continue }
                var end = k
                while end < lines.count, table[end] > 0, end == k || table[end] != 1 { end += 1 }
                var widths: [CGFloat] = []
                for row in k..<end where table[row] != 2 {
                    let font = table[row] == 1 ? serif(fontSize, .semibold) : body
                    for (c, cell) in MD.cells(ns.substring(with: lines[row].content)).enumerated() {
                        let w = (cell as NSString).size(withAttributes: [.font: font]).width
                        if c < widths.count { widths[c] = max(widths[c], w) } else { widths.append(w) }
                    }
                }
                let gap = fontSize * 0.75
                var x = gap, columnStops = [x]
                for w in widths { x += w + 2 * gap; columnStops.append(x) }
                for row in k..<end { stops[row] = columnStops }
                k = end
            }
        }
        // Setext headings: a paragraph line underlined with === or ---.
        var setext = Array(repeating: 0, count: lines.count)
        for k in 1..<max(1, lines.count) where table[k] == 0 && !inCode(lines[k].content.location) {
            let t = ns.substring(with: lines[k].content), prev = ns.substring(with: lines[k - 1].content)
            guard let m = Self.setextRE.firstMatch(in: t, range: MD.full(t)), !prev.trimmingCharacters(in: .whitespaces).isEmpty,
                  setext[k - 1] == 0, table[k - 1] == 0, !inCode(lines[k - 1].content.location), MD.parse(prev) == nil,
                  Self.headingRE.firstMatch(in: prev, range: MD.full(prev)) == nil, !MD.isHR(prev) else { continue }
            setext[k - 1] = (t as NSString).substring(with: m.range(at: 1)).hasPrefix("=") ? 1 : 2
            setext[k] = -1
        }
        for (k, line) in lines.enumerated() { styleLine(s, ns, line.full, line.content, table: table[k], stops: stops[k], setext: setext[k]) }
        // We run after NSTextStorage's own fixing pass, so do font fallback (e.g. ⌘ in New York) ourselves.
        s.fixAttributes(in: NSRange(location: lines[0].full.location, length: lines[lines.count - 1].full.upperBound - lines[0].full.location))
    }

    private func paragraph(_ configure: (NSMutableParagraphStyle) -> Void = { _ in }) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.defaultTabInterval = fontSize * 2
        p.tabStops = []
        configure(p)
        return p
    }

    private func styleLine(_ s: NSTextStorage, _ ns: NSString, _ full: NSRange, _ r: NSRange, table: Int, stops: [CGFloat] = [], setext: Int = 0) {
        s.setAttributes([.font: body, .foregroundColor: NSColor.ink, .paragraphStyle: paragraph()], range: full)
        let text = ns.substring(with: r)
        let doc = wysiwyg
        let reveal = !doc || NSIntersectionRange(full, revealed).length > 0 || full.location == revealed.location
        let pad = fontSize * 0.9
        func hide(_ x: NSRange) { if doc { s.addAttribute(.mdHide, value: true, range: x) } else { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: x) } }

        if doc, !reveal, !inCode(r.location), text.trimmingCharacters(in: .whitespaces).isEmpty {
            // Blank lines read as paragraph spacing, like a rendered page.
            s.addAttributes([.font: NSFont.systemFont(ofSize: fontSize * 0.45), .paragraphStyle: paragraph { $0.lineSpacing = 0; $0.maximumLineHeight = self.fontSize * 0.95 }], range: full)
            return
        }
        if inCode(r.location) {
            s.addAttributes([.font: mono, .mdBlock: 1, .paragraphStyle: paragraph { $0.firstLineHeadIndent = pad; $0.headIndent = pad; $0.tailIndent = -pad; $0.lineSpacing = self.fontSize * 0.32 }], range: full)
            if MD.fenceRE.firstMatch(in: text, range: MD.full(text)) != nil {
                s.addAttribute(.foregroundColor, value: NSColor.syntax, range: r)
            } else {
                for (t, kind) in Highlighter.tokens(in: ns, range: r) { s.addAttribute(.foregroundColor, value: NSColor.code(kind.rawValue), range: t) }
            }
            return
        }
        if setext == -1 {   // the === / --- underline
            if doc && !reveal {
                s.addAttributes([.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: paragraph { $0.lineSpacing = 0; $0.maximumLineHeight = 2 }], range: full)
                s.addAttribute(.mdHide, value: true, range: r)
            } else { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: r) }
            return
        }
        if setext > 0 || Self.headingRE.firstMatch(in: text, range: MD.full(text)) != nil {
            let m = Self.headingRE.firstMatch(in: text, range: MD.full(text))
            let level = m?.range(at: 1).length ?? setext
            let prefixLen = m?.range.length ?? 0
            let scale: [CGFloat] = [2.0, 1.56, 1.25, 1.1, 1, 1]
            let size = fontSize * scale[level - 1]
            if doc {
                s.addAttributes([.font: serif(size, .bold), .foregroundColor: NSColor.heading, .mdHeading: level, .paragraphStyle: paragraph { $0.paragraphSpacingBefore = self.fontSize * (level <= 2 ? 1.6 : 0.9); $0.paragraphSpacing = self.fontSize * 0.2 }], range: full)
            }
            if level == 6 { s.addAttribute(.foregroundColor, value: NSColor.inkSecondary, range: r) }
            hide(NSRange(location: r.location, length: prefixLen))
            inline(s, ns, NSRange(location: r.location + prefixLen, length: r.length - prefixLen), reveal: reveal)
            return
        }
        if Self.refDefRE.firstMatch(in: text, range: MD.full(text)) != nil, !text.hasPrefix("[^") {
            s.addAttributes([.foregroundColor: NSColor.syntax, .font: mono], range: r)   // [id]: url reference definition
            return
        }
        if doc, let m = Self.imageLineRE.firstMatch(in: text, range: MD.full(text)), let img = image((text as NSString).substring(with: m.range(at: 1))) {
            let maxW = fontSize * 34, scale = min(1, maxW / max(1, img.size.width), 420 / max(1, img.size.height))
            let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
            s.addAttributes([.mdImage: ImageBox(image: img, size: size), .paragraphStyle: paragraph { $0.paragraphSpacing = size.height + 14 }], range: full)
            if !reveal { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: r) }
            inline(s, ns, r, reveal: reveal)
            return
        }
        if MD.isHR(text) {
            if doc { s.addAttributes([.mdHide: true, .mdBlock: 4], range: r) } else { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: r) }
            return
        }
        if table > 0 {
            s.addAttribute(.mdTableRow, value: table, range: full)
            if !doc {
                s.addAttribute(.font, value: table == 1 ? NSFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .semibold) : body, range: full)
                if table == 2 { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: r); return }
                inline(s, ns, r, reveal: true)
                for (i, ch) in text.utf16.enumerated() where ch == 124 { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: NSRange(location: r.location + i, length: 1)) }
                return
            }
            if table == 2, !reveal {
                s.addAttributes([.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: paragraph { $0.lineSpacing = 0; $0.maximumLineHeight = 2 }], range: full)
                s.addAttribute(.mdHide, value: true, range: r)   // keep the newline, or the next row merges in
                return
            }
            s.addAttributes([.font: table == 1 ? serif(fontSize, .semibold) : body, .paragraphStyle: paragraph {
                $0.tabStops = stops.map { NSTextTab(textAlignment: .left, location: $0) }
                $0.lineSpacing = self.fontSize * 0.45
                $0.paragraphSpacingBefore = self.fontSize * 0.2
            }], range: full)
            if table == 2 { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: r) }
            inline(s, ns, r, reveal: reveal)
            // Unescaped pipes become tabs; the padding around them collapses.
            let u = Array(text.utf16)
            var i = 0
            while i < u.count {
                if u[i] == 92 { i += 2; continue }
                if u[i] == 124 {
                    s.addAttribute(.mdPipe, value: true, range: NSRange(location: r.location + i, length: 1))
                    var a = i - 1
                    while a >= 0, u[a] == 32 || u[a] == 9 { s.addAttribute(.mdHide, value: true, range: NSRange(location: r.location + a, length: 1)); a -= 1 }
                    var b = i + 1
                    while b < u.count, u[b] == 32 || u[b] == 9 { s.addAttribute(.mdHide, value: true, range: NSRange(location: r.location + b, length: 1)); b += 1 }
                    i = b; continue
                }
                i += 1
            }
            return
        }
        if let m = Self.quoteRE.firstMatch(in: text, range: MD.full(text)) {
            s.addAttributes([.mdBlock: 2, .paragraphStyle: paragraph { $0.firstLineHeadIndent = pad; $0.headIndent = pad }], range: full)
            hide(NSRange(location: r.location, length: m.range.length))
            if let a = Self.alertRE.firstMatch(in: text, range: MD.full(text)) {   // GitHub alert title
                s.addAttributes([.font: NSFont.systemFont(ofSize: fontSize * 0.88, weight: .semibold), .foregroundColor: NSColor.accent], range: NSRange(location: r.location + a.range.location, length: a.range.length))
                return
            }
            inline(s, ns, NSRange(location: r.location + m.range.length, length: r.length - m.range.length), reveal: reveal)
            return
        }
        if let p = MD.parse(text) {
            let indentLen = (p.indent as NSString).length
            let markerRange = NSRange(location: r.location + indentLen, length: (p.marker as NSString).length)
            let prefix = NSRange(location: r.location, length: p.length)
            var visible = ns.substring(with: prefix)
            s.addAttribute(.foregroundColor, value: NSColor.marker, range: prefix)
            if p.task != nil {
                let boxAt = (text as NSString).range(of: "[", range: NSRange(location: indentLen, length: p.length - indentLen)).location
                let box = NSRange(location: r.location + boxAt, length: 3)
                if doc {
                    hide(NSRange(location: markerRange.location, length: box.location - markerRange.location))
                    s.addAttributes([.mdCheckbox: p.task!, .foregroundColor: NSColor.clear, .kern: fontSize * 0.55], range: box)
                    s.addAttribute(.mdHide, value: true, range: NSRange(location: box.location + 1, length: 1))
                    visible = p.indent + "[ ] "
                } else {
                    s.addAttribute(.foregroundColor, value: NSColor.accent, range: prefix)
                }
                if p.task == true {
                    let rest = NSRange(location: prefix.upperBound, length: r.length - p.length)
                    s.addAttributes([.foregroundColor: NSColor.inkSecondary, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: rest)
                }
            } else if p.number != nil, doc {
                // Downright sets list numbers in small grey sans-serif.
                s.addAttributes([.font: NSFont.systemFont(ofSize: fontSize * 0.88), .kern: fontSize * 0.2], range: markerRange)
                visible = p.indent + p.marker + "  "
            } else if p.number == nil, doc {
                s.addAttribute(.mdBullet, value: MD.width(p.indent) / 4, range: markerRange)
                visible = p.indent + "•  "
                s.addAttribute(.kern, value: fontSize * 0.25, range: markerRange)
            }
            let markerFont = p.number != nil && doc ? NSFont.systemFont(ofSize: fontSize * 0.88) : body
            let hang = (visible as NSString).size(withAttributes: [.font: markerFont]).width + (p.task == nil && doc ? fontSize * 0.2 : 0)
            s.addAttribute(.paragraphStyle, value: paragraph { $0.headIndent = hang; $0.paragraphSpacingBefore = self.fontSize * 0.28 }, range: full)
            inline(s, ns, NSRange(location: prefix.upperBound, length: r.length - p.length), reveal: reveal)
            return
        }
        inline(s, ns, r, reveal: reveal)
    }

    private func inline(_ s: NSTextStorage, _ ns: NSString, _ r: NSRange, reveal: Bool) {
        guard r.length > 0 else { return }
        let str = ns as String
        var taken: [NSRange] = []
        func free(_ x: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, x).length > 0 } }
        func marker(_ x: NSRange) {
            if reveal { s.addAttribute(.foregroundColor, value: NSColor.syntax, range: x) } else { s.addAttribute(.mdHide, value: true, range: x) }
        }

        for m in Self.mathRE.matches(in: str, range: r) {   // $math$
            s.addAttributes([.font: mono, .foregroundColor: NSColor.accent], range: m.range)
            taken.append(m.range)
        }
        for m in Self.codeSpanRE.matches(in: str, range: r) where free(m.range) {
            let ticks = m.range(at: 1).length
            s.addAttributes([.font: mono, .mdInlineCode: 1], range: m.range)
            marker(NSRange(location: m.range.location, length: ticks))
            marker(NSRange(location: m.range.upperBound - ticks, length: ticks))
            taken.append(m.range)
        }
        for m in Self.wikiRE.matches(in: str, range: r) where free(m.range) {   // [[Note]], [[Note|Label]], [[Note#Heading]]
            let target = ns.substring(with: m.range(at: 1))
            let hasLabel = m.range(at: 2).location != NSNotFound
            let shown = hasLabel ? NSRange(location: m.range(at: 2).location + 1, length: m.range(at: 2).length - 1) : m.range(at: 1)
            marker(NSRange(location: m.range.location, length: shown.location - m.range.location))
            marker(NSRange(location: shown.upperBound, length: m.range.upperBound - shown.upperBound))
            s.addAttributes([.foregroundColor: NSColor.link, .mdURL: "wiki:" + target], range: shown)
            if !reveal { s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue, range: shown) }
            taken.append(m.range)
        }
        for m in Self.footRE.matches(in: str, range: r) where free(m.range) {   // [^1] footnote reference
            s.addAttributes([.font: NSFont.systemFont(ofSize: fontSize * 0.7, weight: .medium), .baselineOffset: fontSize * 0.35, .foregroundColor: NSColor.accent], range: m.range)
            taken.append(m.range)
        }
        for m in Self.htmlRE.matches(in: str, range: r) where free(m.range) {   // inline HTML tags
            s.addAttributes([.foregroundColor: NSColor.syntax, .font: mono], range: m.range)
            taken.append(m.range)
        }
        for m in Self.linkRE.matches(in: str, range: r) where free(m.range) {
            let label = m.range(at: 1), url = m.range(at: 2)
            marker(NSRange(location: m.range.location, length: label.location - m.range.location))
            marker(NSRange(location: label.upperBound, length: m.range.upperBound - label.upperBound))
            s.addAttributes([.foregroundColor: NSColor.link, .mdURL: ns.substring(with: url)], range: label)
            if !reveal { s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: label) }
            taken.append(NSRange(location: label.upperBound, length: m.range.upperBound - label.upperBound))
        }
        for m in Self.urlRE.matches(in: str, range: r) where free(m.range) {
            let link = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            s.addAttributes([.foregroundColor: NSColor.link, .mdURL: link], range: m.range)
            taken.append(m.range)
        }
        for m in Self.boldRE.matches(in: str, range: r) where free(m.range) {
            s.applyFontTraits(.boldFontMask, range: m.range)
            marker(NSRange(location: m.range.location, length: 2))
            marker(NSRange(location: m.range.upperBound - 2, length: 2))
        }
        for m in Self.italicRE.matches(in: str, range: r) where free(m.range) {
            s.applyFontTraits(.italicFontMask, range: m.range)
            marker(NSRange(location: m.range.location, length: 1))
            marker(NSRange(location: m.range.upperBound - 1, length: 1))
        }
        for m in Self.strikeRE.matches(in: str, range: r) where free(m.range) {
            s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.inkSecondary], range: m.range)
            marker(NSRange(location: m.range.location, length: 2))
            marker(NSRange(location: m.range.upperBound - 2, length: 2))
        }
        for m in Self.markRE.matches(in: str, range: r) where free(m.range) {   // ==highlight==
            s.addAttribute(.mdInlineCode, value: 2, range: m.range(at: 1))
            marker(NSRange(location: m.range.location, length: 2))
            marker(NSRange(location: m.range.upperBound - 2, length: 2))
        }
    }
}

/// Hides syntax glyphs, swaps bullets, and draws code backgrounds, quote bars, rules, checkboxes, table grids and the heading badge.
final class MDLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// Line holding the caret; a heading there gets an "H1" badge in the margin (Document mode).
    var caretLine: NSRange?
    /// Source mode draws line numbers just left of the text column.
    var lineNumbers = false

    private func fontSize(at i: Int) -> CGFloat { (textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont)?.pointSize ?? 16 }

    override init() { super.init(); delegate = self }
    required init?(coder: NSCoder) { fatalError() }

    func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let s = textStorage else { return 0 }
        var newProps: [NSLayoutManager.GlyphProperty]?
        var newGlyphs: [CGGlyph]?
        for i in 0..<range.length {
            let c = characterIndexes[i]
            guard c < s.length else { continue }
            if s.attribute(.mdHide, at: c, effectiveRange: nil) != nil || s.attribute(.mdPipe, at: c, effectiveRange: nil) != nil {
                if newProps == nil { newProps = Array(UnsafeBufferPointer(start: props, count: range.length)) }
                newProps![i] = .controlCharacter
            } else if let depth = s.attribute(.mdBullet, at: c, effectiveRange: nil) as? Int {
                if newGlyphs == nil { newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: range.length)) }
                var ch: UniChar = depth % 2 == 0 ? 0x2022 : 0x25E6
                var g = CGGlyph()
                if CTFontGetGlyphsForCharacters(font, &ch, &g, 1) { newGlyphs![i] = g }
            }
        }
        guard newProps != nil || newGlyphs != nil else { return 0 }
        let p = newProps ?? Array(UnsafeBufferPointer(start: props, count: range.length))
        let g = newGlyphs ?? Array(UnsafeBufferPointer(start: glyphs, count: range.length))
        setGlyphs(g, properties: p, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
        return range.length
    }

    /// Hidden syntax is laid out as zero-width control glyphs (null glyphs would detach from their line).
    func layoutManager(_ lm: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if textStorage?.attribute(.mdPipe, at: charIndex, effectiveRange: nil) != nil { return .horizontalTab }
        return textStorage?.attribute(.mdHide, at: charIndex, effectiveRange: nil) != nil ? .zeroAdvancement : action
    }

    // ponytail: counts newlines from the top on each draw; cache line starts if huge files feel slow.
    private func drawLineNumbers(_ glyphs: NSRange, _ origin: NSPoint) {
        guard let s = textStorage else { return }
        let ns = s.string as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.syntax]
        var counted = 0, line = 1
        enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, g, _ in
            let c = self.characterRange(forGlyphRange: g, actualGlyphRange: nil).location
            while counted < c { if ns.character(at: counted) == 10 { line += 1 }; counted += 1 }
            let label = (c == 0 || ns.character(at: c - 1) == 10 ? "\(line)" : "↳") as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: origin.x - size.width - 14, y: origin.y + used.minY + 2), withAttributes: attrs)
        }
    }

    private func rect(_ chars: NSRange, _ origin: NSPoint) -> NSRect {
        var r = NSRect.null
        enumerateLineFragments(forGlyphRange: glyphRange(forCharacterRange: chars, actualCharacterRange: nil)) { f, _, _, _, _ in r = r.union(f) }
        return r.offsetBy(dx: origin.x, dy: origin.y)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let s = textStorage, s.length > 0, let tc = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let all = NSRange(location: 0, length: s.length)
        let end = min(chars.upperBound, s.length)

        var i = chars.location
        while i < end {
            var eff = NSRange()
            // Search only the visible span; widen to the whole block only when one is actually there.
            if s.attribute(.mdBlock, at: i, longestEffectiveRange: &eff, in: NSRange(location: i, length: end - i)) != nil,
               let kind = s.attribute(.mdBlock, at: i, longestEffectiveRange: &eff, in: all) as? Int {
                let r = rect(eff, origin)
                switch kind {
                case 1:
                    NSColor.codeFill.setFill()
                    NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
                case 2:
                    NSColor.quoteBar.setFill()
                    let lead = (s.attribute(.paragraphStyle, at: eff.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
                    NSBezierPath(roundedRect: NSRect(x: r.minX + 5, y: r.minY, width: 3, height: r.height - lead), xRadius: 1.5, yRadius: 1.5).fill()
                default:
                    NSColor.rule.setFill()
                    NSRect(x: r.minX + 5, y: r.midY.rounded(), width: r.width - 10, height: 1).fill()
                }
            }
            i = max(eff.upperBound, i + 1)
        }

        // Table grid: hairlines at pipe positions and between rows.
        i = chars.location
        while i < end {
            var eff = NSRange()
            if s.attribute(.mdTableRow, at: i, longestEffectiveRange: &eff, in: NSRange(location: i, length: end - i)) != nil {
                enumerateLineFragments(forGlyphRange: glyphRange(forCharacterRange: eff, actualCharacterRange: nil)) { frag, _, _, glyphs, _ in
                    let lineChars = self.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                    guard let row = s.attribute(.mdTableRow, at: lineChars.location, effectiveRange: nil) as? Int else { return }
                    let stops = (s.attribute(.paragraphStyle, at: lineChars.location, effectiveRange: nil) as? NSParagraphStyle)?.tabStops ?? []
                    guard let gap = stops.first?.location else { return }
                    let xs = stops.map { (origin.x + tc.lineFragmentPadding + $0.location - gap).rounded() }
                    guard let minX = xs.first, let maxX = xs.last, xs.count >= 2 else { return }
                    let f = frag.offsetBy(dx: origin.x, dy: origin.y)
                    if row == 1 {
                        NSColor.codeFill.setFill()
                        NSRect(x: minX, y: f.minY, width: maxX - minX, height: f.height).fill()
                    }
                    NSColor.rule.setFill()
                    for x in xs { NSRect(x: x.rounded(), y: f.minY, width: 1, height: f.height).fill() }
                    if row == 1 { NSRect(x: minX, y: f.minY, width: maxX - minX + 1, height: 1).fill() }
                    NSRect(x: minX, y: f.maxY - 1, width: maxX - minX + 1, height: 1).fill()
                }
            }
            i = max(eff.upperBound, i + 1)
        }

        // Inline images, drawn in the paragraph spacing reserved under their line.
        i = chars.location
        while i < end {
            var eff = NSRange()
            if let box = s.attribute(.mdImage, at: i, longestEffectiveRange: &eff, in: NSRange(location: i, length: end - i)) as? ImageBox {
                let g = glyphRange(forCharacterRange: eff, actualCharacterRange: nil)
                if g.length > 0 {
                    let used = lineFragmentUsedRect(forGlyphAt: NSMaxRange(g) - 1, effectiveRange: nil)
                    let rect = NSRect(x: origin.x + tc.lineFragmentPadding, y: origin.y + used.maxY + 4, width: box.size.width, height: box.size.height)
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
                    box.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            i = max(eff.upperBound, i + 1)
        }

        // Inline code pills (a backgroundColor would fill the whole line height, line spacing included).
        i = chars.location
        while i < end {
            var eff = NSRange()
            if let kind = s.attribute(.mdInlineCode, at: i, longestEffectiveRange: &eff, in: NSRange(location: i, length: end - i)) as? Int {
                let lead = (s.attribute(.paragraphStyle, at: eff.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
                enumerateEnclosingRects(forGlyphRange: glyphRange(forCharacterRange: eff, actualCharacterRange: nil), withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { r, _ in
                    let pill = NSRect(x: r.minX - 3, y: r.minY + 1, width: r.width + 6, height: r.height - lead - 1).offsetBy(dx: origin.x, dy: origin.y)
                    (kind == 2 ? NSColor.systemYellow.withAlphaComponent(0.35) : NSColor.inlineCodeFill).setFill()
                    NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
                    guard kind == 1 else { return }
                    NSColor.rule.withAlphaComponent(0.6).setStroke()
                    NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
                }
            }
            i = max(eff.upperBound, i + 1)
        }

        // Checkboxes.
        i = chars.location
        while i < end {
            var eff = NSRange()
            if let checked = s.attribute(.mdCheckbox, at: i, longestEffectiveRange: &eff, in: NSRange(location: i, length: end - i)) as? Bool {
                let g = boundingRect(forGlyphRange: glyphRange(forCharacterRange: eff, actualCharacterRange: nil), in: tc).offsetBy(dx: origin.x, dy: origin.y)
                let lead = (s.attribute(.paragraphStyle, at: eff.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
                let side = min(g.width - 8, fontSize(at: eff.location) * 1.3).rounded()
                let box = NSRect(x: g.minX + 1, y: (g.minY + (g.height - lead - side) / 2).rounded(), width: side, height: side)
                let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: side * 0.26, yRadius: side * 0.26)
                if checked {
                    NSColor.accent.withAlphaComponent(0.14).setFill(); path.fill()
                    path.lineWidth = 1.6
                    NSColor.accent.withAlphaComponent(0.55).setStroke(); path.stroke()
                    let tick = NSBezierPath()
                    tick.move(to: NSPoint(x: box.minX + side * 0.26, y: box.minY + side * 0.52))
                    tick.line(to: NSPoint(x: box.minX + side * 0.43, y: box.minY + side * 0.7))
                    tick.line(to: NSPoint(x: box.minX + side * 0.76, y: box.minY + side * 0.3))
                    tick.lineWidth = max(1.5, side * 0.12); tick.lineCapStyle = .round; tick.lineJoinStyle = .round
                    NSColor.accent.setStroke(); tick.stroke()
                } else {
                    path.lineWidth = 1.6
                    NSColor.marker.withAlphaComponent(0.7).setStroke(); path.stroke()
                }
            }
            i = max(eff.upperBound, i + 1)
        }

    }

    /// Margin decorations (line numbers, heading badge) sit outside the text container, which NSTextView
    /// clips layout drawing to, so MarkdownTextView calls this from its own background pass.
    func drawMargins(_ glyphsToShow: NSRange, at origin: NSPoint) {
        guard let s = textStorage, s.length > 0 else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        if lineNumbers { drawLineNumbers(glyphsToShow, origin) }

        // Heading level badge beside the caret's heading.
        if let line = caretLine, line.location < s.length, NSIntersectionRange(line, chars).length > 0 || NSLocationInRange(line.location, chars),
           let level = s.attribute(.mdHeading, at: line.location, effectiveRange: nil) as? Int {
            let glyphs = glyphRange(forCharacterRange: NSRange(location: line.location, length: max(1, min(line.length, s.length - line.location))), actualCharacterRange: nil)
            var used = NSRect.zero, frag = NSRect.zero
            if glyphs.length > 0 {
                frag = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                used = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let lead = (s.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
                let label = "H\(level)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.inkSecondary]
                let size = label.size(withAttributes: attrs)
                let badge = NSRect(x: origin.x + frag.minX - size.width - 22, y: origin.y + used.minY + (used.height - lead - 18) / 2 + 2, width: size.width + 10, height: 18)
                NSColor.codeFill.setFill()
                NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
                label.draw(at: NSPoint(x: badge.minX + 5, y: badge.minY + (18 - size.height) / 2), withAttributes: attrs)
            }
        }
    }
}

final class ImageBox: NSObject {
    let image: NSImage, size: NSSize
    init(image: NSImage, size: NSSize) { self.image = image; self.size = size }
}

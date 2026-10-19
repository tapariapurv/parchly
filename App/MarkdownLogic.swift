import Foundation

/// Pure, line-level Markdown rules (no AppKit) so Tests/main.swift can exercise them directly.
/// All offsets are UTF-16, matching NSString / NSTextView.
enum MD {
    struct Prefix {
        var indent: String
        var marker: String   // "-", "*", "+", "3.", "3)" or ">"
        var task: Bool?      // nil: not a task item
        var length: Int      // whole prefix incl. trailing spaces
        var isQuote: Bool { marker == ">" }
        var number: Int? { isQuote ? nil : Int(marker.dropLast()) }
    }

    private static let prefixRE = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+]|\d{1,9}[.)])(?:[ \t]+(\[[ xX]\](?:[ \t]+|$))?|$)|(>)[ \t]?)"#)
    private static let hrRE = try! NSRegularExpression(pattern: #"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let headingStripRE = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}(?:[ \t]+|$)"#)
    private static let separatorRE = try! NSRegularExpression(pattern: #"^\s*\|?(?:\s*:?-+:?\s*\|)*\s*:?-+:?\s*\|?\s*$"#)
    static let fenceRE = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})"#, options: .anchorsMatchLines)
    static let headingRE = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$"#, options: .anchorsMatchLines)

    static func full(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    static func isHR(_ line: String) -> Bool { hrRE.firstMatch(in: line, range: full(line)) != nil }

    static func parse(_ line: String) -> Prefix? {
        guard !isHR(line), let m = prefixRE.firstMatch(in: line, range: full(line)) else { return nil }
        let ns = line as NSString
        func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        let marker = group(2) ?? group(4)!
        let task = group(3).map { $0.lowercased().hasPrefix("[x") }
        return Prefix(indent: group(1)!, marker: marker, task: task, length: m.range.length)
    }

    static func leadingWhitespace(_ line: String) -> String { String(line.prefix { $0 == " " || $0 == "\t" }) }
    static func width(_ indent: String) -> Int { indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
    static func indent(_ line: String) -> String { "    " + line }
    static func outdent(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        return String(line.dropFirst(min(4, line.prefix { $0 == " " }.count)))
    }

    // MARK: Return

    enum ReturnEdit: Equatable { case insert(String), replaceLine(String) }

    /// What pressing Return at `cursor` (offset within `line`, which excludes the newline) should do.
    static func returnEdit(line: String, cursor: Int) -> ReturnEdit {
        let ns = line as NSString
        guard let p = parse(line), cursor >= p.length else {
            let lead = leadingWhitespace(line) as NSString
            return .insert("\n" + lead.substring(to: min(cursor, lead.length)))
        }
        if ns.substring(from: p.length).trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: step out of the list (outdent first if nested).
            return .replaceLine(p.indent.isEmpty || p.isQuote ? "" : outdent(line))
        }
        if p.isQuote { return .insert("\n" + p.indent + "> ") }
        let marker = p.number.map { "\($0 + 1)\(p.marker.last!)" } ?? p.marker
        return .insert("\n" + p.indent + marker + " " + (p.task != nil ? "[ ] " : ""))
    }

    // MARK: Ordered list numbering

    /// Lines around `index` that belong to the same list (stops at an unindented non-list paragraph).
    static func inList(_ l: String) -> Bool {
        l.trimmingCharacters(in: .whitespaces).isEmpty || l.first == " " || l.first == "\t" || (parse(l).map { !$0.isQuote } ?? false)
    }

    static func listRegion(_ lines: [String], around index: Int) -> Range<Int> {
        var lo = index, hi = index
        while lo > 0, inList(lines[lo - 1]) { lo -= 1 }
        while hi < lines.count - 1, inList(lines[hi + 1]) { hi += 1 }
        return lo..<(hi + 1)
    }

    /// Renumbers ordered items per indent level, keeping each list's starting number.
    static func renumbered(_ lines: [String]) -> [String] {
        var levels: [(width: Int, next: Int)] = []
        return lines.map { line in
            guard let p = parse(line), !p.isQuote else {
                if let f = line.first, !f.isWhitespace { levels.removeAll() }
                return line
            }
            let w = width(p.indent)
            levels.removeAll { $0.width > w }
            guard let n = p.number else { levels.removeAll { $0.width == w }; return line }
            guard let i = levels.firstIndex(where: { $0.width == w }) else { levels.append((w, n + 1)); return line }
            let want = levels[i].next
            levels[i].next += 1
            guard want != n else { return line }
            let digits = NSRange(location: (p.indent as NSString).length, length: (p.marker as NSString).length - 1)
            return (line as NSString).replacingCharacters(in: digits, with: String(want))
        }
    }

    // MARK: Block toggles

    static func setHeading(_ line: String, level: Int) -> String {
        let m = headingStripRE.firstMatch(in: line, range: full(line))
        let current = m.map { (line as NSString).substring(with: $0.range).filter { $0 == "#" }.count } ?? 0
        let body = m.map { (line as NSString).substring(from: $0.range.length) } ?? line
        let target = current == level ? 0 : level
        return target == 0 ? body : String(repeating: "#", count: target) + " " + body
    }

    enum ListKind { case bullet, ordered, task }

    static func toggleList(_ lines: [String], _ kind: ListKind) -> [String] {
        func has(_ p: Prefix?) -> Bool {
            guard let p, !p.isQuote else { return false }
            switch kind {
            case .bullet: return p.number == nil && p.task == nil
            case .ordered: return p.number != nil
            case .task: return p.task != nil
            }
        }
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = !content.isEmpty && content.allSatisfy { has(parse($0)) }
        var n = 0
        return lines.map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let p = parse(line).flatMap { $0.isQuote ? nil : $0 }
            let indent = p?.indent ?? leadingWhitespace(line)
            let body = (line as NSString).substring(from: p?.length ?? (indent as NSString).length)
            if removing { return indent + body }
            n += 1
            switch kind {
            case .bullet: return indent + "- " + body
            case .ordered: return indent + "\(n). " + body
            case .task: return indent + "- [ ] " + body
            }
        }
    }

    static func toggleTask(_ line: String) -> String {
        let ns = line as NSString
        guard let p = parse(line), !p.isQuote else {
            let lead = leadingWhitespace(line)
            return lead + "- [ ] " + ns.substring(from: (lead as NSString).length)
        }
        let markerEnd = (p.indent as NSString).length + (p.marker as NSString).length
        guard let done = p.task else {
            return p.indent + p.marker + " [ ] " + ns.substring(from: p.length)
        }
        // Box sits right after "<marker> ", replace just its middle character.
        let box = ns.range(of: "[", range: NSRange(location: markerEnd, length: ns.length - markerEnd))
        return ns.replacingCharacters(in: NSRange(location: box.location + 1, length: 1), with: done ? " " : "x")
    }

    // MARK: Tables

    static func isSeparator(_ line: String) -> Bool {
        line.contains("-") && separatorRE.firstMatch(in: line, range: full(line)) != nil
    }

    /// GFM cell split: unescaped pipes separate cells (even inside code spans), outer pipes optional.
    static func cells(_ line: String) -> [String] {
        var out: [String] = [], cur = "", escaped = false
        for ch in line {
            if escaped { cur.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; cur.append(ch); continue }
            if ch == "|" { out.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        out.append(cur)
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { out.removeFirst() }
        if t.hasSuffix("|"), !t.hasSuffix("\\|"), !out.isEmpty { out.removeLast() }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func formatTable(_ rows: [String]) -> [String] {
        let indent = leadingWhitespace(rows[0])
        var grid = rows.map(cells)
        let cols = max(1, grid.map(\.count).max() ?? 1)
        grid = grid.map { $0 + Array(repeating: "", count: cols - $0.count) }
        var widths = Array(repeating: 3, count: cols)
        for (r, row) in grid.enumerated() where r != 1 {
            for (c, cell) in row.enumerated() { widths[c] = max(widths[c], cell.count) }
        }
        return grid.enumerated().map { r, row in
            let parts = row.enumerated().map { c, cell -> String in
                guard r == 1 else { return cell + String(repeating: " ", count: widths[c] - cell.count) }
                let left = cell.hasPrefix(":"), right = cell.count > 1 && cell.hasSuffix(":")
                return (left ? ":" : "") + String(repeating: "-", count: widths[c] - (left ? 1 : 0) - (right ? 1 : 0)) + (right ? ":" : "")
            }
            return indent + "| " + parts.joined(separator: " | ") + " |"
        }
    }

    private static func pipeOffsets(_ row: String) -> [Int] {
        let u = Array(row.utf16)
        var out: [Int] = [], i = 0
        while i < u.count {
            if u[i] == 92 { i += 2; continue }   // backslash escape
            if u[i] == 124 { out.append(i) }     // "|"
            i += 1
        }
        return out
    }

    /// Content range of each cell in a formatted row (zero-length inside an empty cell).
    static func cellRanges(_ row: String) -> [NSRange] {
        let pipes = pipeOffsets(row), ns = row as NSString
        guard pipes.count >= 2 else { return [NSRange(location: ns.length, length: 0)] }
        return zip(pipes, pipes.dropFirst()).map { a, b in
            let seg = NSRange(location: a + 1, length: b - a - 1)
            let text = ns.substring(with: seg)
            let lead = text.prefix { $0 == " " }.utf16.count
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return NSRange(location: a + min(2, seg.length + 1), length: 0) }
            return NSRange(location: seg.location + lead, length: (trimmed as NSString).length)
        }
    }

    static func cellIndex(_ row: String, cursor: Int) -> Int {
        let before = pipeOffsets(row).filter { $0 < cursor }.count
        let leading = row.trimmingCharacters(in: .whitespaces).hasPrefix("|") ? 1 : 0
        return max(0, before - leading)
    }

    struct TableEdit: Equatable { var lines: [String]; var row: Int; var selection: NSRange }

    private static func withEmptyRow(_ lines: [String], at index: Int) -> [String] {
        let cols = cellRanges(lines[0]).count
        var l = lines
        l.insert(String(repeating: "|", count: cols + 1), at: index)
        return formatTable(l)
    }

    /// Tab / Shift-Tab: move to the next / previous cell, appending a row past the end.
    static func tableTab(_ rows: [String], row: Int, cursor: Int, backward: Bool) -> TableEdit {
        var lines = formatTable(rows)
        let cols = cellRanges(lines[0]).count
        var r = row, c = min(cellIndex(rows[row], cursor: cursor), cols - 1)
        if r == 1 { r = backward ? 0 : 2; c = backward ? cols - 1 : 0 }
        else if backward {
            c -= 1
            if c < 0 { r = r == 2 ? 0 : max(0, r - 1); c = r == row ? 0 : cols - 1 }
        } else {
            c += 1
            if c >= cols { c = 0; r = r == 0 ? 2 : r + 1 }
        }
        if r >= lines.count { lines = withEmptyRow(lines, at: lines.count) }
        return TableEdit(lines: lines, row: r, selection: cellRanges(lines[r])[c])
    }

    /// Return: new row below. Return on an empty body row leaves the table.
    static func tableReturn(_ rows: [String], row: Int) -> TableEdit {
        var lines = formatTable(rows)
        if row >= 2, cells(rows[row]).allSatisfy(\.isEmpty) {
            lines.remove(at: row)
            lines.append("")
            return TableEdit(lines: lines, row: lines.count - 1, selection: NSRange(location: 0, length: 0))
        }
        let at = max(row, 1) + 1
        lines = withEmptyRow(lines, at: at)
        return TableEdit(lines: lines, row: at, selection: cellRanges(lines[at])[0])
    }

    static let tableTemplate = ["| Column 1 | Column 2 | Column 3 |", "| -------- | -------- | -------- |", "|          |          |          |"]

    // MARK: Structure

    /// Ranges of fenced code blocks, fence lines included. An unclosed fence runs to the end.
    static func codeBlocks(_ ns: NSString) -> [NSRange] { codeBlocksDetailed(ns).blocks }

    /// Code block ranges plus whether the last one is still open (no closing fence before the end).
    static func codeBlocksDetailed(_ ns: NSString) -> (blocks: [NSRange], openAtEnd: Bool) {
        var out: [NSRange] = []
        var open: (start: Int, fence: String)?
        for m in fenceRE.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)) {
            let fence = ns.substring(with: m.range(at: 1))
            let line = ns.lineRange(for: m.range)
            if let o = open {
                let rest = ns.substring(with: NSRange(location: m.range.upperBound, length: line.upperBound - m.range.upperBound))
                guard fence.first == o.fence.first, fence.count >= o.fence.count, rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                out.append(NSRange(location: o.start, length: line.upperBound - o.start))
                open = nil
            } else {
                open = (line.location, fence)
            }
        }
        if let o = open { out.append(NSRange(location: o.start, length: ns.length - o.start)) }
        return (out, open != nil)
    }

    struct Heading: Hashable { var level: Int; var title: String; var location: Int }

    static func headings(_ ns: NSString, code: [NSRange]) -> [Heading] {
        headingRE.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard !code.contains(where: { NSLocationInRange(m.range.location, $0) }) else { return nil }
            return Heading(level: m.range(at: 1).length, title: ns.substring(with: m.range(at: 2)), location: m.range.location)
        }
    }
}

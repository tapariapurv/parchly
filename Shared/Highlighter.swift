import Foundation

/// A small, language-agnostic code lexer for fenced blocks: good-enough colouring for the common
/// C/Swift/JS/Python/shell family without shipping grammars.
/// ponytail: single-line rules only (no multi-line strings/comments); add per-language grammars if it matters.
enum Highlighter {
    enum Kind: Int { case keyword, string, number, comment, type, function }

    private static let keywords: Set<String> = [
        "let", "var", "const", "func", "function", "def", "class", "struct", "enum", "protocol", "interface", "extension",
        "if", "else", "elif", "for", "while", "do", "return", "import", "from", "export", "default", "in", "of", "as", "is",
        "true", "false", "nil", "null", "None", "True", "False", "undefined", "self", "this", "super", "new", "public",
        "private", "fileprivate", "internal", "static", "final", "async", "await", "try", "catch", "throw", "throws",
        "switch", "case", "break", "continue", "guard", "fn", "pub", "use", "mut", "impl", "match", "type", "package",
        "lambda", "with", "yield", "echo", "then", "fi", "done", "esac", "local", "where", "and", "or", "not", "void",
        "int", "bool", "string", "select", "insert", "update", "delete", "create", "table", "when", "end",
    ]
    private static let rules: [(NSRegularExpression, Kind)] = ([
        (#"(?://|#(?!include|!)|--\s).*$"#, .comment),
        (#"/\*.*?\*/"#, .comment),
        (#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, .string),
        (#"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b"#, .number),
        (#"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#, .function),
        (#"\b[A-Z][A-Za-z0-9_]*\b"#, .type),
        (#"\b[A-Za-z_]+\b"#, .keyword),
    ] as [(String, Kind)]).map { (try! NSRegularExpression(pattern: $0.0, options: .anchorsMatchLines), $0.1) }

    /// Token ranges within `range` of `text`, earliest rule wins on overlap.
    static func tokens(in text: NSString, range: NSRange) -> [(NSRange, Kind)] {
        var out: [(NSRange, Kind)] = []
        for (re, kind) in rules {
            for m in re.matches(in: text as String, range: range) {
                let r = m.range
                if out.contains(where: { NSIntersectionRange($0.0, r).length > 0 }) { continue }
                if kind == .keyword, !keywords.contains(text.substring(with: r)) { continue }
                if kind == .function, keywords.contains(text.substring(with: r)) { continue }
                out.append((r, kind))
            }
        }
        return out
    }

    /// Wraps tokens of an already HTML-escaped `<code>` body in `<span class="tok-…">`.
    static func html(_ escaped: String) -> String {
        let raw = escaped.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
        let ns = raw as NSString
        let names = ["kw", "str", "num", "com", "type", "fn"]
        var out = "", at = 0
        for (r, k) in tokens(in: ns, range: NSRange(location: 0, length: ns.length)).sorted(by: { $0.0.location < $1.0.location }) {
            out += escape(ns.substring(with: NSRange(location: at, length: r.location - at)))
            out += "<span class=\"tok-\(names[k.rawValue])\">" + escape(ns.substring(with: r)) + "</span>"
            at = r.upperBound
        }
        return out + escape(ns.substring(from: at))
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

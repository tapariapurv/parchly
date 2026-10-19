import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown → HTML via cmark-gfm (GitHub-flavored). Shared by the app preview and the Quick Look extension.
enum Renderer {
    static func html(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_GITHUB_PRE_LANG
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        var math: [(String, Bool)] = []
        let source = protectMath(frontMatterAsCode(markdown), into: &math)
        cmark_parser_feed(parser, source, source.utf8.count)
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }
        guard let out = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(out) }
        return restoreMath(polish(String(cString: out)), math)
    }

    // MARK: Extensions beyond GFM

    private static let mathRE = try! NSRegularExpression(pattern: #"(```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`)|\$\$([\s\S]+?)\$\$|(?<![\\$\w])\$(?=\S)([^$\n]+?)(?<=\S)\$(?![\w$])"#)

    /// Swaps $…$ / $$…$$ for private-use placeholders so cmark can't mangle backslashes or underscores.
    static func protectMath(_ s: String, into math: inout [(String, Bool)]) -> String {
        let ns = s as NSString
        var out = "", at = 0
        for m in mathRE.matches(in: s, range: NSRange(location: 0, length: ns.length)) where m.range(at: 1).location == NSNotFound {
            let display = m.range(at: 2).location != NSNotFound
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at))
            out += "\u{E000}\(math.count)\u{E001}"
            math.append((ns.substring(with: m.range(at: display ? 2 : 3)), display))
            at = m.range.upperBound
        }
        return out + ns.substring(from: at)
    }

    static func restoreMath(_ html: String, _ math: [(String, Bool)]) -> String {
        var s = html
        for (i, (tex, display)) in math.enumerated() {
            let esc = tex.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let tag = display ? "<div class=\"math math-display\">\(esc)</div>" : "<span class=\"math math-inline\">\(esc)</span>"
            s = s.replacingOccurrences(of: display ? "<p>\u{E000}\(i)\u{E001}</p>" : "\u{E000}\(i)\u{E001}", with: tag)
            s = s.replacingOccurrences(of: "\u{E000}\(i)\u{E001}", with: tag)
        }
        return s
    }

    private static let alertRE = try! NSRegularExpression(pattern: #"<blockquote>\n<p>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*"#, options: .caseInsensitive)
    private static let textRE = try! NSRegularExpression(pattern: #"<pre[\s\S]*?</pre>|<code[\s\S]*?</code>|<[^>]+>|[^<]+"#)
    private static let markRE = try! NSRegularExpression(pattern: #"==(?=\S)([^=]+?)(?<=\S)=="#)
    private static let wikiRE = try! NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#)
    private static let emojiRE = try! NSRegularExpression(pattern: #":([a-z0-9_+-]+):"#)
    static let emoji: [String: String] = [
        "smile": "😄", "grin": "😁", "joy": "😂", "wink": "😉", "heart": "❤️", "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎",
        "tada": "🎉", "rocket": "🚀", "fire": "🔥", "star": "⭐", "sparkles": "✨", "check": "✔️", "white_check_mark": "✅", "x": "❌",
        "warning": "⚠️", "bulb": "💡", "memo": "📝", "book": "📖", "bug": "🐛", "zap": "⚡", "eyes": "👀", "thinking": "🤔", "pray": "🙏",
        "clap": "👏", "wave": "👋", "ok_hand": "👌", "100": "💯", "coffee": "☕", "lock": "🔒", "key": "🔑", "link": "🔗", "pushpin": "📌",
        "calendar": "📅", "chart_with_upwards_trend": "📈", "construction": "🚧", "question": "❓", "exclamation": "❗", "smiley": "😃",
        "sob": "😭", "cry": "😢", "sunglasses": "😎", "muscle": "💪", "apple": "🍎", "computer": "💻", "gear": "⚙️", "hammer": "🔨",
    ]

    /// [[Note]] → Note.md, [[Note#Heading]] → Note.md#heading, [[#Heading]] → #heading.
    static func wikiHref(_ target: String) -> String {
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let file = parts[0].isEmpty ? "" : (parts[0].hasSuffix(".md") ? parts[0] : parts[0] + ".md")
        let anchor = parts.count > 1 ? "#" + slug(parts[1]) : ""
        return (file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file) + anchor
    }

    /// GitHub-style heading id.
    static func slug(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted).joined()
            .replacingOccurrences(of: " ", with: "-")
    }

    /// GitHub alerts, Mermaid blocks, ==highlights==, [[wiki links]] and :emoji: on top of cmark-gfm's output.
    static func extend(_ html: String) -> String {
        var s = html
        for m in alertRE.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)).reversed() {
            let kind = (s as NSString).substring(with: m.range(at: 1)).lowercased()
            s = (s as NSString).replacingCharacters(in: m.range, with: "<blockquote class=\"alert alert-\(kind)\">\n<p class=\"alert-title\">\(kind.capitalized)</p>\n<p>")
        }
        s = s.replacingOccurrences(of: #"<pre lang="mermaid"><code>([\s\S]*?)</code></pre>"#, with: "<pre class=\"mermaid\">$1</pre>", options: .regularExpression)
        let ns = s as NSString
        return textRE.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m -> String in
            var t = ns.substring(with: m.range)
            guard !t.hasPrefix("<") else { return t }
            t = markRE.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "<mark>$1</mark>")
            for w in wikiRE.matches(in: t, range: NSRange(location: 0, length: (t as NSString).length)).reversed() {
                let tn = t as NSString
                let target = tn.substring(with: w.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let label = w.range(at: 2).location != NSNotFound ? tn.substring(with: w.range(at: 2)) : target
                t = tn.replacingCharacters(in: w.range, with: "<a class=\"wiki\" href=\"\(wikiHref(target))\">\(label)</a>")
            }
            for e in emojiRE.matches(in: t, range: NSRange(location: 0, length: (t as NSString).length)).reversed() {
                if let glyph = emoji[(t as NSString).substring(with: e.range(at: 1))] { t = (t as NSString).replacingCharacters(in: e.range, with: glyph) }
            }
            return t
        }.joined()
    }

    private static let codeRE = try! NSRegularExpression(pattern: #"<pre(?: lang="([^"]*)")?><code[^>]*>(.*?)</code></pre>"#, options: .dotMatchesLineSeparators)
    private static let headingRE = try! NSRegularExpression(pattern: #"<h([1-6])>(.*?)</h\1>"#)

    /// Adds syntax colouring to fenced code and stable ids to headings (for #anchor links).
    static func polish(_ html: String) -> String {
        var s = html as NSString
        for m in codeRE.matches(in: s as String, range: NSRange(location: 0, length: s.length)).reversed() {
            if m.range(at: 1).location != NSNotFound, s.substring(with: m.range(at: 1)) == "mermaid" { continue }
            let body = Highlighter.html(s.substring(with: m.range(at: 2)))
            s = s.replacingCharacters(in: m.range(at: 2), with: body) as NSString
        }
        var used: [String: Int] = [:]
        for m in headingRE.matches(in: s as String, range: NSRange(location: 0, length: s.length)).reversed() {
            let text = s.substring(with: m.range(at: 2)).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            var slug = Self.slug(text)
            if let n = used[slug] { used[slug] = n + 1; slug += "-\(n)" } else { used[slug] = 1 }
            let tag = "<h\(s.substring(with: m.range(at: 1)))"
            s = s.replacingCharacters(in: NSRange(location: m.range.location, length: (tag as NSString).length), with: tag + " id=\"\(slug)\"") as NSString
        }
        return extend(s as String)
    }

    /// Full standalone page. `base` lets relative image paths resolve against the document's folder.
    static func page(_ markdown: String, base: URL? = nil) -> String {
        let baseTag = base.map { "<base href=\"\($0.absoluteString)\">" } ?? ""
        return """
        <!doctype html><html><head><meta charset="utf-8">\(baseTag)
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>\(css)</style></head><body><article id="c">\(html(markdown))</article></body></html>
        """
    }

    /// Script tags that typeset math and diagrams in exported HTML.
    static let exportScripts = """
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/katex.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/katex.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js"></script>
    <script>document.querySelectorAll('.math').forEach(function(e){try{katex.render(e.textContent,e,{displayMode:e.classList.contains('math-display'),throwOnError:false})}catch(_){}});
    if(document.querySelector('pre.mermaid')){mermaid.initialize({startOnLoad:false,theme:matchMedia('(prefers-color-scheme: dark)').matches?'dark':'neutral'});mermaid.run({querySelector:'pre.mermaid'});}</script>
    """

    /// YAML front matter would otherwise render as a rule plus a paragraph.
    private static func frontMatterAsCode(_ s: String) -> String {
        guard s.hasPrefix("---\n"), let end = s.range(of: "\n---\n", range: s.index(s.startIndex, offsetBy: 4)..<s.endIndex) else { return s }
        let yaml = s[s.index(s.startIndex, offsetBy: 4)..<end.lowerBound]
        return "```yaml\n\(yaml)\n```\n" + s[end.upperBound...]
    }

    static let css = """
    :root{--bg:#f7f4ee;--surface:#fffdfa;--fg:#292522;--muted:#685f56;--faint:#8b8178;--heading:#181513;--marker:#71665c;--accent:#307afe;--link:#245fb8;--line:#d9d2c8;--selection:#d9e7fc;--code:#eeeae3;--inline-code:#e8e2d9;--quote:#c9b294;--kw:#8e4f7d;--str:#456f58;--num:#1a659e;--com:#8b817c;--type:#1d6ca4;--fn:#2a5db0}
    @media (prefers-color-scheme:dark){:root{--bg:#171614;--surface:#24211e;--fg:#e3ddd5;--muted:#aca297;--faint:#7f776f;--heading:#f4eee5;--marker:#bdb2a6;--accent:#6ea8ff;--link:#8ab8ff;--line:#3d3832;--selection:#253a56;--code:#231f1a;--inline-code:#2d2822;--quote:#625344;--kw:#e0879f;--str:#a8c08a;--num:#8fb8d9;--com:#726a61;--type:#e7c77d;--fn:#8fb8d9}}
    html{background:var(--bg)}
    ::selection{background:var(--selection)}
    body{margin:0;padding:48px 32px 96px;color:var(--fg);font:16px/1.55 ui-serif,"New York",Georgia,serif;-webkit-font-smoothing:antialiased}
    article{max-width:70ch;margin:0 auto}
    h1,h2,h3,h4,h5,h6{color:var(--heading);line-height:1.25;margin:1.5em 0 .5em;font-weight:700;scroll-margin-top:24px}
    h1{font-size:1.95em}h2{font-size:1.56em}h3{font-size:1.25em}h4{font-size:1.1em}h5{font-size:1em}h6{font-size:1em;color:var(--muted)}
    article>:first-child{margin-top:0}
    p,ul,ol,blockquote,pre,table{margin:0 0 1em}
    a{color:var(--link);text-decoration:underline;text-decoration-color:color-mix(in srgb,var(--link) 35%,transparent);text-underline-offset:2px}
    code{font:.88em "SF Mono",ui-monospace,Menlo,monospace;background:var(--inline-code);padding:.12em .35em;border-radius:5px}
    pre{background:var(--code);padding:14px 16px;border-radius:10px;overflow:auto;line-height:1.5}
    pre code{background:none;padding:0;font-size:.84em}
    .tok-kw{color:var(--kw)}.tok-str{color:var(--str)}.tok-num{color:var(--num)}.tok-com{color:var(--com);font-style:italic}.tok-type{color:var(--type)}.tok-fn{color:var(--fn)}
    blockquote{margin-left:0;padding:0 0 0 14px;border-left:3px solid var(--quote)}
    hr{border:0;border-top:1px solid var(--line);margin:2em 0}
    ul,ol{padding-left:1.6em}li{margin:.2em 0}li>p{margin:0}
    li::marker{color:var(--marker)}
    li:has(>input[type=checkbox]){list-style:none;margin-left:-1.4em}
    li>input[type=checkbox]{appearance:none;width:1.1em;height:1.1em;margin:0 .55em 0 0;vertical-align:-.15em;border:1.5px solid var(--faint);border-radius:.28em}
    li>input[type=checkbox]:checked{background:color-mix(in srgb,var(--accent) 18%,transparent) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M4 8.5l2.5 2.5L12 5.5' fill='none' stroke='%23307afe' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center/100% no-repeat;border-color:var(--accent)}
    li:has(>input:checked){color:var(--muted);text-decoration:line-through}
    table{border-collapse:collapse;display:block;overflow:auto;width:max-content;max-width:100%}
    th,td{border:1px solid var(--line);padding:6px 12px}th{background:var(--surface);font-weight:600}
    img{max-width:100%;border-radius:6px}
    del{color:var(--muted)}
    .footnotes{font-size:.9em;color:var(--muted)}
    mark{background:color-mix(in srgb,#ffd400 40%,transparent);color:inherit;padding:0 .15em;border-radius:3px}
    .math-inline{font:.9em "SF Mono",ui-monospace,monospace;color:var(--accent)}.math-display{font:.9em "SF Mono",ui-monospace,monospace;text-align:center;margin:1em 0;color:var(--accent)}
    .katex-display{margin:1em 0}.math .katex{color:var(--fg)}
    pre.mermaid{background:none;text-align:center;font:.85em "SF Mono",monospace;color:var(--muted)}
    .alert{border-left-width:4px;border-left-color:var(--alert);background:color-mix(in srgb,var(--alert) 8%,transparent);border-radius:0 8px 8px 0;padding:10px 14px}
    .alert>:last-child{margin-bottom:0}.alert-title{font:600 .9em -apple-system,sans-serif;color:var(--alert);margin:0 0 4px}
    .alert-note{--alert:#307afe}.alert-tip{--alert:#2f7a46}.alert-important{--alert:#7a5cb8}.alert-warning{--alert:#945c0a}.alert-caution{--alert:#b03a34}
    a.wiki{text-decoration-style:dotted}
    """
}

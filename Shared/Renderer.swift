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
        let source = frontMatterAsCode(markdown)
        cmark_parser_feed(parser, source, source.utf8.count)
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }
        guard let out = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(out) }
        return polish(String(cString: out))
    }

    private static let codeRE = try! NSRegularExpression(pattern: #"<pre><code([^>]*)>(.*?)</code></pre>"#, options: .dotMatchesLineSeparators)
    private static let headingRE = try! NSRegularExpression(pattern: #"<h([1-6])>(.*?)</h\1>"#)

    /// Adds syntax colouring to fenced code and stable ids to headings (for #anchor links).
    static func polish(_ html: String) -> String {
        var s = html as NSString
        for m in codeRE.matches(in: s as String, range: NSRange(location: 0, length: s.length)).reversed() {
            let body = Highlighter.html(s.substring(with: m.range(at: 2)))
            s = s.replacingCharacters(in: m.range(at: 2), with: body) as NSString
        }
        var used: [String: Int] = [:]
        for m in headingRE.matches(in: s as String, range: NSRange(location: 0, length: s.length)).reversed() {
            let text = s.substring(with: m.range(at: 2)).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            var slug = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -")).inverted).joined()
                .replacingOccurrences(of: " ", with: "-")
            if let n = used[slug] { used[slug] = n + 1; slug += "-\(n)" } else { used[slug] = 1 }
            let tag = "<h\(s.substring(with: m.range(at: 1)))"
            s = s.replacingCharacters(in: NSRange(location: m.range.location, length: (tag as NSString).length), with: tag + " id=\"\(slug)\"") as NSString
        }
        return s as String
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
    """
}

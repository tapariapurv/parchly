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
        return String(cString: out)
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
    :root{--bg:#F5F3EF;--fg:#1C1A17;--muted:#6E6E73;--line:#E6E3DC;--code:#EBE7DF;--accent:#3A6FD8}
    @media (prefers-color-scheme:dark){:root{--bg:#1E1D1C;--fg:#E8E3DB;--muted:#9A9AA0;--line:#38383C;--code:#2A2A2D;--accent:#7FA7F5}}
    html{background:var(--bg)}
    body{margin:0;padding:40px 32px 80px;color:var(--fg);font:17px/1.6 ui-serif,"New York",Georgia,serif;-webkit-font-smoothing:antialiased}
    article{max-width:740px;margin:0 auto}
    h1,h2,h3,h4,h5,h6{line-height:1.25;margin:1.4em 0 .5em;font-weight:700}
    h1{font-size:1.9em}h2{font-size:1.5em}h3{font-size:1.25em}h4{font-size:1.05em}h5{font-size:1em}h6{font-size:1em;color:var(--muted)}
    article>:first-child{margin-top:0}
    p,ul,ol,blockquote,pre,table{margin:0 0 1em}
    a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
    code{font:.88em ui-monospace,"SF Mono",Menlo,monospace;background:var(--code);padding:.15em .35em;border-radius:5px}
    pre{background:var(--code);padding:14px 16px;border-radius:8px;overflow:auto;line-height:1.5}
    pre code{background:none;padding:0;font-size:.86em}
    blockquote{margin-left:0;padding:0 0 0 14px;border-left:3px solid #C9B08A}
    hr{border:0;border-top:1px solid var(--line);margin:2em 0}
    ul,ol{padding-left:1.6em}li{margin:.2em 0}li>p{margin:0}
    li:has(>input[type=checkbox]){list-style:none;margin-left:-1.4em}
    li::marker{color:var(--muted)}
    li>input[type=checkbox]{appearance:none;width:1.1em;height:1.1em;margin:0 .55em 0 0;vertical-align:-.12em;border:1.5px solid var(--muted);border-radius:.25em}
    li>input[type=checkbox]:checked{background:var(--accent) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M4 8.5l2.5 2.5L12 5.5' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center/100% no-repeat;border-color:var(--accent)}
    li:has(>input:checked){color:var(--muted);text-decoration:line-through}
    table{border-collapse:collapse;display:block;overflow:auto;width:max-content;max-width:100%}
    th,td{border:1px solid var(--line);padding:6px 12px}th{background:var(--code);font-weight:600}
    img{max-width:100%;border-radius:6px}
    del{color:var(--muted)}
    .footnotes{font-size:.9em;color:var(--muted)}
    """
}

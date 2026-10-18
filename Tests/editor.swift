import AppKit
// Drives the real editor in-process. Run: scripts/test.sh
// Each check prints FAIL with a line number; the process exits non-zero on any failure.

var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) { if !cond() { failures += 1; print("FAIL line \(line): \(msg)") } }

_ = NSApplication.shared
let ed = EditorController()
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
win.contentViewController = ed
let tv = ed.textView!
win.makeFirstResponder(tv)
let undo = UndoManager()
final class UndoHost: NSObject, NSTextViewDelegate {}
tv.allowsUndo = true

func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
func load(_ s: String, caret: Int? = nil) { ed.setText("x"); ed.setText(s); tv.setSelectedRange(NSRange(location: caret ?? (s as NSString).length, length: 0)); spin() }
func type(_ s: String) { for ch in s { tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)); spin() } }
func sel() -> NSRange { tv.selectedRange() }
var text: String { tv.string }

for mode in [true, false] {   // Document mode, then Source mode
    ed.setWysiwyg(mode)
    let m = mode ? "doc" : "source"

    // Lists
    load("- apple"); tv.insertNewline(nil); type("pear")
    check(text == "- apple\n- pear", "\(m) bullet continue: \(text.debugDescription)")
    load("- "); tv.insertNewline(nil)
    check(text == "", "\(m) empty bullet ends list")
    load("1. one\n2. two\n3. three", caret: 6); tv.insertNewline(nil); type("new")
    check(text == "1. one\n2. new\n3. two\n4. three", "\(m) ordered insert renumbers: \(text.debugDescription)")
    check(sel().location == 13, "\(m) caret stays after renumber: \(sel())")
    load("- [x] done"); tv.insertNewline(nil); type("next")
    check(text == "- [x] done\n- [ ] next", "\(m) task continue")
    load("- a"); tv.insertTab(nil)
    check(text == "    - a", "\(m) tab nests")
    tv.insertBacktab(nil)
    check(text == "- a", "\(m) shift-tab outdents")
    load("> quote"); tv.insertNewline(nil); type("more")
    check(text == "> quote\n> more", "\(m) quote continue")

    // Tables
    load("| a | b |\n|---|---|\n|   |   |", caret: 22); type("x"); tv.insertTab(nil); type("y")
    tv.insertNewline(nil); type("z")
    check(text.hasPrefix("| a   | b   |\n| --- | --- |\n| x   | y   |\n| z") && text.components(separatedBy: "\n").count == 4, "\(m) table tab + return: \(text.debugDescription)")

    // Wrap + pairs
    load("make bold here"); tv.setSelectedRange(NSRange(location: 5, length: 4)); type("*")
    check(text == "make *bold* here" && sel() == NSRange(location: 6, length: 4), "\(m) wrap selection: \(text)")
    load("f"); type("(")
    check(text == "f()" && sel().location == 2, "\(m) auto pair")
    type(")")
    check(text == "f()" && sel().location == 3, "\(m) type over closer")
    load("f"); type("("); tv.deleteBackward(nil)
    check(text == "f", "\(m) backspace removes pair")

    // Undo / redo of a smart edit
    load("1. a\n2. b", caret: 4); tv.insertNewline(nil)
    let after = text
    tv.undoManager?.undo(); spin()
    check(text == "1. a\n2. b", "\(m) undo smart return: \(text.debugDescription)")
    tv.undoManager?.redo(); spin()
    check(text == after, "\(m) redo smart return")

    // Format commands
    load("Title", caret: 0); let h2 = NSMenuItem(); h2.tag = 2; tv.setHeading(h2)
    check(text == "## Title", "\(m) heading")
    tv.setHeading(h2)
    check(text == "Title", "\(m) heading toggles off")
    load("a\nb"); tv.selectAll(nil); tv.toggleNumbers(nil)
    check(text == "1. a\n2. b", "\(m) numbered toggle")
    load("todo"); tv.toggleTaskDone(nil)
    check(text == "- [ ] todo", "\(m) task add")
    tv.toggleTaskDone(nil)
    check(text == "- [x] todo", "\(m) task tick")
    load("word", caret: 0); tv.selectAll(nil); tv.toggleBold(nil)
    check(text == "**word**", "\(m) bold")
    tv.toggleBold(nil)
    check(text == "word", "\(m) unbold")
    load("one\ntwo", caret: 5); tv.moveLineUp(nil)
    check(text == "two\none" && sel().location == 1, "\(m) move line up")
    tv.duplicateLine(nil)
    check(text == "two\ntwo\none", "\(m) duplicate line")
    load(""); tv.insertTable(nil)
    check(text.hasPrefix("| Column 1 |") && tv.selectedRange().length == 8, "\(m) insert table selects header")
    load("text"); tv.insertRule(nil)
    check(text == "text\n\n---\n", "\(m) insert rule")
    load("# Head", caret: 2); tv.deleteBackward(nil)
    check(text == "Head", "\(m) backspace removes heading prefix: \(text)")

    // Clipboard (the user's clipboard is restored afterwards)
    let pb = NSPasteboard.general, saved = pb.string(forType: .string)
    load("hello world"); tv.setSelectedRange(NSRange(location: 0, length: 5)); tv.copy(nil)
    check(pb.string(forType: .string) == "hello", "\(m) copy")
    tv.setSelectedRange(NSRange(location: 11, length: 0)); tv.paste(nil)
    check(text == "hello worldhello", "\(m) paste")
    tv.setSelectedRange(NSRange(location: 0, length: 5)); tv.cut(nil)
    check(text == " worldhello" && pb.string(forType: .string) == "hello", "\(m) cut")
    pb.clearContents(); pb.setString("https://example.com", forType: .string)
    load("site"); tv.selectAll(nil); tv.paste(nil)
    check(text == "[site](https://example.com)", "\(m) paste URL over selection makes link")
    pb.clearContents(); pb.setData(try! NSAttributedString(string: "rich", attributes: [.font: NSFont.boldSystemFont(ofSize: 30)]).data(from: NSRange(location: 0, length: 4), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
    pb.setString("rich", forType: .string)
    load(""); tv.paste(nil)
    check(text == "rich", "\(m) rich paste becomes plain text")
    pb.clearContents(); if let saved { pb.setString(saved, forType: .string) }

    // Round trip: styling never changes the characters
    let sample = "# H1\nSetext\n===\n\n**b** *i* `c` ~~s~~ ==m== $x^2$ [[Note|N]] [l](u) [^1] <br>\n\n> [!NOTE]\n> hi\n\n- [ ] t\n1. n\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```js\nlet a = 1 // c\n```\n\n$$\nx\n$$\n\n![img](missing.png)\n\n[^1]: foot\n[ref]: http://x\n---\n"
    load(sample)
    check(text == sample, "\(m) styling preserves text")
}

// Fence edits must still restyle correctly with the incremental fence tracking
ed.setWysiwyg(true)
load("```js\nlet a = 1\n```\nafter", caret: 3)
check(ed.styler.code.count == 1, "one code block")
tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
check(ed.styler.code.count == 1 && ed.styler.code[0].length == 21, "typing in fence line keeps block: \(ed.styler.code)")
tv.setSelectedRange(NSRange(location: 2, length: 0)); tv.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
check(ed.styler.code.count == 1 && ed.styler.code[0].location == 18, "split fence: old closer now opens a block: \(ed.styler.code)")
load("```\ncode\n```", caret: 8); type("more")
check(ed.styler.code.count == 1 && ed.styler.code[0].upperBound == (text as NSString).length, "typing inside code grows block")

// Document-mode caret clamping keeps the caret out of hidden prefixes
ed.setWysiwyg(true)
load("## Heading", caret: 0); tv.setSelectedRange(NSRange(location: 1, length: 0))
check(sel().location == 3, "caret clamps past hidden heading prefix: \(sel())")
ed.setWysiwyg(false)
tv.setSelectedRange(NSRange(location: 1, length: 0))
check(sel().location == 1, "source mode does not clamp")

// Performance: a ~1 MB document stays responsive
ed.setWysiwyg(true)
let big = String(repeating: "## Section\n\nSome **bold** text with `code` and a [link](x).\n\n- item one\n- [ ] task\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n", count: 9000)
var t0 = Date(); load(big)
let loadTime = Date().timeIntervalSince(t0)
tv.setSelectedRange(NSRange(location: 5000, length: 0)); t0 = Date()
for ch in "typing fast" { tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)); tv.displayIfNeeded() }
let typeTime = Date().timeIntervalSince(t0) / 11
if ProcessInfo.processInfo.environment["PERF_LOOP"] != nil {   // for profiling with `sample`
    for _ in 0..<600 { tv.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)); tv.displayIfNeeded() }
}
print(String(format: "perf: load %.0f KB in %.2fs, %.1f ms per keystroke", Double((big as NSString).length) / 1024, loadTime, typeTime * 1000))
check(loadTime < 6, "1MB load under 6s")
check(typeTime < 0.016, "keystroke under one 60Hz frame")

print(failures == 0 ? "editor: all checks passed" : "editor: \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)

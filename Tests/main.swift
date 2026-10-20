import Foundation
// Run: swiftc -O App/MarkdownLogic.swift Tests/main.swift -o build/mdtest && build/mdtest
func check(_ cond: Bool, _ msg: String, line: Int = #line) { if !cond { print("FAIL line \(line): \(msg)"); exit(1) } }

// Return continues / ends lists
check(MD.returnEdit(line: "- item", cursor: 6) == .insert("\n- "), "bullet")
check(MD.returnEdit(line: "  9. nine", cursor: 9) == .insert("\n  10. "), "ordered")
check(MD.returnEdit(line: "1) a", cursor: 4) == .insert("\n2) "), "paren")
check(MD.returnEdit(line: "- [x] done", cursor: 10) == .insert("\n- [ ] "), "task")
check(MD.returnEdit(line: "> quote", cursor: 7) == .insert("\n> "), "quote")
check(MD.returnEdit(line: "- ", cursor: 2) == .replaceLine(""), "empty ends")
check(MD.returnEdit(line: "    - ", cursor: 6) == .replaceLine("- "), "empty nested outdents")
check(MD.returnEdit(line: "---", cursor: 3) == .insert("\n"), "hr is not a list")
check(MD.returnEdit(line: "**bold**", cursor: 8) == .insert("\n"), "bold is not a list")
check(MD.returnEdit(line: "    code", cursor: 8) == .insert("\n    "), "keeps indent")
check(MD.returnEdit(line: "- item", cursor: 1) == .insert("\n"), "cursor inside marker")

// Renumbering
check(MD.renumbered(["1. a", "2. new", "2. b", "    1. x", "    5. y", "3. c"]) == ["1. a", "2. new", "3. b", "    1. x", "    2. y", "4. c"], "renumber")
check(MD.renumbered(["3. a", "1. b"]) == ["3. a", "4. b"], "keeps start")
check(MD.renumbered(["1. a", "para", "1. b"]) == ["1. a", "para", "1. b"], "paragraph splits lists")
check(MD.listRegion(["intro", "1. a", "", "2. b", "end"], around: 3) == 1..<4, "region")

// Toggles
check(MD.setHeading("## Title", level: 1) == "# Title", "h2->h1")
check(MD.setHeading("# Title", level: 1) == "Title", "toggle off")
check(MD.setHeading("Title", level: 3) == "### Title", "set h3")
check(MD.toggleList(["a", "", "b"], .ordered) == ["1. a", "", "2. b"], "ordered")
check(MD.toggleList(["- a", "- b"], .bullet) == ["a", "b"], "remove bullets")
check(MD.toggleList(["1. a", "b"], .bullet) == ["- a", "- b"], "convert")
check(MD.toggleTask("- [ ] x") == "- [x] x" && MD.toggleTask("- [X] x") == "- [ ] x", "flip")
check(MD.toggleTask("* x") == "* [ ] x" && MD.toggleTask("  x") == "  - [ ] x", "add task")

// Tables
check(MD.cells("| a | b \\| c | `d` |") == ["a", "b \\| c", "`d`"], "cells")
check(MD.isSeparator("|:--|---:|") && MD.isSeparator("--- | ---") && !MD.isSeparator("| a |"), "separator")
check(MD.formatTable(["|a|bb|", "|:-|-:|", "|ccc|"]) == ["| a   | bb  |", "| :-- | --: |", "| ccc |     |"], "format")
let t = MD.formatTable(["| a | b |", "|---|---|", "| 1 | 2 |"])
var e = MD.tableTab(t, row: 0, cursor: 2, backward: false)
check(e.row == 0 && e.selection == NSRange(location: 8, length: 1), "tab next cell \(e)")
e = MD.tableTab(t, row: 0, cursor: 8, backward: false)
check(e.row == 2 && e.selection == NSRange(location: 2, length: 1), "tab skips separator")
e = MD.tableTab(t, row: 2, cursor: 8, backward: false)
check(e.lines.count == 4 && e.row == 3 && e.selection.length == 0, "tab appends row")
e = MD.tableTab(t, row: 2, cursor: 2, backward: true)
check(e.row == 0 && e.selection == NSRange(location: 8, length: 1), "shift-tab back to header")
e = MD.tableReturn(t, row: 2)
check(e.lines.count == 4 && e.row == 3 && e.lines[3] == "|     |     |", "return adds row \(e.lines)")
e = MD.tableReturn(e.lines, row: 3)
check(e.lines.count == 4 && e.lines[3] == "" && e.row == 3, "return on empty row exits")

// Structure
let doc = "# A\n```\n# not\n```\n## B\n~~~\nopen" as NSString
let code = MD.codeBlocks(doc)
check(code.count == 2 && code[1].upperBound == doc.length, "code blocks")
check(MD.headings(doc, code: code).map(\.title) == ["A", "B"], "headings skip code")
check(MD.toggleTask("[ ] a") == "- [x] a" && MD.toggleTask("  [x] a") == "  - [ ] a", "toggle bare task")
check(MD.toggleList(["[ ] a", "b"], .task) == ["- [ ] a", "- [ ] b"], "task list keeps bare box")
check(MD.toggleList([""], .task) == ["- [ ] "] && MD.toggleList([""], .bullet) == ["- "] && MD.toggleList([""], .ordered) == ["1. "], "list on empty line")
check(!MD.isBareTask("[link] x") && !MD.isBareTask("[ ]x"), "bare task needs box + space")
print("all checks passed")

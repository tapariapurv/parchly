#!/bin/bash
# Runs every automated check: editing rules, the live editor, and the renderer.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -O App/MarkdownLogic.swift Tests/main.swift -o build/tests/logic && build/tests/logic
cp Tests/editor.swift build/tests/main.swift
swiftc App/MarkdownLogic.swift App/Styling.swift App/Editor.swift App/Theme.swift App/FormatBar.swift Shared/Highlighter.swift \
  build/tests/main.swift -o build/tests/editor && build/tests/editor
APP=build/dd/Build/Products/Debug/Parchly.app/Contents/MacOS/Parchly
if [ -x "$APP" ]; then
  out=$(printf '%s\n' '> [!NOTE]' '> n' '' '$a$ ==m== [[W|L]] :rocket:' '' '```js' 'let x = 1' '```' | "$APP" --render-html)
  for want in 'alert-note' 'math-inline' '<mark>m</mark>' 'href="W.md">L<' '🚀' 'tok-kw'; do
    grep -qF "$want" <<<"$out" || { echo "FAIL render: missing $want"; exit 1; }
  done
  printf -- '- [x] a\n\n- [ ] b\n' | "$APP" --render-html | grep -qF 'disabled="" /><p>a' || { echo "FAIL render: gap after task box"; exit 1; }
  echo "render: all checks passed"
  "$APP" --selftest   # Debug build: drives documents, preview, sidebar and Home in-process
fi

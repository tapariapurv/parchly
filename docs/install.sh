#!/bin/bash
# Parchly installer: curl -fsSL https://tapariapurv.github.io/parchly/install.sh | bash
# Downloads the latest release, installs it into /Applications (or ~/Applications),
# registers the Quick Look extension and opens the app. Nothing else is touched.
set -euo pipefail

URL="https://github.com/tapariapurv/parchly/releases/latest/download/Parchly.zip"
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

[ "$(uname)" = "Darwin" ] || { echo "Parchly is a macOS app."; exit 1; }
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 14 ] || { echo "Parchly needs macOS 14 (Sonoma) or later."; exit 1; }

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
bold "Downloading Parchly…"
curl -fL --progress-bar "$URL" -o "$TMP/Parchly.zip"
ditto -x -k "$TMP/Parchly.zip" "$TMP"

osascript -e 'quit app "Parchly"' >/dev/null 2>&1 || true
rm -rf "$DEST/Parchly.app"
ditto "$TMP/Parchly.app" "$DEST/Parchly.app"
xattr -dr com.apple.quarantine "$DEST/Parchly.app" 2>/dev/null || true

bold "Registering Quick Look…"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Parchly.app"
pluginkit -a "$DEST/Parchly.app/Contents/PlugIns/ParchlyQuickLook.appex" 2>/dev/null || true
pluginkit -e use -i com.purvt.ParchlyQuickLook 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true

open "$DEST/Parchly.app"
bold "✓ Parchly is installed in $DEST."
echo "  • Press Space on any .md file in Finder for a Quick Look preview."
echo "  • To open .md files with Parchly by default: Finder › Get Info › Open with › Parchly › Change All."

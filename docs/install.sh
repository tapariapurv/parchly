#!/bin/bash
# Inkdown installer: curl -fsSL https://tapariapurv.github.io/inkdown/install.sh | bash
# Downloads the latest release, installs it into /Applications (or ~/Applications),
# registers the Quick Look extension and opens the app. Nothing else is touched.
set -euo pipefail

URL="https://github.com/tapariapurv/inkdown/releases/latest/download/Inkdown.zip"
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

[ "$(uname)" = "Darwin" ] || { echo "Inkdown is a macOS app."; exit 1; }
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 14 ] || { echo "Inkdown needs macOS 14 (Sonoma) or later."; exit 1; }

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
bold "Downloading Inkdown…"
curl -fL --progress-bar "$URL" -o "$TMP/Inkdown.zip"
ditto -x -k "$TMP/Inkdown.zip" "$TMP"

osascript -e 'quit app "Inkdown"' >/dev/null 2>&1 || true
rm -rf "$DEST/Inkdown.app"
ditto "$TMP/Inkdown.app" "$DEST/Inkdown.app"
xattr -dr com.apple.quarantine "$DEST/Inkdown.app" 2>/dev/null || true

bold "Registering Quick Look…"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Inkdown.app"
pluginkit -a "$DEST/Inkdown.app/Contents/PlugIns/InkdownQuickLook.appex" 2>/dev/null || true
pluginkit -e use -i com.purvt.InkdownQuickLook 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true

open "$DEST/Inkdown.app"
bold "✓ Inkdown is installed in $DEST."
echo "  • Press Space on any .md file in Finder for a Quick Look preview."
echo "  • To open .md files with Inkdown by default: Finder › Get Info › Open with › Inkdown › Change All."

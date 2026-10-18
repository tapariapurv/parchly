#!/bin/bash
# Builds Inkdown, packages Inkdown.zip + Inkdown.dmg, and publishes a GitHub release.
# Usage: scripts/release.sh 1.0.0        (release notes come from release-notes/v1.0.0.md)
set -euo pipefail
VERSION="${1:?usage: scripts/release.sh <version>}"
NOTES="release-notes/v$VERSION.md"
[ -f "$NOTES" ] || { echo "missing $NOTES"; exit 1; }
cd "$(dirname "$0")/.."

sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
xcodegen -q
xcodebuild -project Inkdown.xcodeproj -scheme Inkdown -configuration Release \
  -derivedDataPath build/release -clonedSourcePackagesDirPath build/spm clean build -quiet
APP=build/release/Build/Products/Release/Inkdown.app
codesign --verify --deep --strict "$APP"

OUT=build/dist; rm -rf "$OUT"; mkdir -p "$OUT/dmg"
ditto -c -k --keepParent "$APP" "$OUT/Inkdown.zip"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname "Inkdown $VERSION" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/Inkdown.dmg"
(cd "$OUT" && shasum -a 256 Inkdown.zip Inkdown.dmg > SHA256SUMS.txt)

git tag -a "v$VERSION" -m "Inkdown $VERSION" 2>/dev/null || true
git push -q origin "v$VERSION"
gh release create "v$VERSION" "$OUT/Inkdown.dmg" "$OUT/Inkdown.zip" "$OUT/SHA256SUMS.txt" \
  --title "Inkdown $VERSION" --notes-file "$NOTES" --latest

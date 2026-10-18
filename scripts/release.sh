#!/bin/bash
# Builds Parchly, packages Parchly.zip + Parchly.dmg, and publishes a GitHub release.
# Usage: scripts/release.sh 1.0.0        (release notes come from release-notes/v1.0.0.md)
set -euo pipefail
VERSION="${1:?usage: scripts/release.sh <version>}"
NOTES="release-notes/v$VERSION.md"
[ -f "$NOTES" ] || { echo "missing $NOTES"; exit 1; }
cd "$(dirname "$0")/.."

sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
BUILD=$(( $(git rev-list --count HEAD) + 1 ))   # always increasing, as the App Store requires
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
git commit -qm "Bump version to $VERSION ($BUILD)" project.yml || true
git push -q origin HEAD:main
xcodegen -q
xcodebuild -project Parchly.xcodeproj -scheme Parchly -configuration Release \
  -derivedDataPath build/release -clonedSourcePackagesDirPath build/spm ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build -quiet
APP=build/release/Build/Products/Release/Parchly.app
codesign --verify --deep --strict "$APP"

OUT=build/dist; rm -rf "$OUT"; mkdir -p "$OUT/dmg"
ditto -c -k --keepParent "$APP" "$OUT/Parchly.zip"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname "Parchly $VERSION" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/Parchly.dmg"
(cd "$OUT" && shasum -a 256 Parchly.zip Parchly.dmg > SHA256SUMS.txt)

git tag -a "v$VERSION" -m "Parchly $VERSION" 2>/dev/null || true
git push -q origin "v$VERSION"
gh release create "v$VERSION" "$OUT/Parchly.dmg" "$OUT/Parchly.zip" "$OUT/SHA256SUMS.txt" \
  --title "Parchly $VERSION" --notes-file "$NOTES" --latest

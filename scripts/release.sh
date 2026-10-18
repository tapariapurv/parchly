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

# Sparkle appcast: signed with the EdDSA key stored in the login keychain (scripts: build/spm/artifacts/sparkle).
SIG=$(build/spm/artifacts/sparkle/Sparkle/bin/sign_update "$OUT/Parchly.zip")
cat > docs/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Parchly</title>
    <link>https://tapariapurv.github.io/parchly/appcast.xml</link>
    <item>
      <title>Parchly $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/tapariapurv/parchly/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/tapariapurv/parchly/releases/download/v$VERSION/Parchly.zip" type="application/octet-stream" $SIG/>
    </item>
  </channel>
</rss>
XML

git tag -a "v$VERSION" -m "Parchly $VERSION" 2>/dev/null || true
git push -q origin "v$VERSION"
gh release create "v$VERSION" "$OUT/Parchly.dmg" "$OUT/Parchly.zip" "$OUT/SHA256SUMS.txt" \
  --title "Parchly $VERSION" --notes-file "$NOTES" --latest

# Publish the appcast only after the release assets exist, so updaters never see a dead link.
git add docs/appcast.xml && git commit -qm "Appcast for $VERSION" && git push -q origin HEAD:main

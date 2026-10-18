#!/bin/bash
# Archives Inkdown and uploads it to App Store Connect.
# Needs: a paid Apple Developer Program membership for team 7PM4P8RLL2, your Apple ID signed in under
# Xcode › Settings › Accounts, and an app record for bundle ID com.purvt.Inkdown in App Store Connect.
# Listing text and screenshots live in appstore/ (fastlane deliver layout: `fastlane deliver --skip_binary_upload`).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen -q
xcodebuild -project Inkdown.xcodeproj -scheme Inkdown -configuration Release \
  -clonedSourcePackagesDirPath build/spm -archivePath build/Inkdown.xcarchive \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Inkdown.xcarchive -exportOptionsPlist appstore/ExportOptions.plist \
  -exportPath build/appstore -allowProvisioningUpdates

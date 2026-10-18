#!/bin/bash
# Archives Parchly and uploads it to App Store Connect.
# Needs: a paid Apple Developer Program membership for team 7PM4P8RLL2, your Apple ID signed in under
# Xcode › Settings › Accounts, and an app record for bundle ID com.purvt.Parchly in App Store Connect.
# Listing text and screenshots live in appstore/ (fastlane deliver layout: `fastlane deliver --skip_binary_upload`).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen -q
xcodebuild -project Parchly.xcodeproj -scheme Parchly -configuration Release \
  -clonedSourcePackagesDirPath build/spm -archivePath build/Parchly.xcarchive \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Parchly.xcarchive -exportOptionsPlist appstore/ExportOptions.plist \
  -exportPath build/appstore -allowProvisioningUpdates

# Mac App Store kit

Everything needed to list Parchly on the Mac App Store. The app is already sandboxed and ships a privacy manifest.

| Path | What |
| --- | --- |
| `metadata/en-US/*.txt` | Name (25/30), subtitle (28/30), keywords (99/100), promotional text, description, URLs, release notes |
| `metadata/*_category.txt` | Productivity (primary), Developer Tools (secondary) |
| `screenshots/en-US/*.png` | Six 2880×1800 captioned screenshots, regenerated with `python3 scripts/make-screenshots.py` |
| `review_notes.txt` | Notes for App Review (how to test, why each entitlement is needed) |
| `ExportOptions.plist` | Used by `scripts/appstore.sh` to upload the build |

The layout matches [fastlane deliver](https://docs.fastlane.tools/actions/deliver/), so `fastlane deliver --skip_binary_upload` pushes the listing.

## Keyword strategy
The name already covers *Markdown* and *Editor*, and the subtitle covers *write, view, Quick Look, .md*. The keyword field adds terms Apple doesn't already index from those two fields: `md, notes, writer, writing, preview, gfm, table, todo, checklist, journal, readme, github, outline, wysiwyg, docs`. There are no competitor trademarks and no repeated words.

## Submitting (needs the paid Apple Developer Program)
1. Join the Apple Developer Program with team `7PM4P8RLL2` and sign in under Xcode › Settings › Accounts.
2. In App Store Connect, create a macOS app with bundle ID `com.purvt.Parchly`, SKU `parchly`, primary language English.
3. Run `scripts/appstore.sh`. It archives a universal build and uploads it. Xcode creates the distribution certificates automatically.
4. Paste in or `deliver` the metadata and screenshots, then answer the privacy questionnaire with **Data Not Collected**. Encryption is already declared (`ITSAppUsesNonExemptEncryption = NO`).
5. Submit for review with `review_notes.txt`.

## Privacy nutrition label
Data Not Collected. Policy: https://tapariapurv.github.io/parchly/privacy.html

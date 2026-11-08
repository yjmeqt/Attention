# Mac App Store release

Prepared 8 November 2026. App `6827156660`, bundle ID `com.yjmeqt.attn`, team `M3V5P234X3`, minimum macOS 26.0. The Mac platform shares the iOS app record.

## Store configuration

Mac version `1.0.1`, version ID `05ee4003-0335-4ec3-bb2a-aacf01643cf5`, is configured for **manual release**. Build **1.0.1 (5)** (`0acaa458-d8d9-464a-a744-a9c7db4221b4`) is attached. Apple reports it processed and App Store eligible. Changes after build 5 affect iOS UI and build numbering; the Mac target's application sources are unchanged apart from this branch's Debug capture tooling and lazy library initialization.

Mac descriptions and keywords are stored in `ios/fastlane/mac-metadata/` for all 11 existing Mac locales: en-US, zh-Hans, ja, ko, ru, vi, ar-SA, fr-FR, de-DE, es-ES and es-MX. Mac review instructions are in `review-notes.txt` beside them. These have been uploaded to the Mac version, preserving review contact details and shared app information.

There are three real application screenshots per locale: library, search and card inspector. The exported PNGs are 2880×1800, opaque, and use localized headings. Some Mac UI strings currently fall back to English; the captures show the actual shipped UI rather than replacing those labels. Sample website previews and tags are demonstration content.

## Verification

- Debug screenshot build and Release Mac build succeeded.
- The exported build 5 package has the team's Mac Installer Distribution signature. Its extracted app passes `codesign --verify --deep --strict`.
- The exported app has production push and CloudKit entitlements, App Sandbox, network client access and user-selected file access; no `get-task-allow` entitlement.
- Captures exercised preview retrieval, library persistence, search and card inspection. End-to-end production iCloud sync and biometric authentication were not independently exercised in this preparation.
- `asc validate` flags empty What's New fields, but Apple rejects edits to that field for this first Mac release. Leave them empty.
- Deep privacy/agreement checks need an Apple web session, which is not cached on this Mac. API validation alone cannot attest to those checks; review submission is the next server-side gate.
- Machine-readable validation, upload and submission evidence is saved locally in ignored `build/mac-store-readiness/`.

## Repeatable screenshots

```sh
xc-dev build-mac-store-shots
zsh ios/Tools/store-shots/mac-capture.zsh /absolute/path/to/Debug/Attention.app
npm ci --prefix ios/Tools/store-shots
node ios/Tools/store-shots/mac-export.js
```

The capture script also accepts a list of locale codes after the app path. Build products use this checkout's normal Xcode DerivedData directory. Screenshot mode is Debug-only, uses a separate non-syncing demonstration library under the Debug app sandbox's Documents/MacStoreShots directory, and captures only its own windows through ScreenCaptureKit's current-process API. It does not require screen recording access to other apps. Wait for capture completion before exporting.

Raw files are copied into `ios/fastlane/raw/<locale>/mac-*.png`. Final images go to `ios/fastlane/mac-screenshots/<locale>/`, separate from the iOS images. Both are ignored by Git and can be regenerated.

## Updating store materials

```sh
# Preview text updates and screenshot replacement:
zsh ios/Tools/release.sh metadata --mac
# Apply after reviewing the preview:
zsh ios/Tools/release.sh metadata --mac --apply
# Screenshot-only refresh:
zsh ios/Tools/release.sh metadata --mac --screenshots-only --apply
```

`Tools/mac-metadata.py` validates every active locale before writing, checks that the target is MAC_OS, and updates only descriptions, keywords and review instructions. It does not update shared app-info fields, privacy declarations, pricing or the iOS version. The release helper uses the Mac-only screenshot folder for `--mac`.

For the initial upload, `asc screenshots upload --app 6827156660 --version-id 05ee4003-0335-4ec3-bb2a-aacf01643cf5 --platform MAC_OS --path ios/fastlane/mac-screenshots --device-type APP_DESKTOP --skip-existing` allows safe resume without replacing already uploaded images.

## Review and release

```sh
asc validate --app 6827156660 --version-id 05ee4003-0335-4ec3-bb2a-aacf01643cf5 --platform MAC_OS --check-urls
asc versions view --version-id 05ee4003-0335-4ec3-bb2a-aacf01643cf5 --include build,appStoreVersionSubmission
```

The owner releases the version in [App Store Connect](https://appstoreconnect.apple.com/apps/6827156660/distribution/macos/version/inflight) after Apple approves it. Manual release prevents automatic publication after approval. Apple review may require additional answers or changes before that button is available.

## Apple references

- [Adding platforms to an existing app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Cloud-managed signing certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates)
- [Mac App Store security checks replace separate notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

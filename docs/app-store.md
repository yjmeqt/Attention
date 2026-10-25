# iOS App Store submission

Everything needed to create the App Store listing lives in the repo. Pricing and subscriptions are intentionally not set up yet.

## Identifiers

| Item | Value |
|---|---|
| App bundle ID | `com.yijiang.opticshare` |
| Share extension | `com.yijiang.opticshare.share` |
| App Group | `group.com.yijiang.opticshare` |
| Team | `5AT3UN98GQ` (set in `ios/project.yml`) |
| Version | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `ios/project.yml` |

Bundle IDs are permanent once the app is created in App Store Connect.

## Listing copy

`ios/fastlane/metadata/` follows the [fastlane deliver](https://docs.fastlane.tools/actions/deliver/) layout, one folder per locale (`zh-Hans`, `en-US`):

| File | Limit |
|---|---|
| `name.txt` | 30 characters |
| `subtitle.txt` | 30 characters |
| `promotional_text.txt` | 170 characters, editable without a new build |
| `description.txt` | 4000 characters |
| `keywords.txt` | 100 characters, comma-separated, no app name |
| `release_notes.txt` | What's New |
| `support_url.txt`, `privacy_url.txt`, `marketing_url.txt` | **Empty — fill in before submitting** |

Shared files: `copyright.txt`, `primary_category.txt` (Utilities), `secondary_category.txt` (Productivity), and `review_information/notes.txt` (instructions for App Review).

Upload with `fastlane deliver --skip_binary_upload --skip_screenshots` from `ios/`, or paste the text into App Store Connect by hand.

## Screenshots

1. `ios/Tools/capture-screenshots.sh` builds the Debug app, creates two simulators (iPhone 17 Pro Max, 6.9-inch, and iPad Pro 13-inch) and captures every scene in both locales into `ios/fastlane/raw/`. Scenes are driven by Debug-only launch arguments: `-demoURL <link>` generates a card on launch and `-demoStyle YES` opens the Style sheet.
2. `ios/Tools/frame-screenshots.swift` adds the caption and background and writes the upload-ready images to `ios/fastlane/screenshots/<locale>/`. Captions are defined at the top of that script.

Sizes: iPhone 1320 × 2868, iPad 2064 × 2752. Those are the only sizes App Store Connect requires; smaller devices are scaled from them.

The capture needs network access, because the demo links are unfurled live.

## Privacy

- **Privacy manifest**: `ios/App/PrivacyInfo.xcprivacy` and `ios/ShareExtension/PrivacyInfo.xcprivacy`. No tracking, no collected data; UserDefaults is declared with reasons `CA92.1` (app-only) and `1C8F.1` (App Group).
- **App Privacy questionnaire**: answer **Data Not Collected**. Links are fetched from the device and never sent to the developer.
- **Privacy policy**: `docs/privacy-policy.md` (Chinese and English). It must be published at a public URL and that URL put in `privacy_url.txt`. The repo is private, so use GitHub Pages from a public repo, a Gist, or any static host.
- **Permission prompts**: camera (QR scanning) and adding to Photos, in English and Simplified Chinese (`InfoPlist.strings`).

## Age rating and export compliance

- **Age rating**: all content questions "None". The app is not a web browser: it shows page titles and preview images of links the user chooses, so "Unrestricted Web Access" is **No**. Expect 4+.
- **Encryption**: the app uses only HTTPS through system APIs, which is exempt. `ITSAppUsesNonExemptEncryption` is already `NO` in the Info.plist, so App Store Connect won't ask on every build.

## Before the first submission

- [ ] Publish the privacy policy and a support page; fill in the URLs
- [ ] Create the app in App Store Connect with the bundle ID above (primary language: Simplified Chinese)
- [ ] Run the screenshot scripts and review the output
- [ ] Archive with the Release configuration and upload (Xcode Organizer or `xcodebuild -exportArchive`)
- [ ] Fill in App Privacy, age rating, category and review notes
- [ ] Pricing and availability (not decided yet)

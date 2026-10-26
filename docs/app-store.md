# iOS App Store submission

Everything needed to create the App Store listing lives in the repo. Pricing and subscriptions are intentionally not set up yet.

## Identifiers

| Item | Value |
|---|---|
| App bundle ID | `com.yijiang.attention` |
| Share extension | `com.yijiang.attention.share` |
| App Group | `group.com.yijiang.attention` |
| Team | `5AT3UN98GQ` (set in `ios/project.yml`) |
| Version | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `ios/project.yml` |

Bundle IDs are permanent once the app is created in App Store Connect.

## Listing copy

`ios/fastlane/metadata/` follows the [fastlane deliver](https://docs.fastlane.tools/actions/deliver/) layout, one folder per locale: Simplified Chinese (`zh-Hans`), English (`en-US`), Korean (`ko`), Japanese (`ja`), Russian (`ru`), Vietnamese (`vi`), Arabic (`ar-SA`), French (`fr-FR`), German (`de-DE`) and Spanish (`es-ES`, `es-MX`):

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

**Status: to be redone before the first submission.** The scenes, captions and scripts below still describe the old card-maker app. Redo them once the library UI stops changing.

Plan, five scenes for iPhone (1320 × 2868) and iPad (2064 × 2752), positioned around "keep the links you care about":

1. Home feed, the waterfall of link previews
2. Saving from any app through the share sheet (captured by hand from Safari)
3. Item detail: the card with its templates and aspect ratios
4. Tags, filters and search
5. Private and Archived

How to rebuild the pipeline:

- Fill the library with the Debug-only `-demoLinks "https://a https://b"` launch argument (newest first, only when the library is empty, needs network access). Add `-seenShareGuide YES` to skip the first-launch guide. Avoid links that don't unfurl reliably, such as bilibili.
- The simulators are `Attention-Shots-iPhone` (iPhone 17 Pro Max), `Attention-Shots-iPad` (iPad Pro 13-inch) and `Attention-Shots-Duo` (iPhone Duo). App Store Connect has no foldable size class, so Duo images are for marketing only (`ios/fastlane/extra/`).
- Rewrite the scenes in `ios/Tools/capture-screenshots.sh` and the captions in `ios/Tools/frame-screenshots.swift` (10 locales; `es-MX` reuses `es-ES`). The old `-demoURL`, `-demoStyle`, `-demoHistory` and `-demoNoAutoShare` arguments no longer exist.
- Update `description.txt`, `subtitle.txt`, `keywords.txt` and `promotional_text.txt` in every locale to the library positioning at the same time.

## Design decisions

- **App icon**: keep the current one.
- **Paste button**: keep the system `PasteButton`, which pastes without the "Allow Paste" prompt. Its size is fixed, so it is an icon-only circle next to Scan on the left. On iPhone Duo the toolbar moves to a column on the right and the paste button can't go there, so it floats at the bottom left.
- **Filters**: Archived and Private are toggles at the top right. Site and tag chips show only while searching, or while one of them is on.

## Privacy

- **Privacy manifest**: `ios/App/PrivacyInfo.xcprivacy` and `ios/ShareExtension/PrivacyInfo.xcprivacy`. No tracking, no collected data; UserDefaults is declared with reasons `CA92.1` (app-only) and `1C8F.1` (App Group).
- **App Privacy questionnaire**: answer **Data Not Collected**. Links are fetched from the device and never sent to the developer.
- **Privacy policy**: `docs/privacy-policy.md` (Chinese and English). It must be published at a public URL and that URL put in `privacy_url.txt`. The repo is public, so GitHub Pages from this repo works, as does a Gist or any static host.
- **Permission prompts**: camera (QR scanning) and adding to Photos, in all listed languages (`InfoPlist.strings`).

## Age rating and export compliance

- **Age rating**: all content questions "None". The app is not a web browser: it shows page titles and preview images of links the user chooses, so "Unrestricted Web Access" is **No**. Expect 4+.
- **Encryption**: the app uses only HTTPS through system APIs, which is exempt. `ITSAppUsesNonExemptEncryption` is already `NO` in the Info.plist, so App Store Connect won't ask on every build.

## Before the first submission

- [ ] Publish the privacy policy and a support page; fill in the URLs
- [ ] Create the app in App Store Connect with the bundle ID above (primary language: Simplified Chinese)
- [ ] Redo the screenshots and store text (see Screenshots) and review the output
- [ ] Archive with the Release configuration and upload (Xcode Organizer or `xcodebuild -exportArchive`)
- [ ] Fill in App Privacy, age rating, category and review notes
- [ ] Pricing and availability (not decided yet)

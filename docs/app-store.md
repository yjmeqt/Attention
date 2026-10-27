# iOS App Store submission

Everything needed to create the App Store listing lives in the repo. Pricing and subscriptions are intentionally not set up yet.

## Identifiers

| Item | Value |
|---|---|
| App bundle ID | `com.yjmeqt.attn` (Release; Debug builds use `com.yjmeqt.attn.dev`) |
| Share extension | `com.yjmeqt.attn.share` |
| App Group | `group.com.yjmeqt.attn.shared` |
| Team | `M3V5P234X3` (set in `ios/project.yml`) |
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
| `support_url.txt`, `privacy_url.txt`, `marketing_url.txt` | Support and privacy point at the GitHub Pages site; marketing is empty |

Shared files: `copyright.txt`, `primary_category.txt` (Utilities), `secondary_category.txt` (Productivity), and `review_information/notes.txt` (instructions for App Review).

Push the text and screenshots with `Tools/release.sh metadata` (see Releasing).

## Releasing

`ios/Tools/release.sh` wraps the [asc](https://github.com/rorkai/App-Store-Connect-CLI) CLI (`brew install asc`). It needs an App Store Connect API key once per Mac: create one under **Users and Access → Integrations → App Store Connect API** (App Manager role), then run `asc auth login` with its key ID, issuer ID and `.p8` file. The key lives in the keychain, not the repo.

| Command (from `ios/`) | What it does |
|---|---|
| `Tools/release.sh beta` | Sets `CURRENT_PROJECT_VERSION` to the next free build number, archives Release, exports an IPA to `build/release/` and uploads it to TestFlight, waiting for processing. Commit the bump afterwards |
| `Tools/release.sh beta --group "Public" --notes "…"` | Same, then adds the build to that beta group, sets What to Test (en-US) and notifies testers |
| `Tools/release.sh beta --no-upload` | Archive and export only, keeping the local build number |
| `Tools/release.sh metadata` | Plan only: validates `fastlane/metadata`, then shows what the text import and screenshot upload would change on the App Store version matching `MARKETING_VERSION` |
| `Tools/release.sh metadata --apply` | Pushes it. Screenshots replace each locale's iPhone 6.9" (`iphone-*`) and iPad 13" (`ipad-*`) sets |

The App Store version itself (for example 1.0) has to exist in App Store Connect before `metadata` can target it. Locales that have no version localization yet are created by the text import, so a first `--apply` may need a second run to upload their screenshots.

## TestFlight

Internal testing needs nothing beyond an uploaded build. External testing needs the fields below in **TestFlight → Test Information**, and the first build of each version goes through Beta App Review (usually under a day).

| Field | Value |
|---|---|
| Beta App Description | below |
| Feedback Email | the address testers' screenshots and comments go to |
| Privacy Policy URL | `https://yjmeqt.github.io/Attention/privacy-policy.html` |
| Marketing URL | leave empty |
| Beta App Review contact | name, phone and email of whoever Apple should call |
| Sign-in required | No |
| Review notes | `ios/fastlane/metadata/review_information/notes.txt` |

Beta App Description (English is the primary language; add Simplified Chinese as a second localization):

> Attention keeps the links you care about. Share a page from Safari, YouTube, X or any app, or paste a link, and it's saved with its title and cover. Any saved link can be sent as an image card with a QR code, so it previews properly in WeChat.

> Attention 帮你收藏想留下的链接。在 Safari、YouTube、X 等 App 里点分享，或直接粘贴链接，就会连同标题和封面一起保存下来。任何一条链接都能生成带二维码的图片卡片，发到微信里也能看到预览。

What to Test (per build):

> Save links by sharing from other apps and by pasting. Open an item: Open is the main button, and Share offers Share Link, Copy Link and Share as Image. Try the Card, Text and QR templates. On a fresh install the share-sheet guide plays through once before it can be closed. Report links that show no preview.

> 通过其他 App 的分享菜单和粘贴保存链接。打开一条：主按钮是“打开”，“分享”里有分享链接、复制链接和分享为图片。试试卡片、文字和二维码三种模板。首次安装时，分享菜单引导要看完一遍才能关掉。没有预览的链接请反馈给我们。

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
- **Paste button**: a plain toolbar button next to Scan, so the two look the same. The system paste control pastes without the "Allow Paste" prompt, but it forces a solid background that can't match the glass, so it was dropped; iOS asks before each paste unless the user allows pasting in Settings.
- **Filters**: Archived and Private are in the More menu; while one is open, a prominent button for it sits beside More and closes it. Site and tag chips sit just above the search field, only while searching or while one of them is on.

## Privacy

- **Privacy manifest**: `ios/App/PrivacyInfo.xcprivacy` and `ios/ShareExtension/PrivacyInfo.xcprivacy`. No tracking, no collected data; UserDefaults is declared with reasons `CA92.1` (app-only) and `1C8F.1` (App Group).
- **App Privacy questionnaire**: answer **Data Not Collected**. Links are fetched from the device and never sent to the developer.
- **Privacy policy and support page**: `docs/privacy-policy.md` and `docs/support.md` (Chinese and English), published by GitHub Pages from `docs/` on `main` at `https://yjmeqt.github.io/Attention/privacy-policy.html` and `https://yjmeqt.github.io/Attention/support.html`. `docs/_config.yml` keeps the other docs off the site.
- **Permission prompts**: camera (QR scanning) and adding to Photos, in all listed languages (`InfoPlist.strings`).

## Age rating and export compliance

- **Age rating**: all content questions "None". The app is not a web browser: it shows page titles and preview images of links the user chooses, so "Unrestricted Web Access" is **No**. Expect 4+.
- **Encryption**: the app uses only HTTPS through system APIs, which is exempt. `ITSAppUsesNonExemptEncryption` is already `NO` in the Info.plist, so App Store Connect won't ask on every build.

## Before the first submission

- [x] Publish the privacy policy and a support page; fill in the URLs
- [x] Create the app in App Store Connect with the bundle ID above (primary language: English)
- [ ] China mainland availability needs an ICP filing number (App 备案)
- [ ] Redo the screenshots and store text (see Screenshots) and review the output
- [x] Archive with the Release configuration and upload; 1.0 (2) is the build for the public TestFlight link. `Tools/release.sh beta` does this and bumps `CURRENT_PROJECT_VERSION`
- [ ] Fill in App Privacy, age rating, category and review notes
- [ ] Pricing and availability (not decided yet)

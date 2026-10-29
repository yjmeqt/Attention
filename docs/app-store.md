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

`ios/fastlane/metadata/` follows the [fastlane deliver](https://docs.fastlane.tools/actions/deliver/) layout, one folder per locale: English (`en-US`, the primary language), Simplified Chinese (`zh-Hans`), Korean (`ko`), Japanese (`ja`), Russian (`ru`), Vietnamese (`vi`), Arabic (`ar-SA`), French (`fr-FR`), German (`de-DE`) and Spanish (`es-ES`, `es-MX`):

| File | Limit |
|---|---|
| `name.txt` | 30 characters |
| `subtitle.txt` | 30 characters |
| `promotional_text.txt` | 170 characters, editable without a new build |
| `description.txt` | 4000 characters |
| `keywords.txt` | 100 characters, comma-separated, no app name |
| `release_notes.txt` | What's New |
| `support_url.txt`, `privacy_url.txt`, `marketing_url.txt` | Support and privacy point at the GitHub Pages site; marketing is empty |

The listing pitches one library per market. Every locale but Simplified Chinese leads with all your links from every app and site in one place, with no feed, no algorithm and no tracking; cards and QR codes come last. Simplified Chinese leads with sending YouTube and X links to WeChat, which shows them as a bare URL, as image cards with title, cover and QR code. The app's empty screen follows the same split. Keywords leave out third-party names (YouTube, X, WeChat), per guideline 2.3.7. Plain "Attention" belongs to another developer, so every name adds a localized tail: "Attention – All Your Links" in English and its equivalents, "Attention – 链接转图片卡片" in Simplified Chinese (1.0 shipped as "Attention – Save & Share Links" everywhere). Subtitles avoid repeating the name's words, since both are indexed.

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
| `Tools/release.sh metadata --apply` | Pushes it. Screenshots replace each locale's iPhone 6.9" (`iphone-*`), iPhone 6.3" (`iphone63-*`), iPad 13" (`ipad-*`) and iPhone Duo (`duo-*`, inner then outer display) sets. The Duo set needs asc 5.12 or later |

The App Store version itself (for example 1.0) has to exist in App Store Connect before `metadata` can target it. Locales that have no version localization yet are created by the text import, so a first `--apply` may need a second run to upload their screenshots.

### Xcode Cloud

TestFlight builds can also come from Xcode Cloud, which signs with the team's cloud-managed certificates, so nothing is stored in the repo or on a Mac. `ios/ci_scripts/ci_pre_xcodebuild.sh` sets `CURRENT_PROJECT_VERSION` to Xcode Cloud's build number before each archive.

One-time setup:

1. In Xcode, **Product → Xcode Cloud → Create Workflow**, pick the `Attention` product, and grant Xcode Cloud access to `yjmeqt/Attention` on GitHub when asked.
2. Edit the default workflow: start condition **Branch Changes** on `main` (or **Manual** only), action **Archive** with platform iOS, scheme `Attention`, deployment preparation **TestFlight and App Store** (Internal Testing Only builds can't go to the public link), and a post-action **TestFlight Internal Testing** to the internal group, plus **TestFlight External Testing** if builds should reach the public link.
3. In App Store Connect, **Xcode Cloud → Settings → Build Number**, set the next build number above the latest upload (3 or higher after 1.0 (2)).

After that, merging to `main` produces a TestFlight build. To start one from the terminal: `asc xcode-cloud run --app 6827156660 --workflow "<workflow name>" --branch main --wait`. `MARKETING_VERSION` still comes from `project.yml`; `Tools/release.sh metadata` is unchanged.

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

> Attention keeps all your links from every app and site in one place, with no feed, no algorithm and no tracking. Share a page from Safari, YouTube, X or any app, or paste a link, and it's saved with its title and cover. Any saved link can also be sent as an image card with a QR code.

> Attention 帮你收藏想留下的链接。在 Safari、YouTube、X 等 App 里点分享，或直接粘贴链接，就会连同标题和封面一起保存下来。任何一条链接都能生成带二维码的图片卡片，发到微信里也能看到预览。

What to Test (per build):

> Save links by sharing from other apps and by pasting. Open an item: Open is the main button, and Share offers Share Link, Copy Link and Share as Image. Try the Card, Text and QR templates. On a fresh install the share-sheet guide plays through once before it can be closed. Report links that show no preview.

> 通过其他 App 的分享菜单和粘贴保存链接。打开一条：主按钮是“打开”，“分享”里有分享链接、复制链接和分享为图片。试试卡片、文字和二维码三种模板。首次安装时，分享菜单引导要看完一遍才能关掉。没有预览的链接请反馈给我们。

## Screenshots

Five per device, in the order the App Store shows them; people mostly see the first three. Every language but Simplified Chinese pitches one library for links from every site, with no feed and no tracking:

1. `feed`: the home feed, all your links in one place
2. `share`: Safari's own share sheet with Attention in its app row, saving from any app
3. `private`: Private unlocked with Face ID; no algorithm, no tracking
4. `search`: search results, find it by site
5. `detail`: the item detail with its card, share it as a card, text or QR code

Simplified Chinese pitches sending YouTube and X links to WeChat, which shows them bare:

1. `compare`: a bare link in a chat bubble, then the same link as a card (no app screen)
2. `detail`, 3. `share`, 4. `template` (the Text template), 5. `search`

| Device | Size | App Store Connect slot |
|---|---|---|
| `iphone` (iPhone 17 Pro Max) | 1320 × 2868 | iPhone with Dynamic Island, large display |
| `iphone63` (same frame, scaled) | 1206 × 2622 | iPhone with Dynamic Island, medium display (**required**) |
| `ipad` (iPad Pro 13-inch, landscape) | 2752 × 2064 | iPad 13-inch display (required for iPad apps) |
| `duo` (iPhone Duo, inner display) | 2007 × 2853 | iPhone Duo inner display (optional until April 2027; shows the "optimized for iPhone Duo" badge) |
| `duo-cover` (iPhone Duo, outer display) | 1398 × 2034 | iPhone Duo outer display (same simulator, folded shut) |

Pipeline, run from `ios/` (the export needs Google Chrome and `npm install` in `Tools/store-shots` once):

```
zsh Tools/store-shots/capture.zsh                 # raw screens into fastlane/raw (ONLY="en-US ko", DEVICES="ipad duo", SCENES="share" for a subset)
node Tools/store-shots/export.js                  # framed shots into fastlane/screenshots, headers into fastlane/headers
node Tools/store-shots/export.js screenshots duo ar-SA   # one device and locale; "headers" renders only the headers
```

- The capture script builds the Debug app named Attention (into `build/store-shots`), drives the `Attention-Shots-*` simulators, and reinstalls the app for every scene, filling the library with the Debug-only launch arguments in `Shared/Library/DemoLibrary.swift`: `-demoLinks` (needs network access), `-demoSearch Apple`, `-demoOpen 0`, `-demoPrivate` with `-demoUnlockPrivate YES` (the script enrolls Face ID and sends a matching face). `-seenShareGuide YES` skips the first-launch guide. It boots each simulator in the locale's language, since the share sheet is drawn by the system, and empties the clipboard so the "You copied a link" banner stays away.
- Content: outside Simplified Chinese the library is Apple and Wikipedia pages only (the locale's Bauhaus article, Apple's iPhone, Music, Maps, Keynote, Swift, Podcasts and HIG pages), so no third-party content or people appear. Russian uses the US storefront, whose Apple pages preview. Traditional Chinese shares Apple's Swift page, since Chinese Wikipedia shows a sitenotice. Simplified Chinese shows a 3Blue1Brown YouTube video, its pitch, and Apple's Chinese pages; on iPad and the Duo's inner display it shares Apple's Swift page, since desktop YouTube shows faces in its sidebar.
- The iPad is rotated to landscape and the Duo unfolded or folded with the argent CLI, which also takes the Duo's screenshots (`simctl` doesn't capture a folded device's panel) and does the taps.
- Design: Constructivism. Paper (`#ece2cd`), ink and red (`#d4261b`), a red wedge and a black diagonal bar, a heavy headline tilted −8° with its second half in red, and a monospaced subline (each script's own Noto face where the mono font doesn't cover it). The device shows the real, unedited app screen. Arabic is mirrored. Headlines and sublines live in `Tools/store-shots/copy.js` (11 locales; `es-MX` reuses `es-ES`); the layout, with each language's line-breaking rules, is `frame.html`. The exporter renders each frame at an exact App Store size and writes PNGs with no alpha channel.
- Product page header (21:9, 3840 × 1646): `header.html`, in the same style, with the first screenshot's headline and generic link cards (no real site, logo or URL). Everything that matters sits in the middle 60%, since devices crop the edges. App Store Connect takes headers in its Asset Library, which needs an approved version; `release.sh` doesn't upload them.
- Neither the raw nor the framed images are in git: run the pipeline to regenerate them before uploading. Look through every image first: a link that failed to unfurl shows as a bare tile, and Safari sometimes shows the wrong page under the share sheet. Rerun just that scene with `SCENES`, `ONLY` and `DEVICES`.
- Upload with `Tools/release.sh metadata --apply` (see Releasing), or by hand in App Store Connect: drag each device's files into its slot, and both Duo displays into the one iPhone Duo slot.

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
- [x] Redo the store text for the library positioning
- [ ] Review the regenerated screenshots (see Screenshots) and upload them (`Tools/release.sh metadata --apply`)
- [x] Archive with the Release configuration and upload; 1.0 (2) is the build for the public TestFlight link. `Tools/release.sh beta` does this and bumps `CURRENT_PROJECT_VERSION`
- [ ] Fill in App Privacy, age rating, category and review notes
- [ ] Pricing and availability (not decided yet)

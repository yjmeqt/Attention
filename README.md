<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/icon-dark.png">
    <img src="docs/images/icon-default.png" alt="OpticShare app icon" width="128" height="128">
  </picture>
</p>

# OpticShare

Links from YouTube, X and many other sites show up in WeChat as a bare URL, with no title and no thumbnail. OpticShare unfurls the link on the device, renders a card image with the title, cover, site icon and a QR code, copies the cleaned link, and hands both to the system share sheet.

中文：让微信也能"预览"链接。把 YouTube、X、B 站和各类网页链接变成带标题、封面和二维码的图片卡片。

## Repository layout

| Path | Platform | Status |
|---|---|---|
| [`ios/`](ios) | iOS 26+, iPhone, iPad and iPhone Duo (SwiftUI, Swift 6) | Main app, feature complete for 1.0 |
| [`android/`](android) | Android 12+ (Kotlin, Jetpack Compose, Material 3) | In progress |
| [`docs/`](docs) | App Store preparation, privacy policy | |

HarmonyOS is planned as a sibling `harmony/` folder. Each platform is a self-contained native project; behaviour is kept in sync by porting from the iOS implementation, which is the reference.

## How it works

1. **Unfurl**: site-specific sources first (YouTube oEmbed, Bilibili's public API, FxTwitter for X), then the page's Open Graph and Twitter tags, then the system link-metadata provider as a fallback. Pages that answer with a captcha or login wall are detected and get a QR-only card instead of a broken preview.
2. **Icon**: the page's `apple-touch-icon` or largest `rel=icon`, then `/apple-touch-icon.png` and `/favicon.ico`, upgraded from Google's favicon service when the result is tiny.
3. **Render**: one of four templates (hero image, post, minimal text, QR) chosen from the link type and the cover image's shape, in 4:5, 1:1 or 9:16, rendered at 1080 px wide. The card text is always Simplified Chinese, because it's read in WeChat.
4. **Share**: tracking parameters are stripped (`youtu.be/ID` for YouTube, no query for X, no `utm_*` elsewhere), the link goes to the clipboard and the image to the share sheet.

Everything runs on the device. There is no backend and no account.

## iOS

Requirements: Xcode 27.1, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd ios
xcodegen generate          # regenerate OpticShare.xcodeproj after changing project.yml or adding files
open OpticShare.xcodeproj
```

Command-line builds put their output in the repo-level `build/` folder, which is git-ignored:

```sh
xcodebuild -project OpticShare.xcodeproj -scheme OpticShare \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath ../build/ios build
```

| Target | What it is |
|---|---|
| `OpticShare` | The app (`App/`, plus everything in `Shared/`) |
| `OpticShareExtension` | Share extension, so links can be shared from Safari, YouTube, X, etc. (`ShareExtension/`) |
| `OpticShareTests` | Swift Testing suites (`Tests/`) |

- Code shared by the app and the extension lives in `Shared/`. They exchange history through the App Group `group.com.yijiang.opticshare`.
- Signing uses automatic provisioning with team `5AT3UN98GQ`. To build under a different Apple ID, change `DEVELOPMENT_TEAM` and the bundle ID prefix in `project.yml`.
- UI strings are in `Shared/Localizable.xcstrings` (English source, Simplified Chinese). The app icon is an Icon Composer document (`App/OpticShare.icon`), so iOS derives the dark, tinted and clear appearances itself.

Tests: the `UnfurlTests` suite fetches about 30 real Chinese and US sites, so it needs network access and is slow. Run everything else with:

```sh
xcodebuild test -project OpticShare.xcodeproj -scheme OpticShare -destination 'platform=iOS Simulator,name=<simulator>' \
  -derivedDataPath ../build/ios -skip-testing:OpticShareTests/UnfurlTests
```

## Android

Requirements: JDK 17 and the Android SDK (platform 36), or simply Android Studio.

```sh
cd android
./gradlew assembleDebug testDebugUnitTest
./gradlew installDebug     # to a running emulator or device
```

Package and application ID: `com.yijiang.opticshare`. The launcher icon is an adaptive icon with a monochrome layer for themed icons.

## Docs

- [App Store submission](docs/app-store.md): identifiers, listing copy, screenshots, privacy answers, checklist
- [Privacy policy](docs/privacy-policy.md): needs to be published at a public URL before submission

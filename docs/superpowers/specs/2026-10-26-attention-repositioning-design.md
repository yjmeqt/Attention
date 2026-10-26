# Repositioning: Collect your attention (iOS)

Attention is a place to collect what caught your eye during the day and sort it at night. Share cards
are a by-product, not the point, and WeChat is no longer the story. This covers three changes, each
its own PR: sharing, templates, copy. Android ports them later.

## 1. Sharing

Three actions replace the single Share:

| Action | Does |
|---|---|
| Share Link | System share sheet with the cleaned link only |
| Copy Link | Copies the cleaned link; shows "Link copied" |
| Share as Image | System share sheet with the card image, and copies the link as today |

- `ItemActions` gets `shareLink`, `copyLink` and `shareImage` (today's `share`). `linkCopied`
  becomes a message so the bottom notice can say which: "Link copied" for Copy Link, the current
  "Link copied — paste it after the image." for Share as Image.
- Image items (no link) only have Share as Image, so wherever the three would show they get a single
  Share button instead.
- App detail page bottom bar: **Open** is the prominent button (when the item has a link and apps can
  be opened), next to a **Share** menu with the three actions. Without a link: a single Share button.
- Share extension bottom bar: the **Share** menu stays prominent, next to **Done**.
- Long-press menu: the Share button becomes a Share submenu with the three actions.

## 2. Templates

- `CardTemplate` keeps `auto`, `tile` (Card), `minimal` (Text), `qr`. `hero` (Image) and `post` are
  removed with their files. Unknown raw values, including stored `hero` and `post`, decode as `auto`.
- `CardAspect` and the aspect picker are removed. `CardStyle` is just the template; an old `aspect`
  key in saved JSON is ignored.
- Every template is 360 pt wide (1080 px at 3x) and as tall as its content, measured the way the tile
  is today. Text and QR swap their flexible `Spacer`s for fixed spacing. `CardMetrics` keeps only
  the values Text and QR use (today's 4:5 values).
- `LibraryItem.aspectRaw` stays as an unused stored property to avoid a SwiftData migration in the
  shared App Group store. New items write `"portrait"` to it. `thumbnailAspect` is unaffected: it
  already comes from the cover image.
- The detail page placeholder (before the card renders) uses a 4:5 box.
- Tests: card rendering runs per template instead of per template × aspect; the QR decode test runs
  once.

## 3. Copy

Tone: quiet, a little literary, for someone who collects during the day and sorts at night. No
feature lists in the headline, no WeChat.

- Tagline: **Collect your attention.** / **收集你的注意力。** Empty-state title and App Store
  subtitle.
- Empty state body: one sentence about the day's scattered attention, kept for later.
- Empty state steps:
  1. Keep anything, from anywhere — share from any app, or paste a link
  2. Sort it at night — tags, search and Private
  3. Pass it on — send the link, or a card
- App Store description, subtitle, keywords and promotional text: rewritten in English and Chinese
  first for review, then translated to the other 8 locales. Review notes stay accurate to the flow.
- Unchanged: the share sheet guide, the privacy policy, card text.

## Out of scope

Android, screenshots (redone after these land, per `docs/app-store.md`), the app name.

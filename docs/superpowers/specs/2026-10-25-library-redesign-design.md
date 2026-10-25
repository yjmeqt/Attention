# Library redesign (iOS)

Attention becomes a link library that also makes share cards. Everything shared in or pasted is
saved first; sharing is an explicit action.

## Items

A `LibraryItem` is either a **link** (URL + unfurled metadata + card style) or an **image**
(a shared image with no link QR code). Stored with SwiftData in the App Group container so the app
and the share extension both write to it; binary data (cover, avatar, icon, source image,
thumbnail) lives in files under `Library/<id>/`.

- Dedupe key: cleaned URL for links, SHA-256 of the image for images. Re-adding updates the
  existing item and keeps its tags.
- Fields: style (template, aspect), manual tags, `isPrivate`, `ocrText`, created/updated dates.
- Automatic tag = normalized domain (`www.`/`m.` stripped; `youtu.be` → `youtube.com`,
  `b23.tv` → `bilibili.com`, `xhslink.com` → `xiaohongshu.com`, `twitter.com` → `x.com`).
  Image items get the fixed "Images" tag. Automatic tags are derived, not stored.
- Cap: 5,000 items; the oldest non-private items are removed first.
- The old `History/index.json` is imported once on first launch.

## Intake

`Intake.capture(from:)` turns share-extension items, paste or drop providers, or typed text into a
`Capture`:

1. If an attachment is an image: downsample to ≤ 2048 px, read QR codes with Vision. A QR
   code with a web link → link capture with the image as its source image; otherwise an
   image capture.
2. Otherwise the first web link in URLs, text, or raw item types (existing behaviour).

Saving happens before any network work: the item is written immediately, then unfurled, then
(for images) OCR'd, updating the item each time. When a page has no og image, the source image
is the cover. When it has no title, the OCR title is used.

OCR: Vision text recognition, accurate, automatic language detection. Title = the tallest
1–2 lines in the top half, skipping boilerplate (小红书, 扫码, 长按识别, lines starting with @).
The full text is stored for search.

## Home screen

- Input bar (paste, type, scan QR) and the clipboard banner, as today.
- Filter bar: All · domains · #tags · 🔒 Private. Multiple selected tags are ANDed. Search
  matches title, URL and OCR text.
- Staggered feed: 2 columns on compact width, 3–4 on wider screens. Built from N lazy columns,
  each item assigned to the shortest column using its known aspect ratio.
- Tap → detail page. Long press → Open in App, Open in Browser, Share, Edit Tags, Move to /
  Remove from Private, Only this domain/tag, Select, Delete.
- Select mode: add tag, move to Private, delete (no bulk share).
- Empty library shows the existing onboarding (sample card, steps, share-sheet guide).

## Detail page

Shared by the app and the share extension.

- Link: the card, template and aspect pickers inline, title, link, tags.
- Image: the image, recognized text (copyable), tags.
- Actions: Share (card image; link copied to the clipboard as today), Open (app or browser, app
  only), Tags, Private, Delete.
- Share extension: the bottom bar is **Share** and **Done**. The item is already saved, so
  closing or swiping down keeps it. No automatic share sheet.

## Private

Private items are hidden from every filter except Private. Opening Private requires
`deviceOwnerAuthentication` (Face ID / Touch ID, passcode fallback) every time; it locks when
the filter changes or the app leaves the foreground, and the feed is covered while inactive.
Adding to Private needs no authentication; removing does. Private item files use
`FileProtectionType.complete`. A paid Pro unlock may gate adding to Private later.

## Out of scope

Android, bulk share, collections, Pro purchase.

## Testing

Unit tests: domain normalization, dedupe (URL and image hash), cap, private filtering, history
import, OCR title heuristic, QR reading from a generated image. Manual: simulator run of the
feed, detail, share extension (URL, text, image with and without QR), and Face ID (simulated).

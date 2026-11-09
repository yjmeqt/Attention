# App Store search creative experiment

Prepared on 9 November 2026 for Attention (`6827156660`).

The English creative leads with saving and rediscovering links. Simplified Chinese leads with saving links and sharing image cards. Both use the existing paper, ink and red palette and real app screenshots. The experiment changes only search-result creative assets, keeping listing text, icons and screenshots as the control.

## Regenerate

From the repository root:

```sh
node ios/Tools/store-shots/search-export.js
```

Requires the existing `ios/Tools/store-shots` npm dependencies and Google Chrome (`CHROME` can override its path). Raw inputs are `ios/fastlane/raw/en-US/iphone-1-feed.png` and `ios/fastlane/raw/zh-Hans/iphone-3-detail.png`. These captures are local files, not committed assets. The exporter fails if either image cannot decode.

Outputs are `ios/fastlane/search-results/search-en-US.png` and `search-zh-Hans.png`: 3840 × 2560, 3:2, opaque PNG. Inspect both before uploading. Generated files and ASC receipts are ignored by Git.

## ASC resources

| Resource | ID |
|---|---|
| PPO experiment, 50% treatment traffic | `f6976f09-e5c1-4eb2-be98-182ac72d7edc` |
| Treatment | `e905c1e8-9fd0-40ab-983b-15a99761a421` |
| English treatment localization | `46a483bd-7186-4505-a68b-0df26917290d` |
| Simplified Chinese treatment localization | `85776018-f18f-4acc-b4a7-8281f4f83fd7` |
| English image | `69800019-6ee2-84b4-802f-ac461796325a` |
| Simplified Chinese image | `96800019-6ee2-84b4-8034-0571de1b85c2` |
| Review submission | `c72b38aa-819f-44c9-8b36-4ae1c0a7366c` |

Images are assigned to `APP_STORE_SEARCH_RESULTS_ASSET` on treatment localizations, not the default version. Submit the experiment with its assets; do not also add the same images as standalone review items, which locks them out of experiment review. Approval and experiment start are separate from upload. Read current state from ASC before making further changes.

Compare download conversion against the original in PPO; no improvement is assumed. Search creative assets appear on iOS/iPadOS 27 and later; retain screenshots for other clients. See [Apple's asset guidance](https://developer.apple.com/app-store/asset-best-practices/).

Validation: both outputs rendered and visually inspected; dimensions and absence of alpha verified with `sips`; exporter syntax checked with `node --check`.

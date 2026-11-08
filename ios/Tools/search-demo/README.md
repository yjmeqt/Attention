# Search test library

For a live preview test, run `zsh ios/Tools/search-demo/run-real.zsh`. It launches a separate
in-memory library with eight real NASA, GitHub, and Apple links. The app fetches each page and
its OG image, so this mode needs network access. Try searching for `Mars`, `Swift`, `NASA`,
`GitHub`, or `Apple`. Link content can change, so these results have no fixed expected count.
The live mode uses the same worktree simulator and does not sync to iCloud.

For deterministic search-count tests, use the offline corpus below.

Run `zsh ios/Tools/search-demo/run.zsh` from the worktree root. This builds Attention in the
`smart-search` worktree's own iPhone simulator and starts a **separate in-memory library**.
It never syncs the fixture to iCloud and seeds the same data each time you run the script.
Launching the app normally returns to the ordinary library; the fixture is in memory only.

The library contains 204 offline items: 192 synthetic links across eight sites and six
topics, plus 12 symbolic images. Each topic includes Chinese and English titles, authors,
keywords, visual labels, and one OCR phrase. Dates are relative to launch time. Eight
Fashion links are Private; eight Music links are Archived. The fake link paths are intended
for search testing and generally do not open real pages.

`catalog.csv` lists every item. `questions.csv` contains 112 questions and the expected
count when the model produces the listed filters. Start with these checks:

| Question | Scope | Expected |
| --- | --- | ---: |
| 我的收藏一共有多少条？ | All Items | 188 |
| 我收藏了多少个来自 GitHub 的链接？ | All Items | 22 |
| 过去24小时我收藏了多少个 GitHub 链接？ | All Items | 12 |
| #Programming 有多少条收藏？ | All Items | 34 |
| GitHub 的 #Programming 收藏有多少条？ | All Items | 4 |
| 过去24小时 GitHub 的 #Programming 有多少条？ | All Items | 2 |
| 归档里有多少条？ | Archived | 8 |
| 私密收藏有多少条？ | Private, unlocked | 8 |

The counts are deterministic **after the question has been translated to the intended
QueryPlan**. A different count may mean the model chose different filters, or the matcher
returned the wrong items. Inspect the chips on the Ask card to distinguish the two.
`questions.json` carries the same questions for the automated count check. Visual questions
list a baseline count from labels only; MobileCLIP can widen the result.
The 12 symbolic images are useful for UI and label fallback checks, but are not a photo
recognition benchmark. `generate.py` regenerates both CSV files and the bundled JSON from
the same source definitions.

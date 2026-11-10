# 市场配置复盘

2026 年 11 月 10 日。对象是仓库里所有"对外"的配置：App Store Connect 的文本和共享字段、截图与头图流水线、发布脚本、GitHub Pages 站点、隐私政策、Mac 和 Android 的上架材料，以及 App 内自带的宣传面。[定位复盘](positioning-review.md)已经讲过文案应该怎么写，这里不重复，只看配置层面：哪里不一致、哪里会出事、哪里缺了。

## 一句话结论

数字层面没有问题：12 个地区的名字、副标题、关键词、推广文案全部在限额内，流水线脚本能跑通，图片不入库的约定也遵守了。真正的问题有四类：
1. **故事分裂**：只有简中（zh-Hans）在文本、截图、头图、首屏四处讲"发到微信的卡片"；其余 11 个地区、Mac 的全部 12 个地区、TestFlight 的测试说明、审核备注，讲的都还是"所有链接集中一处"。图标换了以后，这些地方和图标不是一套。
2. **GitHub Pages 多发了东西**：`docs/_config.yml` 只排除了 `app-store.md`，于是 `mac-app-store.html`（带 App Store Connect 的版本 ID、构建 ID）和 `search-followups.html` 现在是公开页面；`positioning-review.md` 合进 main 后也会公开。站点根路径是 404，而 `marketing_url` 又是空的。
3. **隐私政策落后于代码**：政策没提 iCloud 同步，也没提视觉搜索首次使用时会从 GitHub Releases 下载模型、并在 github.com 不通时走两个第三方镜像（ghfast.top、mirror.ghproxy.com）。
4. **文档过时**：`app-store.md` 里"图标保持现状"、"除简中外都讲所有链接"、Beta 描述等多处已与现实不符。

## 1. 清单

| 东西 | 位置 | 谁推送 | 入库 |
|---|---|---|---|
| 名字、副标题、推广文案、关键词、描述、更新说明、三个 URL | `ios/fastlane/metadata/<locale>/` × 12 | `Tools/release.sh metadata --apply`（asc migrate import） | 是 |
| 版权、分类、审核备注 | `ios/fastlane/metadata/{copyright,primary_category,secondary_category}.txt`、`review_information/notes.txt` | 同上（版权单独 `asc versions update`） | 是 |
| iOS 截图（iphone、iphone63、ipad、duo） | `ios/fastlane/screenshots/<locale>/` | 同上 | 否，`.gitignore` |
| 原始截屏 | `ios/fastlane/raw/` | `Tools/store-shots/capture.zsh` 生成 | 否 |
| 产品页头图 | `ios/fastlane/headers/header-<locale>.png` | 没有脚本推送，手动传 Asset Library | 否 |
| 截图文案和布局 | `Tools/store-shots/copy.js`、`frame.html`、`header.html`、`export.js` | 本地渲染 | 是 |
| Mac 描述、关键词、审核备注 | `ios/fastlane/mac-metadata/` × 12 | `release.sh metadata --mac`（`Tools/mac-metadata.py`） | 是 |
| Mac 截图 | `ios/fastlane/mac-screenshots/` | `mac-capture.zsh` + `mac-export.js` | 否 |
| 隐私政策、支持页 | `docs/privacy-policy.md`、`docs/support.md` | GitHub Pages（main 的 `docs/`） | 是 |
| README 图标 | `docs/images/icon-{default,dark}.png` | 无 | 是 |
| App 内：首屏空状态、分享引导、卡片底部署名 | `Shared/Localizable.xcstrings`、`Shared/EmptyState.swift`、`CardComponents.swift` | 随 build | 是 |
| Android 文案 | `android/app/src/main/res/values{,-zh-rCN}/strings.xml` | 随 build；没有 Play 商店文案 | 是 |

## 2. App Store Connect 文本（12 个地区）

**限额**：全部合规。名字最长 29（es-ES/es-MX），副标题 de-DE 刚好 30，关键词 es-ES 99、en-US 94、zh-Hans 50、zh-Hant 43；描述 1.1k 到 2.1k，远低于 4000。`release.sh` 推送前还会跑 `asc migrate validate`。

**故事分布**：

| | 名字和副标题 | 推广文案 | 关键词 | 描述首段 |
|---|---|---|---|---|
| zh-Hans | 链接转图片卡片 | 微信痛点 | 链接转图片、长图、朋友圈、群聊 | 收藏在前（见定位复盘 §4） |
| en-US | All Your Links | 收藏 | bookmark、read later、reading list | 收藏 |
| zh-Hant | 連結收藏夾 | 收藏 | 稍後閱讀、書籤 | 收藏 |
| 其余 9 个 | "所有链接"的直译 | 收藏 | 书签、稍后读、收藏夹 | 收藏 |

建议分两档：
- **A 档 en-US、zh-Hans、zh-Hant**：按定位复盘的文案改，这是已经立的任务卡。
- **B 档 ja、ko、vi、ru、ar-SA、fr-FR、de-DE、es-ES、es-MX**：这些市场的主力聊天工具（LINE、KakaoTalk、Zalo、WhatsApp、Telegram）本来就有链接预览，"微信没预览"这个痛点不存在。有两种选法：要么改成不依赖微信的通用版本，"把链接变成带二维码的图片卡片，发到任何地方"，卡片在前、收藏在后，至少和图标、头图是一套；要么干脆砍掉这 9 个地区，减少维护面。不建议维持现状，因为现状和新图标说的是两件事。

**更新说明（release_notes）**：en-US 是 "A clearer welcome screen, and small fixes."，zh-Hant 是"新增繁體中文 App Store 介紹與螢幕截圖"。后者描述的是商店素材而不是 App 本身，用户看不到意义。1.0.2 的更新说明应写新图标和新首屏，12 个地区统一。

**审核备注（review_information/notes.txt）**：第一句 "Attention is a library for links" 要改成卡片故事；测试步骤里加一步"分享为图片后，把图片发到任意聊天 App 看效果"（不需要微信）。另外要补一句：视觉搜索第一次使用会下载一个约几十 MB 的模型文件，审核员看到下载进度不要当成异常。

**分类**：主类 Utilities、副类 Productivity。新定位下仍然合适，不用动；Photo & Video 和 Social Networking 都不如 Utilities 准确。

**三个 URL**：支持页和隐私页 12 个地区一致，都返回 200。`marketing_url` 12 个地区全空，而站点根路径 `https://yjmeqt.github.io/Attention/` 是 404。建议加一个 `docs/index.md` 做一屏落地页（中英双语，一句话痛点、一张卡片图、App Store 徽章），然后把 `marketing_url` 填上。这个 URL 也会出现在产品页上。

**版权**："2026 Yi Jiang"，没问题。

## 3. 截图与头图流水线

脚本本身是健全的：`capture.zsh` 用专用的 `Attention-Shots-*` 模拟器、按地区切系统语言、固定状态栏、每个场景重装 App；`export.js` 用 Chrome 渲染，iphone63 由 iphone 缩放得到，es-MX 复制 es-ES；`release.sh` 按前缀分四组上传。以下是配置层面的问题：

- **场景序列**：除 zh-Hans 外 11 个地区都是 feed → share → private → search → detail，第一张是满屏收藏网格，第三张是 Face ID。改法见定位复盘 §5，这里只补一点：`capture.zsh` 第 132 行附近的 compare 卡片裁切只对 `zh-Hans` 的 iphone 做，其他地区要用 compare 场景的话，这个条件要一起放开。
- **分享菜单里的图标**：share 场景截的是 Safari 的真实分享菜单，里面有 App 图标。图标换了，所有地区、所有设备的 share 场景都要重截，不只是 en-US。
- **头图构图**：`header.html` 里 `lang` 只在 `zh-Hans` 时取 `zh`，所以 zh-Hant 现在拿到的是英文的"四张散卡"构图，不是"光秃链接 → 卡片"。统一成后者后这个分支可以删掉。头图不入库，本地 `fastlane/headers` 里 11 个地区都已生成（含 zh-Hant），缺 es-MX，但 es-MX 可以直接复用 es-ES 的文件。
- **内容合规**：非中文地区只用 Apple 和 Wikipedia 页面、zh-Hans 用 3Blue1Brown，这套约定继续有效。如果 en-US 改用 compare 场景，气泡里的链接文字可以是 Wikipedia 的，痛点是"任何链接"。
- **上传范围**：`release.sh` 的 `SCREENSHOT_SETS` 含 ipad 和 duo，但本地只有 iphone 和 iphone63 的成品，ipad、duo 要重新跑 `capture.zsh` 才有。`app-store.md` 记录 8 日已给 1.0.2 草稿传了 zh-Hant 的 25 张，这批是旧文案，改完后要用 `ONLY="zh-Hant"` 覆盖。

## 4. GitHub Pages

`docs/_config.yml` 的 exclude 只有 `app-store.md` 和 `superpowers`。实测：

| 页面 | 状态 |
|---|---|
| `/Attention/` | 404（没有 index） |
| `/Attention/support.html`、`/Attention/privacy-policy.html` | 200，应该公开 |
| `/Attention/mac-app-store.html` | 200，内部文档，含版本 ID、构建 ID、验证记录 |
| `/Attention/search-followups.html` | 200，内部文档 |
| `/Attention/positioning-review.html` | 404，仅因为还没合进 main |

这次改动已把 `mac-app-store.md`、`search-followups.md`、`positioning-review.md` 和本文加进 exclude。更稳的做法是把内部文档挪到 `docs/internal/` 并排除整个目录，或者挪出 `docs/`，这样以后新建文档不用记得加排除。

## 5. 隐私政策与代码的差距

政策（生效日 2026-10-26）列出的第三方：YouTube oEmbed、FxTwitter、Bilibili API、Google favicon。代码里实际还会联系：

- **iCloud 同步**：README 和 Mac 审核备注都说收藏库通过用户自己的 iCloud 私有数据库在 iPhone、iPad、Mac 之间同步。政策的 "On-device storage" 一节只说"保存在你的设备上"，一字未提 iCloud。虽然私有数据库不经过开发者，App Privacy 仍可答 "Data Not Collected"，但政策必须写明。
- **模型下载**（`Shared/Search/ClipModel.swift`）：视觉搜索首次使用时从 `github.com/yjmeqt/Attention/releases` 下载 MobileCLIP 模型，失败时依次走 `ghfast.top` 和 `mirror.ghproxy.com`。这两个镜像是第三方服务，大陆用户几乎一定会走到，它们能看到设备 IP。政策要加一条。
- **Apple Intelligence**：Ask 用的 FoundationModels 在设备上运行，可以顺手写一句，免得用户以为问答上了云。
- **小红书图片代理**（`Unfurler.swift`）：只是把页面自己给的图片 URL 解包后直接取原图，属于"访问链接对应的网站"，不需要单独列。

改完后更新生效日期，三种语言同步。

## 6. `docs/app-store.md` 过时的地方

- "Design decisions → App icon: keep the current one"：已换。
- "Listing copy" 一节描述的分布（除简中外都讲所有链接）、"1.0 shipped as Save & Share Links everywhere"：第一句在改完 A 档后要重写。
- "Before the first submission" 里 "[x] Redo the store text for the library positioning"：这一项的方向已反转。
- TestFlight 的 Beta App Description（英文那段是收藏故事）和 What to Test：按新定位重写英文段，中文段已对。
- "Screenshots" 一节的两套序列说明：改完后同步。
- 这个文件被 `_config.yml` 排除了，不会公开，可以放心写内部细节。

## 7. Mac

- `mac-metadata/` 12 个地区的描述全部以"把想留下的链接收进同一个收藏库"开头，菜单栏做卡片在第二段；关键词是 bookmarks、read later、organizer。建议倒过来：菜单栏一键把剪贴板链接变卡片、⌃⌥⌘A 直接粘进微信，这是 Mac 版最贴场景、也最独特的能力。
- `mac-export.js` 的三张截图标题是"想留下的链接，都在这里 / 收藏过的链接，轻松找到 / 把链接，变成图片卡片"，卡片在第三张；建议卡片放第一张。
- 名字和副标题是 iOS 和 Mac 共享的 App 信息，iOS 一改，Mac 商店页自动变成"链接转图片卡片"，而 Mac 描述还在讲收藏库，两者会对不上。所以 Mac 文本至少要和 A 档一起改。
- Mac 1.0.1 在审，这些改动留给下一个 Mac 版本；`mac-metadata.py` 只改描述、关键词、审核备注，不碰共享字段，是对的。

## 8. Android

- 还没有 Play 商店文案，仓库里也没有 `android/fastlane` 之类的目录。`strings.xml` 的英文和简中已经是微信故事（"Links WeChat can preview"），和 iOS 的 zh-Hans 一致，比 iOS 的英文还超前。
- 建 Play 文案时直接复用 iOS 的 zh-Hans 和改好的 en-US；Play 对第三方品牌名的限制比 App Store 松，但标题里同样别放 WeChat。
- 图标已同步（adaptive + monochrome），`ic_launcher_background` 是米白。

## 9. App 内自带的宣传面

- 首屏空状态：en 是 "All your links in one place / Save links from YouTube, X and any other site. No feed, no algorithm, no tracking."，zh-Hant 是同一套的翻译；zh-Hans 已是"让微信也能预览的链接"。改 en 和 zh-Hant 两组字符串，第三步点名"在微信里发送图片，再粘贴链接"。
- 分享引导演示 youtube.com 的分享菜单，和定位一致。
- 卡片底部 "Made with Attention / 由 Attention 生成"：纯文字模板（TextCardView）的底部已经带 App Store 二维码，设置里有开关，默认开；链接卡片模板（TileTemplate）的底部二维码指向原链接，署名只有文字。链接卡片是主打场景，被转发得最多，可以考虑把 `Brand.appStoreURL` 以文字形式（apps.apple.com 短链）加进署名行，不另加二维码，避免和原链接的二维码混淆。
- Debug 包叫 "Attention Dev"，截图流水线用 `APP_DISPLAY_NAME=Attention` 覆盖，分享菜单里显示正确，这个约定不要丢。

## 建议的顺序

1. **合并 PR #50 前**：`_config.yml` 排除内部文档（本次已做）。
2. **1.0.2 提交前，不需要新 build**：隐私政策补 iCloud、模型下载镜像、Apple Intelligence，更新生效日期；审核备注改首句、加模型下载说明；12 个地区的更新说明统一写新图标和首屏；`marketing_url` 配一个 `docs/index.md`。
3. **A 档文本和截图**：en-US、zh-Hant 的 name、subtitle、promo、keywords、description，`copy.js` 换 compare 序列，`header.html` 统一构图，全部地区重截 share 场景；用 `ONLY` 覆盖 8 日传上去的 zh-Hant。这是已立的任务卡。
4. **Mac 文本**：和 A 档一起改，随下一个 Mac 版本推送。
5. **B 档 9 个地区**：先定留还是砍；留就改通用卡片版本。
6. **`app-store.md` 刷新**：以上做完后对照改。
7. **Android Play 文案**：等 Android 到可上架时，从 zh-Hans 和 en-US 复用。

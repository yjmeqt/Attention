# 分享列表：设计

把选中的条目（或一个标签下的条目）分享成一个网页：`https://<域名>/l/<id>`。分享出去的是链接，链接的预览图是这个列表的双列流截图。想发图片时，把链接分享给 Attention，用它现有的流程生成卡片。

## 已定的决定

| 问题 | 决定 |
|---|---|
| 存在哪里 | Cloudflare Worker + R2。这是 Attention 第一次有后端 |
| 更新方式 | 一次性快照，不能修改。想改就重新分享，得到一个新链接 |
| 分享哪些条目 | 链接和纯文本条目。图片条目跳过，私密条目（`isPrivate`）和已归档条目一律不上传 |
| 有效期 | 永久有效，用户可以在 app 里撤回 |

还没定：域名（官网也要用同一个）。

## 上传什么

快照是一个 JSON 文件，加上若干张缩略图：

```json
{
  "v": 1,
  "title": "周末要看的",
  "createdAt": "2026-11-14T08:00:00Z",
  "lang": "zh-Hans",
  "items": [
    { "kind": "link", "url": "https://youtu.be/abc", "title": "…", "site": "YouTube",
      "author": "…", "thumb": "0.jpg", "aspect": 1.78 },
    { "kind": "text", "text": "…" }
  ]
}
```

- 链接用 app 已经清理过的版本（去掉 `utm_*`，`youtu.be/ID` 这类），和复制到剪贴板的那个一致。
- 只有前 20 条带缩略图。缩略图在设备上压成 JPEG，最长边 480 px，单张不超过 60 KB。有用户自选图（`customData`）就用它，没有就用封面（`coverData`）；两者都没有就不传，网页显示站点名。站点图标不上传。
- 不上传：OCR 文本、视觉标签、关键词、作者头像、标签名以外的其他标签、`createdAt` 以外的时间。

### 链接预览图（`preview` part，可选）

分享出去的是列表的链接，这张图就是链接的封面：在 iMessage、Telegram、X 等会显示链接预览的地方，对方看到的就是它。把链接分享给 Attention，Attention 会用它做链接卡片的封面，所以想发图片（比如在微信里）时，走 Attention 现有的"链接 → 卡片"流程即可，不再单独做一张带二维码的分享卡。它由 app 在设备上渲染，和上传一起发出，服务端存为 `lists/<id>/og.jpg`，网页的 `og:image:width/height` 按这张图的实际尺寸写。没有这张图的列表，网页会退回到通用模板 `web/public/img/og-list-<lang>.png`。

- **尺寸**：1080 × 1080（1:1），JPEG。正方形是因为 Attention 的卡片和很多聊天 App 会把封面裁成方形。服务端只接受 600–1200 px 宽的正方形 JPEG（允许 1 px 误差），超过 150 KB 一律拒绝（`invalid_preview`）。
- **压缩**：不超过 140 KB。1080 px 先用 0.7 的画质，逐步降到 0.5；再不行就缩到 900 px、720 px。
- **版式**：和 feed、网页一样的双列流。
  - 只有前 8 条排成的双列流，没有标题、图标和条数：别的 App 展开链接时会显示 `og:title` 和网站图标，图里不再重复。
  - 用和 feed 同一个卡片组件（`FeedTileFace`）和同样的颜色：深色模式（黑底）；有图的条目下面是从图片底边取色的色带，没图的用深色模式的系统次级背景色。每条放到较短的一列。
  - 放不下的部分在底部被裁掉，并渐隐到黑底。底边因此是纯色：Attention 会用图片底边的颜色给卡片的文字区上色，纯色才能得到干净的文字区。
  - 上传时每张缩略图附带同样算法取出的色带颜色（`tint`，`#rrggbb`），网页用它给图片下的色带上色，和 App 一致。网页的配色也用 iOS 系统色。
- 卡片上的文字跟随设备语言，和上传的 `lang` 一致。
- 渲染方式和现有的卡片一样：360 pt 的 SwiftUI 视图加 `ImageRenderer`，按 scale 3 输出（`ios/Shared/Sharing/ListCard.swift`）。
- 上限：100 条，纯文本单条 5,000 字，整个请求 4 MB。超出的部分在 app 的确认页上先告诉用户。
- 顺序和 feed 一致，从新到旧。

## 服务端（`web/`）

用一个 Worker 同时托管官网静态页（Workers Static Assets）和下面的接口，代码放在仓库新建的 `web/` 目录，用 `wrangler` 部署。

| 路由 | 作用 |
|---|---|
| `POST /api/lists` | multipart：`list` 是上面的 JSON，链接条目的 `thumb` 写缩略图所在的 part 名；可选的 `preview` 是链接预览图。返回 201 `{ id, url, deleteToken }` |
| `GET /l/:id/og.jpg` | 列表的链接预览图（有的话） |
| `GET /api/lists/:id` | App 用的完整列表 JSON，缩略图是绝对地址；撤回或移除返回 410，不存在返回 404 |
| `GET /.well-known/apple-app-site-association` | Universal Link 声明，两个域名都有 |
| `DELETE /api/lists/:id` | 带 `Authorization: Bearer <deleteToken>`，删除快照和缩略图 |
| `GET /l/:id` | 服务端渲染的 HTML 页面 |
| `GET /l/:id/:n.jpg` | 从 R2 读缩略图，`Cache-Control: immutable` |

- **ID**：10 位 base62 随机串（约 59 bit），猜不到，也不能枚举。
- **撤回**：没有账号，所以靠一次性的 `deleteToken`（32 字节随机）。服务端只存它的 SHA-256，原值只存在用户的设备上。
- **R2 布局**：`lists/<id>/list.json`（token 哈希放在它的 custom metadata 里）、`lists/<id>/<n>.jpg`；撤回后留下 `revoked/<id>`，用来区分 410 和 404。
- **防滥用和费用上限**：上传接口是匿名的。Workers 用免费套餐，超额只会失败、不会扣钱；会按用量扣钱的只有 R2，而且它没有消费上限，所以 Worker 里有四层保护：
  - 按 IP 限流：每 60 秒 3 次（Workers 的限流绑定只支持 10 秒或 60 秒的窗口）。
  - 全站每日上限：`DAILY_UPLOAD_LIMIT`，默认每个 UTC 日 500 次，由一个 Durable Object 计数，不管对方换多少 IP 都有效。
  - 只有前 20 条带缩略图，单次上传最多写 21 个对象。
  - 总闸：把 `UPLOADS_ENABLED` 改成 `"false"` 再部署，就停掉所有新上传，已分享的列表照常能看。

  - App Attest（`web/src/attest.ts`、`ios/Shared/Sharing/AppAttest.swift`）：App 在安全隔区里生成一个密钥，第一次分享前请 Apple 证明它（`GET /api/attest/challenge` 拿挑战，`POST /api/attest` 交证明）。Worker 按 Apple 的步骤验证证书链（根证书在 `web/src/appAttestRoot.ts`）、nonce、密钥 ID、App ID 和环境，然后把公钥和计数器存进 R2 的 `attest/<key id>`。之后每次上传带一个断言，签的是新挑战加列表 JSON 的哈希，Worker 验证签名并要求计数器递增。服务器不认识这个密钥时返回 `unknown_attest_key`，App 换一个新密钥重试一次。
  - `ATTEST_MODE` 决定没有或验证不过的上传怎么处理：`log` 只记日志，`require` 拒绝上传（现在的设置，真机验证过；模拟器不支持 App Attest，所以没法往线上传），`off` 不检查。测试里用 `log`。
  - 测试用 `node web/scripts/attest-fixture.mjs` 生成的证书链（和 Apple 的结构一样，但用测试根证书签），见 `web/test/attest.test.ts`。
  - Android 以后用 Play Integrity。另外在 Cloudflare 后台打开按用量计费的提醒。
- **撤回后**：`/l/:id` 返回 410，页面提示"分享者已撤回这个列表"。

## 网页 `/l/:id`

- 服务端直接输出 HTML，不依赖前端框架，在微信内置浏览器里首屏要快。
- 页面结构：列表标题、条目数、分享日期；然后是条目列表，链接条目显示缩略图、标题、站点，点击直接打开原链接；纯文本条目显示正文，长文折叠。
- 页面带 Open Graph 和 Twitter 标签（标题、第一张缩略图），所以发到微信以外的地方也有预览。
- 页脚：来自 Attention，App Store 链接；一个"举报"入口。
- 界面文字跟随快照的 `lang`，第一版做简体中文和英文。
- 加 `<meta name="robots" content="noindex">`，不让搜索引擎收录。只有拿到链接的人能看到。

## App

**入口**：主入口是多选：在"更多 › 选择"里选中几条，点底栏的"分享为列表"，标题默认是当前标签名，不在标签里时用日期。也可以按标签分享：侧边栏的标签行有上下文菜单"分享列表…"，打开一个标签后"更多"菜单里也有。

Mac 的库窗口侧边栏同样加一个，可以放在第二步做。

**确认页**（sheet）：顶部是可编辑的列表标题（默认当前标签名，不在标签里时用日期），下面写明条数和跳过的条目（私密、图片、超过 100 条），然后用首页 feed 的卡片（`FeedTile`、`Waterfall`）双列显示要分享的条目，最后一句说明会上传、拿到链接的人都能看、可以在侧边栏"已分享的列表"里撤回。

- 可以修改列表标题，默认用标签名。
- 显示将要分享几条，以及跳过了几条、原因是什么（私密、图片、超出上限）。
- 一句说明："列表会上传到 Attention 的服务器，任何拿到链接的人都能看到，之后可以在设置里撤回。"
- 确认后上传，成功后进入分享步骤。

**分享出去的东西**：上传成功后复制链接，并调起系统分享面板分享链接（`ShareItem`，面板顶部显示列表的预览图）。确认页上同时说明：想发图片，就把链接分享给 Attention，再发它生成的卡片。

**管理已分享的列表**：侧边栏底部的"已分享的列表"（不放在设置里）。列表页单列显示每个列表的分享图（`og.jpg`）、标题、条数和日期，右下角菜单可以分享链接、复制链接、撤回。点进去是详情页，用和收到的人一样的双列流显示整个列表，右上角同样有分享和菜单。

记录放在一个新的 SwiftData 模型里，通过 CloudKit 同步，这样在 Mac 上也能撤回：

```swift
@Model
final class SharedListRecord {
    var listID = ""        // 服务端 ID
    var title = ""
    var itemCount = 0
    var createdAt = Date.now
    var deleteToken = ""   // 只存在用户自己的 iCloud 私有库里
}
```

新模型要在第一个带这个功能的版本发布前，把 CloudKit schema 从 Development 部署到 Production（和 README 里 `LibraryItem` 的步骤一样）。

## Universal Link：在 App 里看完整列表

- **网页只给预览**：`/l/:id` 只显示前 5 条，下面是"在 Attention 中查看"的引导，网页上不提供完整列表（已定）。
- **AASA**：`attentioncard.com` 和 `open.attentioncard.com` 都在 `/.well-known/apple-app-site-association` 提供这个文件，声明 `/l/*` 由 App 打开，`/l/*/*`（缩略图和预览图）除外。appID 是 `M3V5P234X3.com.yjmeqt.attn` 和 `.attn.dev`。
- **为什么要 `open.` 这个域名**：在 Safari 里点同一个域名的链接，iOS 不会转去 App。所以网页上的按钮指向 `https://open.attentioncard.com/l/<id>`：装了 App 就直接打开；没装的话，Worker 把这个地址重定向到 App Store。页面同时带 Smart App Banner（`app-argument` 是列表地址），Safari 顶部的"打开"也能跳进 App。
- **按设备区分**：网页按 User-Agent 区分苹果设备、Android 和其他电脑（iPadOS 的 Safari 会自称 Mac，所以 Mac 也算苹果设备）。
  - 苹果设备：显示"在 Attention 中查看"按钮，提示"会先打开 App Store，装好后回到这里再点一次"（没有脚本，装完不会自动回到列表）。
  - Android：没有按钮，说明 Attention 目前只有 iPhone、iPad 和 Mac 版。
  - 其他电脑：同样的说明，再加一个指向列表页的二维码，用 iPhone 相机扫一扫在手机上打开。
  - `open.attentioncard.com/l/<id>` 也一样：只有苹果设备会被重定向到 App Store，其他设备回到列表页。
- **从哪里能直接进 App**：iPhone 相机扫卡片上的二维码、在 Safari/信息/备忘录里点链接、点网页上的按钮。**微信里不会跳转**（微信拦截 Universal Link），所以在微信内置浏览器里，页面会提示"点右上角 ··· 在浏览器中打开"。
- **App 端**（`ios/Shared/Sharing/`）：
  - App 的 entitlement 声明了 `applinks:` 这两个域名；Debug 版加了 `?mode=developer`，直接从网站取 AASA，不经过 Apple 的 CDN（真机要打开"设置 → 开发者 → Associated Domains Development"）。
  - App 用 `onOpenURL` 接收链接，弹出 `SharedListView`：通过 `GET /api/lists/:id` 读取完整列表，只读显示；点"保存到我的收藏"会把链接和文字存进收藏，用列表标题作为标签，已有的条目只加标签，之后补抓预览。
  - 列表已撤回或被移除时显示 410 对应的提示，不存在时显示 404 对应的提示。
- **Mac 暂不认领这些链接**：Mac App 和 iPhone App 是同一个 bundle ID，如果在 Mac 上也声明 Associated Domains，Mac 浏览器会把链接交给一个还不能显示列表的 App。

## 合规

- **隐私政策**（`docs/privacy-policy.md`）：新增一节，写明只有用户主动分享列表时才会上传，说明上传哪些内容，内容公开给有链接的人，可以随时撤回，撤回后删除。不收集账号和设备标识。
- **App Privacy**：从 "Data Not Collected" 改为声明 User Content（其他用户内容），不关联身份，不用于追踪。
- **审核指南 1.2（用户生成内容）**：网页上有举报入口，开发者能下架内容，用户能撤回自己的分享。审核备注里说明这几点。
- **下架流程**：举报发到 report@attentioncard.com（Cloudflare Email Routing 转发给开发者）。开发者运行 `npm --prefix web run takedown -- <链接或 ID>` 删除，页面返回 410，显示"已根据举报移除"，和分享者自己撤回的提示不同。

## 实施顺序

1. **`web/` 和 Worker**（已完成并部署，见 [`web/README.md`](../web/README.md)）：上传、读取、删除接口，`/l/:id` 页面。
2. **iOS 上传**（已完成）：`SharedListRecord` 模型（`ios/Shared/Library/SharedListRecord.swift`）、快照打包和压缩、上传客户端（`ios/Shared/Sharing/ListUpload.swift`），单元测试在 `ios/Tests/ListUploadTests.swift`，不碰网络。
3. **iOS 界面**（已完成）：侧边栏标签的上下文菜单和标签页“更多”菜单里的“分享列表…”、确认页（`ShareListSheet.swift`）、链接预览图（`ListCard.swift`）、侧边栏的"已分享的列表"和详情页（`SharedListsView.swift`）。发布前要把 CloudKit schema 部署到 Production。
4. **合规**：隐私政策、App Privacy、审核备注（已完成）；App Attest（已完成，`require` 模式，真机验证过）。
5. **Mac 入口**。之后再做 Android。

## 第一版不做

- 修改已分享的列表（已定为不可变快照）。
- 收到的人"导入到自己的 Attention"。以后可以通过 Universal Link 做，但微信会拦截 Universal Link，价值有限。
- 访问统计。

# 定位复盘：从"收藏链接"到"发到微信的链接卡片"

2026 年 11 月 9 日。对照新的核心场景（微信里贴链接没有预览，用图片卡片当链接的替身），逐项检查 1.0.2 草稿里的全部对外素材：名字、副标题、推广文案、关键词、描述、截图、产品页头图、图标、首屏和分享引导，以及 Mac 的上架材料。每项给出现状、问题和建议改法。

## 一句话结论

简中这一套（zh-Hans）已经讲对了故事，但其他所有地区还在讲"所有链接集中一处、没有算法"，图标和头图也看不出"聊天"这个场景。最该改的是 en-US（海外华人大多用英文系统和美区账号）和 zh-Hant，再把图标、头图和搜索故事与新定位对齐。

## 原则

- 微信不能出现在名字、副标题、关键词里（审核指南 2.3.7），截图不能用微信界面。描述和推广文案里可以说"发到微信也有预览"。
- 名字和副标题都进搜索索引，别互相重复用词。
- 简中讲"微信"，英文讲"chat apps"或点名 WeChat（描述里可以），繁中讲"LINE、微信"两边都要照顾：台湾和香港的主力是 LINE 和 WhatsApp，这两个本来就有链接预览，所以繁中的痛点要改说成"发到微信群、发给大陆的朋友"，不要照抄简中。
- 收藏库、标签、私密、搜索保留，但从主卖点降为"顺便"。

## 1. 名字和副标题

| 地区 | 现状 | 问题 | 建议 |
|---|---|---|---|
| en-US | Attention – All Your Links / Every site. No algorithm. | 两句都是收藏类通用话术，看不出场景 | Attention – Link Preview Cards（30 字）/ Send any link as a card with a QR code |
| zh-Hans | Attention – 链接转图片卡片 / 标题、封面、二维码，一眼看懂 | 已对齐 | 保留；副标题可考虑"发到群里，一眼看懂"把聊天场景点出来 |
| zh-Hant | Attention – 連結收藏夾 / 每個網站，沒有演算法 | 完全是收藏故事 | Attention – 連結轉圖片卡片 / 標題、封面、QR Code，一眼看懂 |
| 其他 9 个 | 所有链接的直译 | 对微信故事无感的市场 | 暂不动，降低优先级 |

## 2. 推广文案（170 字，可随时改）

- en-US 现在是 "Links from every app and site, in one place…"。建议改成痛点开头："Paste a YouTube or X link in WeChat and all your friend sees is a URL. Attention turns it into an image card: title, cover, QR code. One tap from the share sheet."
- zh-Hans 已经是痛点开头，保留。
- zh-Hant 照 en-US 的结构重写，场景写成"傳到微信群、傳給大陸的朋友"。

## 3. 关键词（100 字）

- en-US 现在全是 bookmark、read later、reading list、organizer，是红海词，而且和新定位无关。建议换成：link to image, link card, QR code, share link, preview, poster, chat, wechat 不能用，youtube 不能用。可用：`link card,link to image,qr code,share link,link preview,poster,thumbnail,chat,share sheet,save link`。
- zh-Hans 已经是"链接转图片,长图,转发,朋友圈,群聊,二维码…"，方向对。"书签,稍后读"可以删掉给其他词腾位置，补"卡片""分享图""链接卡片"。
- zh-Hant 是"稍後閱讀,書籤,閱讀清單…"，整组换成简中的繁体版。

## 4. 描述（4000 字）

- en-US 第一段是 "keeps all your links from every app and site in one place"。建议第一段改成痛点加解法，把现有 SHARE WITH CONTEXT 那一段提到最前面并扩写（为什么会这样：聊天 App 对粘贴的链接不生成预览；卡片上有什么；分享图片时链接已复制）。其余段落顺序改为：CARDS FOR CHAT → SAVE FROM THE SHARE SHEET → KEEP WHAT YOU SHARED（收藏库、标签、私密）→ FIND IT AGAIN（搜索）→ SCAN → ON YOUR DEVICE。
- zh-Hans 第一句"帮你留住值得收藏的链接和图片，也让分享链接更体面"仍然是收藏在前。建议第一句直接写"把链接发到微信，也能有标题、封面和预览"，后面段落顺序已经对了。
- zh-Hant 整体按 zh-Hans 的新顺序重写，不是直译"演算法"那套。

## 5. 截图（每地区 5 张，前三张决定转化）

现状：zh-Hans 是 compare → detail → share → template → search，故事完整。en-US 和 zh-Hant 是 feed → share → private → search → detail，第一张是满屏 Apple 和 Wikipedia 的收藏网格，第三张讲 Face ID。

建议 en-US 和 zh-Hant 改用 zh-Hans 的场景序列，并把文案改成：

| 序 | 场景 | en-US 标题 / 副题 |
|---|---|---|
| 1 | compare | Don't send a bare URL! / In WeChat a YouTube or X link is just text. Send a card instead |
| 2 | detail | Title, cover, QR code! / Friends scan it to open the original |
| 3 | share | Tap Share. Done! / From YouTube, X, Safari or any app |
| 4 | template | Card, text or QR! / The right template is picked for you |
| 5 | search | Everything you sent, kept! / Search, or filter by site |

注意点：

- compare 这张的"以前"气泡现在写的是 `https://youtu.be/…` 加"好友：这是什么？"，这是全套里最有说服力的一张，建议所有地区第一张都用它。英文版气泡的回话可以是 "friend: what is this?"。
- compare 图里没有任何微信界面，只是一个白色气泡，合规。保持这样。
- en-US 现在示例内容全是 Apple 和 Wikipedia 页面（见 copy.js 注释），为的是规避第三方品牌。改用 zh-Hans 的 3Blue1Brown YouTube 示例是可行的，zh-Hans 已经这么上传过了；如果担心审核，用 Wikipedia 页面做 compare 也成立，因为痛点是"任何链接"。
- iPad 和 Duo 的五张也要同步换场景，不然同一地区内故事不一致。

## 6. 产品页头图（header，3840×1646）

- header.html 取每个地区第一张截图的标题，所以 en-US 现在是 "All your links. One place!" 配四张散开的卡片；zh-Hans 是"别再发一串网址！"配一个光秃秃的链接气泡、一个箭头、一张卡片。
- zh-Hans 版的构图正好就是新定位的视觉：链接 → 卡片。建议 header.html 不再按语言分两套构图，所有地区统一用"链接气泡 → 箭头 → 卡片"这一套，只换文字。
- 缺 zh-Hant 的头图，fastlane/headers 里没有 header-zh-Hant.png。

## 7. 图标

- 现状：米色底，一张斜放的灰绿色卡片，上半是橙红色封面，封面上一个黑色链条，下面两行文字和一个二维码。
- 读出来的信息是"链接 + 卡片 + 二维码"，和产品本体一致，但没有"发出去、聊天"这层含义，和头图、截图的气泡语言也没有呼应。
- 建议最小改动：把链条换成或叠加一个对话气泡（卡片从气泡里冒出来，或卡片右上角一个小气泡尾巴），二维码保留。颜色体系（米色、橙红、黑）和截图背景一致，不用动。Icon Composer 的四层结构（card、hero、details、link）里只需要改 link.svg 这一层，或者加一层 bubble.svg。
- Debug 的 Dev 斜带不受影响。

## 8. 首屏空状态和分享引导

- zh-Hans 首屏已是"让微信也能预览的链接"，三步说明里也写了"在微信里发送图片，再粘贴链接"。对的。
- en-US 首屏是 "All your links in one place / Save links from YouTube, X and any other site. No feed, no algorithm, no tracking."，三步说明第三步是 "Send the image anywhere"。建议标题改成 "Links that preview in any chat"，副题改成 "In WeChat a pasted link is just a URL. Turn it into a card with the title, cover and QR code."，第三步点名 "Send the image in WeChat, then paste the link"。
- zh-Hant 首屏是简中的收藏版翻译，照新的简中改。
- 分享引导（ShareSheetGuide）演示的是 youtube.com 的分享菜单，和新定位一致，不用动。
- 卡片底部的 "Made with Attention / 由 Attention 生成" 是每一张被转发的卡片都带着的自传播入口，建议保留，并考虑把 App Store 链接也编进这行（现在只有文字）。

## 9. 搜索功能的位置

- Shared/Search 里有 CLIP 视觉搜索、Ask 自然语言问答、关键词生成，是一套相当重的能力，但在新定位里它回答的问题是"我上周发给谁的那条链接在哪"。
- 建议对外只说"搜索发过的链接、按网站筛选"，截图第五张留给它，描述里一段带过。Ask、视觉搜索这些不要出现在前三张截图和推广文案里，避免稀释。
- 工程上不需要砍，只是不再作为卖点。

## 10. Mac

- Mac 的 en-US 描述第一句是 "Keep the links you want to return to in one place on your Mac"，第二段才是菜单栏做卡片。建议把顺序倒过来：菜单栏一键把剪贴板里的链接变成卡片图、⌃⌥⌘A 直接粘进微信，这是 Mac 版独有且最贴场景的能力。
- Mac 关键词 en-US 还是 bookmarks、read later，换成和 iOS 一致的卡片词。
- Mac 三张截图（library、search、card inspector）建议把 card inspector 或菜单栏面板放第一张。

## 建议的改动顺序

1. en-US 和 zh-Hant 的 name、subtitle、promotional_text、keywords、description（纯文本，`Tools/release.sh metadata --apply` 即可推送到 1.0.2 草稿）。
2. copy.js 里 en-US、zh-Hant 换成 compare 序列的五句文案，重新跑 capture 和 export，上传截图；补 zh-Hant 头图。
3. header.html 统一成"气泡 → 卡片"构图。
4. EmptyState 的英文和繁中字符串。
5. 图标加气泡元素（需要新一个 build）。
6. Mac 描述和关键词顺序调整。

1 到 4 不需要新 build，可以先推到 1.0.2 草稿。5 需要随下一个 build 一起。

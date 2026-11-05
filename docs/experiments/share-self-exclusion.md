# Attention 自分享排除实验

日期：2026-11-05。分支：`codex/share-self-exclusion`。基于 `23e2574`。

结论：**额外附加一个来源标记会误伤其他分享入口，不适合采用。** 在同一个附件上增加一个遵循标准 URL / PNG 类型、承载真实内容的自定义子类型，可以在本次模拟器测试中隐藏 Attention，同时保留其他已测试入口。后者仍是实验方案，尚未完成微信真机兼容性验证。

## 环境和方法

- 独立 Codex worktree：`/Users/yi.jiang/.codex/worktrees/share-self-exclusion/Attention`。
- iPhone 17 Pro Max 模拟器，iOS 27.0，UDID `EE2AABD9-C22E-4B17-8C39-828BCC7ADB26`。
- 使用 `xc-dev run` 构建、安装；使用 Argent 操作真实系统分享面板和接收应用。
- 调试入口：用 Argent `launch-app` 启动 `com.yjmeqt.attn.dev`，传 `launchArgs: ["-shareProbe", "YES"]`。
- 固定测试 URL：`https://www.apple.com/swift/?attention_share_probe=1`。
- 固定测试图片：程序生成的青色图片，文字为 `ATTENTION SHARE PROBE`，无个人数据。
- `ShareProbe.swift` 的 Baseline 使用现有 `ShareItem`，并保留 `SharePresenter` 当前的系统操作排除列表；正常产品分享代码没有接入实验发送逻辑。
- 截图保存在本地、被 git 忽略的 `build/share-probe/` 下。

## 实际观察

| 方案 / 路径 | Attention 入口 | 其他入口和内容 | 结论 |
| --- | --- | --- | --- |
| Baseline：链接 | 显示 | Reminders、Safari 显示 | 对照组 |
| Baseline：图片 | 显示 | Reminders、Save Image、Add to Shared Album 显示 | 对照组 |
| 把扩展 bundle ID 加入 excludedActivityTypes：链接 | 仍显示 | 与基线相同 | 无法达到目的 |
| 额外加入自定义标记附件：链接 | 隐藏 | Reminders、Safari 和 Open in Safari 消失 | 会误伤其他目标 |
| 额外加入自定义标记附件：图片 | 隐藏 | Reminders、Add to Shared Album 消失；Save Image 仍显示 | 会误伤其他目标 |
| 同一 NSItemProvider 加未知自定义类型：链接 | 隐藏 | Reminders、Safari 和 Open in Safari 消失 | 单纯减少附件数量仍不足以解决 |
| 同一 NSItemProvider 加标准 URL 子类型：链接 | 隐藏 | Reminders、Safari、Open in Safari、Reading List 保留 | 显示层验证通过 |
| 同一 NSItemProvider 加标准 PNG 子类型：图片 | 隐藏 | Reminders、Save Image、Add to Shared Album 保留 | 显示层验证通过 |

基线和最后两项使用同一版有效扩展激活规则；未标记链接仍显示 Attention，排除了“整个扩展激活规则失效”造成的假阳性。

## 实际接收验证

1. **改进方案 → Reminders，链接：成功。** 接收界面显示完整测试 URL；点击 Done 后回调为 `com.apple.reminders.sharingextension`、`completed=true`、`error=none`。
2. **改进方案 → Safari，链接：成功。** 点击 Safari 入口后打开 Apple Swift 页面；该 URL 重定向至 Apple Developer，页面内容正常显示。
3. **改进方案 → Save Image → Photos，图片：成功。** 回调为 `com.apple.UIKit.activity.SaveToCameraRoll`、`completed=true`、`error=none`；随后在 Photos 中找到并打开同一张青色测试图片，文字和画面完整。
4. **Photos → Attention，图片：成功。** Photos 分享面板仍显示 Attention；打开扩展后正确显示图片、OCR 文本和“Saved to Attention”。
5. **Reminders 接收图片：未完成。** 标记方案尝试未进入编辑页；基线对照也无法保存，明确弹出“Upgrade Your Reminders”，要求升级的 Reminders Apple Account。因此不能用本机的 Reminders 证明图片端到端兼容，也不能把它归因于标记。

## 机制和限制

额外标记相当于分享了另一个接收方不认识的附件；即使把未知类型放回同一个 provider，某些激活规则也会检查所有声明的类型。因此两种简单标记方式都实际减少了其他目标。

改进方案在 App 的 `UTExportedTypeDeclarations` 中声明：

- `com.yjmeqt.attn.shared-url` 遵循 `public.url`，数据是实际 URL 的 UTF-8 内容。
- `com.yjmeqt.attn.shared-image` 遵循 `public.png`，数据是实际 PNG 内容。

原 provider 的标准 URL / UIImage 表示仍保留；额外表示有真实有效内容。Attention 自己的激活谓词按自定义标识符排除，其余扩展可按标准类型匹配。

**这份分支是实验记录，不能直接当生产改动合并：**

- 微信、QQ 等第三方 App 未测试；当前没有连接可用的实体 iPhone。必须真机验证目标是否出现以及接收的链接、图片是否正常。
- 顶部 Siri 的 Save / Share 推荐项未验证；这里验证的是 App 入口行。
- 仅验证 iOS 27.0 模拟器，未覆盖最低支持的 iOS 26、iPad 或从 Attention 扩展内部再次分享。
- 实验激活谓词简化了原来的数量限制；正式实现须保留原有支持类型和数量语义。
- Provider 方案尚未接回现有标题、图标、缩略图元数据，实验面板头部为空；正式实现须保留这些定制。
- 没有宣称所有其他 App 都兼容。第三方扩展若仅按精确类型字符串而非类型继承匹配，仍可能有差异。

## 本地截图

- [原链接分享面板](../../build/share-probe/baselineLink.png)
- [额外标记导致其他入口消失](../../build/share-probe/extraLink.png)
- [原图片分享面板](../../build/share-probe/baselineImage.png)
- [额外图片标记造成的影响](../../build/share-probe/extraImage.png)
- [标准 URL 子类型：保留其他入口](../../build/share-probe/typedLink.png)
- [标准 PNG 子类型：保留其他入口](../../build/share-probe/typedImage.png)
- [Reminders 收到完整链接](../../build/share-probe/remindersLink.png)
- [Reminders 成功回调](../../build/share-probe/remindersCompleted.png)
- [Safari 打开目标页面](../../build/share-probe/safariReceived.png)
- [保存图片成功回调](../../build/share-probe/photoCompleted.png)
- [Photos 中的实际图片](../../build/share-probe/photoReceived.png)
- [Photos 仍可分享给 Attention](../../build/share-probe/inboundAvailable.png)
- [Attention 收到图片](../../build/share-probe/inboundReceived.png)
- [Reminders 图片测试的账号限制](../../build/share-probe/remindersImageBlocked.png)

验证：原版和最终实验版 `xc-dev run` 均构建成功；以上为实际运行的模拟器 UI 观察及完成回调，未运行单元测试套件。实验未推送或合入 main。

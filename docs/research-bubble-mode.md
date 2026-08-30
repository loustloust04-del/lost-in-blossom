# Research · 气泡模式作为独立模式（粟粟线全盘）

2026-08-30 兔兔提的问题：粟粟气泡模式下思考链全没了，是不是为了模仿聊天软件刻意去掉的？
兔兔的方向：**气泡模式单独作为一个模式存在，专门模拟对话。**
本文先盘家底、答那个问题、列待拍决策。不动手。

---

## 一、结论先说：思考链不是刻意去掉的，是半成品

证据在她的仓库（`/root/projects/SusuPalace`）：

1. 她 06-11 专门做了一整条「思考链回传」线（research → plan → review 三份文档齐全）：
   CC 的 Stop hook 把 thinking `POST /thinking` 回 hub → 广播给 app → 落进 `MessageNode.ccThinking` 字段，
   并配了显示开关 `ccShowThinking`（默认开，「关=不渲染，数据照落库」）。
   **一个想刻意隐藏思考链的人不会去修一条回传管线。**
2. `ChatBubbleStyle.swift:588` 有 `ThinkingBubble`，非复杂消息分支里正常挂出（`:358`）。
3. 复杂消息分支 `:314` 那句 `isComplex ? (nil, [])` 把思考链一起抹了，
   她自己的注释写着「思考链气泡留第 3 步」——**是没做完，不是设计**。
4. 她的 `isComplex` 判定：segments 里除 `.text / .image / .audioRef` 之外任何段都算复杂。
   CC 回话几乎都带 toolUse 段 → 全是复杂 → `ccThinking` 全程看不到。她主用 API 流式，
   thinking 在 segments 里由 `MessageSegmentsView` 渲染，所以她自己没痛感；兔兔主用 CC，痛感最强。

**我们这边**：思考链走 `[thinking]` 内嵌（pendingThinking consume-once），不走 `ccThinking` 字段。
第三刀 `acac10b5` 已把灰泡挂上，两条来源（内嵌 / segments .thinking）都接了。

---

## 二、她的气泡模式现在有多大（06-03 → 08-29）

`ChatBubbleStyle.swift` 603 行 + 独立文件 `BubbleContextMenuBridge` / `BubbleMenuOverlayView` /
`BubblePopTunerView` / `AvatarCropSheet`，`chatBubbleMode` 分流散在 4 个文件 15 处。

| 层 | 内容 | 我们 |
|---|---|---|
| 外壳 | 尾巴形状、只末块带尾巴、圆角滑条 | ✅ 已搬 |
| 拆块 | 空行拆、代码块整块 | ✅ 已搬 |
| 思考链 | 灰泡 + ThinkingDisclosure（展开/弹 sheet 统一） | ✅ 第三刀（我们自己的写法） |
| 语音 | audioRef 渲染成独立语音气泡（一条一泡） | ❌ 我们语音条在气泡外侧胶囊 |
| 动效 | 流式「段落完成即弹泡」spring + dots 尾泡；CC 入场 reveal（dots 前奏 → 逐泡放出）；BubblePopTuning 调参探针 | ❌ |
| 交互 | 长按 Telegram 式浮层菜单（UIKit 桥）、划词浮条、引用 reply_to、选择文本页 | ❌ 我们用原路径的长按菜单 |
| Markdown | 「抹平文档感」：标题→加粗、嵌套列表拍平、分隔线删，代码块表格原样 | ❌ 我们直接 `Text()` 裸渲染 |
| 附件 | `BubbleAttachmentStrip` 图片移到气泡外上方 | ❌ |
| 顶栏 | 头像胶囊、隐藏 PinBar、隐藏分支地图按钮 | ❌（兔兔不要头像） |
| 视觉 | 默认主题 AI 气泡 alpha 0、列表顶余量分模式 150/50、usage footer | 部分 |

她的方向修正（575e14cf）值得记：**气泡模式不吐字，改「段落完成即弹泡」；丝滑吐字只归文章模式。**
这正是「气泡模式 = 模拟对话」的核心手感：聊天软件里对方不是逐字打给你看的，是一条条发过来的。

---

## 三、「独立模式」意味着什么（待兔兔拍板）

现在我们的气泡模式是 `CardFlowView` 里一个 `if chatBubbleMode` 分流，只换正文渲染，
其它（流式、长按菜单、附件、语音条、Markdown）全借文章模式的。要成为独立模式，得决定：

- **D1 流式怎么显示**：a) 照粟粟「段落完成即弹泡」+ dots 尾泡（最像聊天）；b) 流式期间回落文章模式吐字（现状）；c) 只 dots，整条到齐再一次弹出
- **D2 Markdown**：a) 抹平文档感（粟粟做法）；b) 完整 Markdown 渲染；c) 裸文本（现状，`#`/`**` 会原样露出）
- **D3 思考链**：灰泡默认显示 / 默认收起 / 跟随「思考链预览」设置（现状：跟随，hidden 时不出）
- **D4 语音条**：进气泡（一条一泡）还是留外侧胶囊
- **D5 长按菜单**：借文章模式的 / 搬她的 Telegram 浮层（UIKit 桥 + 双影修 + 尾巴白卡，成本高）
- **D6 附件/图片**：气泡外上方条 还是 现状

## 四、建议的切法（每刀能单独装包）

1. **D2 抹平文档感**（`7a6d2423`，纯文本变换函数，低成本高感知——现在裸 `#` 露出最出戏）
2. **D1a 段落完成即弹泡**（`35322cfb` + `575e14cf`，中等：要在流式分支里接已完成段落 + dots 尾泡；她删了 MarkdownUI 流式分支才收敛，我们要看清楚再动）
3. D4 语音气泡（`bb8fd45b`，小）
4. D6 附件条（小）
5. D5 长按菜单（大，先不碰）

**不搬**：头像、usage footer、召回卡、划词收词、弹泡调参探针。

---

## 五、2026-08-30 实机打脸 + 她代码里的线索清单

兔兔装 448 截图对比：我们的气泡模式看起来**和文章模式一模一样**。真凶：`BubbleModeRow` 被套在
`BubbleView` 那层文章模式大卡片**里面**，小泡与大卡同色（`userBubble`/`assistantBubble`）→ 小泡隐形。
唯一露馅的是思考链灰泡（它是 `textMuted.opacity(0.18)`，颜色不同才看得见）。

她那边的结构（`CardFlowView.swift:2669` `innerBody`）：**顶层 `if chatBubbleMode { BubbleModeRow } else { articleModeBody }`**，
气泡模式根本不进大卡。我们的修法：大卡在气泡模式下去内距去底色，contextMenu/overlay/分支指示器/sheet 原位保留。

### 她气泡模式的完整线索（按 commit，供逐条对照）

| 线索 | commit | 我们 |
|---|---|---|
| 顶层 if 分流，不进文章卡 | 46f5c03e 之前 / `innerBody` | ✅ 本次修 |
| 固定内距 18/15，行距 1.45 段距 1.65，圆角滑条 `bubbleModeCornerRadius` | `BubbleModeRow.fixedPadding*` | ✅ 对齐 |
| 泡下面不放操作按钮，走长按菜单 | — | ✅ 本次隐藏 |
| header（名字+时间）贴消息侧，字号 caption2 | `BubbleModeRow.header` | ✅ 已是 |
| usage footer（↑↓token · 命中% · $）在 AI 泡下 | `usageFooter` + `showMessageUsage` | ❌ 我们 usage 走 Token 统计页，不搬 |
| 顶栏中央头像胶囊（封面图→emoji→占位圈三级 fallback） | 1ad133cc | ❌ 待拍（兔兔说不要头像，但胶囊是顶栏不是气泡旁） |
| 气泡模式隐藏 PinBar + 分支地图按钮 | 73dc61c2 / ContentView:847,872 | ❌ 小 |
| 列表视觉顶余量 150（文章 50） | da5df806 | ❌ 小 |
| 默认主题 AI 气泡 alpha 0（透明融背景） | bd272ae3 | ❌ 主题层，看兔兔要不要 |
| 图片条与气泡间距 6px、气泡自适应宽度不撑满 | 0a1cb6a5 | ✅ 自适应已是；间距可调 |
| 流式段落弹泡 + dots 尾泡 | 35322cfb | ✅ 已搬 |
| CC 入场 reveal（dots 前奏→逐泡按字数节奏放出） | dafad12a `entranceDelay` | ❌ 下一刀候选（CC 回复整条到达，没有这个就是「啪」一下全出） |
| 发消息弹泡 popPending + BubblePopTuning 调参 | b5ec8117 等 | ❌ 后 |
| Telegram 式长按浮层 | contextmenu 系列 | ❌ D5 不碰 |

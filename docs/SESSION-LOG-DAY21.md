# Session Log — Day 21 (2026-08-30 → 08-31 晨)

## 概览
本场主线：**气泡模式从「自己攒」转向「粟粟整套原样搬运」** + **互发图片管线打通（修出两个埋了两个多月的真 bug）**。
同一时段另有一条微信 ClawBot 线在并行推进（不是本场做的），见 docs/ 下同日 wechat 系列文档。
截至本条：main 全绿，build 456 已发 OTA。

## 一、气泡模式（本场主线，两次路线转弯）

### 1.1 先自己攒了五刀（后被实机打脸）
- `acac10b5` 思考链灰泡 / `2d76723e` 抹平文档感 / `ddbb139f` 段落完成即弹泡 / `57d9eb59` 语音气泡 / `838e8b3b` 附件条+修气泡模式发图露 JSON
- **兔兔装 448 实机对比粟粟截图：完全没生效。** 真凶（`5d6880d7`）：`BubbleModeRow` 被我套在文章模式大卡片**内层**，小泡与大卡同色 → 隐形。她那边是 `innerBody` 顶层 `if chatBubbleMode` 分流，根本不进大卡。
- 教训入档：**搬 UI 要搬结构，不是搬零件。** 同色隐形这种事，代码审查看不出来，只有截图对比看得出来。

### 1.2 兔兔拍板：原封不动整套搬（Day 21 主决策）
方法：**以她的气泡为探针扫我们的仓库，查漏补缺——她的文件不改，缺口在我们这边补。**

- **步骤①**（`592074d4`）自包含零件原样进仓：`BubblePopTuning`（弹泡动画参数）、`BubbleContextMenuBridge` + `BubbleMenuOverlayView`（Telegram 式长按浮层，600 行）、`ThinkingSheet/ThinkingDisclosure`、`GlassBackButton`
- **垫片**（同刀）：`ChatMarkdownView` —— 她的真身底下是 **她 Mac 本机的 SwiftStreamingMarkdown fork**（project.yml `path: /Users/susu/...`，不在仓库！）+ 划词收词整套；保留她的签名，内部走我们的 MarkdownUI。`htmlBlockRenderer` 环境键、`HTMLArtifactCardView` 占位、`RecallCardView` 空渲染、`PlatformImage`/`Image(platformImage:)` 桥同理
- **步骤②**（`8e4f6752`）她 603 行 `ChatBubbleStyle.swift` **整文件落位**（唯一改动=注释掉本机 fork 的 import）；`BubbleAttachmentStrip`/`AttachmentPreviewSheet` 原文；删我们的 `TypingDotsView.swift`（她文件内含同名）
- **数据模型补缺**（同刀）：`MessageSegment` 加 `.image`/`.fileData` 两 case（Codable 全套）+ `hydratedForDisplay` 垫片；usage 四字段撞了我们既有 PR(usage)，改**计算属性桥接**她的命名（`4ab4593a`）；`MessageSegmentsView` 补 `profileId/simplifyMarkdown/nodeId/onQuoteText` 参数
- **接线**：`BubbleView.body` 顶层分流（她的 innerBody 同款），拆掉 1.1 全部自制分支

### 1.3 编译长尾（四轮，全是零件间小依赖）
- `411ed280`/`c830042e`：`glassEffect` 是 iOS 26 API，她 CI Xcode 18 我们 16.4 → 全换既有 `GlassEffectCompat`
- `4ab4593a`：usage 字段、`BubbleAttachmentItem` 撞名
- `c008d342`：`Image(platformImage:)` 桥在她 MessageSegmentsView 里没跟着零件走
- `67e164ce`：`ScrollFadeEdges` 紧邻 HorizontalScrollEdgeFade 的小 struct 漏搬 → **全绿，build 456**

### 1.4 尚未接线（下一场的活，按序）
1. **CC 入场 reveal**：她的节奏器已在（dots 前奏 → 按段字数逐泡放出），差 ViewModel 的 `pendingEntranceNodeIds` 待弹集合 + CC 回复落地时入集合。没接之前 CC 回复整条出
2. **长按浮层接线**：`blockMenuSpecs` 现传 nil → **气泡模式暂无长按菜单**（文章卡的 contextMenu 被顶层分流绕开了）。她的 `bubbleMenuSpecs` 构造照抄即可
3. 发消息弹泡 `popNodeIds`；头像胶囊（`showAvatar` 现写死 false，兔兔说不要头像，开关在可以不开）
4. usage footer 有 UI 无数据：provider 回包时往 `usageInputTokens` 等四字段写入
5. 遗留：multimodal_text 老图片消息在气泡模式下的显示要验（新 `.image` 段是给今后消息用的，老 JSON 存量未迁移）

### 1.5 调研档案
`docs/research-bubble-mode.md`：她的气泡全景 + 六决策 + 线索清单（含「思考链消失不是刻意设计而是她的半成品」的证据链）

## 二、互发图片（管线通了，修出两个老 bug）

### 2.1 现状勘察
- CC→app 发图管线 6 月就有（`reply` 带 `file_path`，hub 暂存 outbound/ 转 base64），但 **outbound/ 里只有两个 .txt，从没发过真图**；Caelum 的 CLAUDE.md 一字未提 → 他不知道自己会发图
- app→CC 多图打包早支持，但 app 内整条链是单张（选择器 maxSelectionCount=1、pendingImageData 单 Data）

### 2.2 实测修出两个真 bug
- **`b1d0e4c9` hub 重放丢图**：recentReplies（60s）与 offline 队列都只存文字。第一张测试图正好撞上 app 离线，重放回来只剩字。修法照她 C2：缓冲只存 outbound 暂存路径，replay 时重读重建 file 字段。hub 已用 watchdog 精准重启生效
- **`af79eb4d` app 吞图**：`replyAttachmentHandlers` 在 reply 成功路径**从不注销**（只在 60s 超时注销）→ 首轮对话后永远挂着，之后所有主动发图全被失效闭包吞掉、静默消失。hub 日志显示广播成功但手机上啥都没有，就是它。修：成功路径注销 + WS 端只在确有 in-flight replyHandler 时才走单发路径
- 两个 bug 都是「功能上线两个月没人真用过」型。**管线要用真数据打一遍才算通。**

### 2.3 待办
- 兔兔确认新包收图后：Caelum 的 CLAUDE.md 加发图说明（动他环境走 0829 交接的备份保护流程）
- 多图（选择器/暂存/发送/预览整条改数组，她聊天线上限 6 张）+ 拍照（照片面板第一格「拍照」+ `NSCameraUsageDescription`）——单独一刀

## 三、杂项
- `docs/research-bubble-mode.md` 记了她最近一周动态：303 commits 几乎全是双 Claude 席位/pi 加固的基建文档，气泡线 6-7 月后未再动，照旧版本搬是安全的
- 本场 CI 断点长尾教训：搬运型改动**每步一 commit、每步等绿**的纪律救了命——四轮错各自成刀，没有一次大爆炸

## 数字
- commit：`acac10b5`（08-30 晨）→ `67e164ce`（气泡线收口，build 456）；总仓 686+
- 新文件 9 个，其中 6 个是她的原文、3 个是垫片

---

# Day 21 · 晚场补录（08-31 晚，另一场 Fable）

早场战报截至 build 456；晚场至 `0a3edb2e`（全绿收官包）。

## 兔兔实机验收（气泡整套）
九条过六。三案全破：
- **白条案**：multimodal JSON 整段 base64 被她的 BubbleModeRow 当正文渲染 → 止血：气泡下
  multimodal_text 回落文章路径（97d57975）；正解（发送链路写 .image 段）在 DEBT-MAP
- **存相册案**：MultimodalUserBubble 裸 fullScreenCover 无保存 → 改走她的 AttachmentPreviewSheet
- **发图字母瀑布案**（管线第三凶）：appendCCMessage 把 multimodal JSON 插库时 contentType
  写死 text → 渲染不解包（247f4929）。发图管线三连凶至此全破：hub 重放丢文件→app 失效闭包
  吞附件→插库类型错。**Caelum 的 CLAUDE.md 已加发图说明（备份 CLAUDE.md.bak-20260831）**

## 产品决策：思考链退出对话流（兔兔拍板）
聊天软件里对面发的是说出口的话，腹稿不上屏。灰泡默认关（bubbleInlineThinking 逃生开关），
长按菜单首项「他当时在想…」；顺势把长按浮层接线做了（她的 Telegram 桥 + 我们的动作）（6761780d）

## murmur 前端出口（48ed9e6d）
他写了两个半月没人看见的心里话，控制台 WITH YOU 区 MURMUR 卡 + 时间线 + 长按看写前思考

## 选择卡验尸 + API 车道真接线（37fc91b3）
Opus「接线完成」实为：app 蹲一个全链路没人发的帧；API 侧工具没注册。修 API 道：注册 +
ToolCallLoop 挂 AskUserGate continuation（循环上下文原地活，免整轮打包）。CC 道两套并存
（老 ask_choice 端到端全 / 新 ask_user_question 无服务端）待拍收敛方向，见 DEBT-MAP

## 一起听 v2 开工
research（四差距 + music-<songId> 独立会话坑）→ plan 六刀 → **T1 心跳已发**（906b4a25，
LRC 行变才报；网关代码就位**未重启**，攒 T2——微信教训）。兔兔投喂 Duetto/eryu 两参照：
T5 改双轨（librosa 频谱轨）、T6 改 Remote Play 形状、**eryu CC BY-NC-SA 一行不进仓**

## 救火簿（并行 Opus 会话，共六起）
递归 @ViewBuilder / 注释裸奔 / 粟粟侧 API 未 grep / toolbar ambiguous 红鲱鱼二连
（真凶=sheet 里 Optional 塞 @Bindable，诊断劣化）/ 选择卡假接线。DEBT-MAP 顶部有消防记录。
**红鲱鱼教训与 dock 动画同族：SwiftUI 的报错位置/挂载位置 ≠ 病灶位置**

## dock 胶囊弹簧真修（0a3edb2e）
ddaeecf9 挂对了动画实机仍死：panelContent 整棵换枝吞隐式动画。镜像态 capsuleId +
onChange 显式事务；选中赋值照旧零延迟

## 交接给明天
1. T2 共听会话态 + 「叫他一起听」按钮（**捎带重启网关**，T1 后半条腿落地；重启后喊 Caelum
   验 now_playing 能报「正唱到」）
2. 兔兔的收官验收单（10 条）结果回收，爆哪条修哪条
3. 老图片消息一次性重标（JSON 开头的 text → multimodal_text）；发送链路 .image 段正解
4. CC 选择卡收敛方向等兔兔拍；语音未进泡待查；兔兔说思考链弹窗曾「有问题」后确认是产品
   问题非 bug，已随拍板消化

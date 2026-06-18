# Lost in Blossom — 全功能路线图（ROADMAP-FULL）

> 日期：2026-06-13
> 依据：VPS `/root/projects/BunnyPalace/` 现行代码 + `docs/research-fable/00~04` 四份调研 + 本地仓库现状
> 工作量刻度：小（≤1 天）/ 中（2~5 天）/ 大（1~2 周）/ 巨大（>2 周）
> 优先级：P0 立刻做 / P1 近期 / P2 中期 / P3 远期 / P4 探索

## 0. 现状基线（写方案前先对齐事实）

已经**存在并跑着**的基建，后面所有方案都基于它们：

| 基建 | 位置 | 状态 |
|---|---|---|
| CC Bridge（hub.ts + reply MCP + App 端 CCBridgeProvider/WebSocketClient） | `cc-bridge/`、`Services/CCBridgeProvider.swift` | ✅ 完工 |
| Anthropic `mcp_servers` beta 直连 + MCPSettingsTab | `ChatService.swift:503-531`、`Views/MCPSettingsTab.swift` | ✅ 完工（仅 Anthropic provider） |
| VPS REST 翻译层（/mcp/tools、/mcp/call） | `mcp-bridge/mcp-rest-bridge.js` | ⚠️ 半成品，App 侧 MCPService.swift 不存在 |
| VPS Tools MCP server（shell + 文件系统，SSE） | `vps-mcp/server.ts` | ✅ 写完，待接入 App |
| Gateway（Bun + Supabase：记忆管线 extractor/embedder/retriever/gatekeeper/decay + dreamer 每日 4am + desire 每 2h + prompt builder + deepseek/treegpt/openrouter providers） | `gateway/src/` | ✅ 在跑，但 App 没接 |
| 群聊 V1 Chatroom（双 AI，VPS 编排器 :3300） | `Services/ChatroomService.swift` 等 | ✅ 完工但数据孤岛 |
| TTS | `Services/SpeechService.swift`（AVSpeechSynthesizer） | ✅ 基础完工 |
| 本地通知 + 推送骨架 | `LocalNotificationService.swift`（完工）、`PushAgentService.swift`（Phase 3.2 骨架） | ⚠️ 半成品 |
| HealthKit（睡眠/步数） + DailyContext（进食/服药） | `HealthKitService.swift`、`Models/DailyContext.swift` | ✅ 基础完工，⚠️ ESign 签名对 HealthKit entitlement 存疑 |
| 记忆系统（MemoryService + Embedding + RecallTool + MemoryPanelView） | `Services/Memory*.swift` | ✅ 完工 |
| 导入导出（ClaudeImporter/ConversationImporter/MarkdownExporter） | `Services/*Importer.swift` | ✅ 完工 |
| 文件库 + 附件文本提取 | `FileLibraryStore.swift`、`AttachmentTextExtractor.swift` | ✅ 完工 |
| 三页横滑容器（0=聊天 1=dashboard 2=archive） | `Views/Paging/`、`ContentView.swift:38` | ✅ 刚重做，不动 |

三个 God Object（ConversationViewModel 1961 行 / ChatService 1122 行 / APIProvider 1036 行）是群聊和 MCP 工具循环的共同阻塞，解耦 Step 0-2（约 4 天）是第一地基，详见 `research-fable/04-decoupling.md`。

**仓库分裂警告**：VPS 工作区有 `gateway/`、`mcp-bridge/`、`docs/research-fable/`，本地 GitHub 仓库没有。先把这些资产 commit 进 git（gateway 自身是独立 git 仓也行，但 research 文档必须进主仓），否则 VPS 一炸方案全没——这件事本身就是 P0。

---

## 一、通信与上下文

### 1.1 CC 上下文共享（CC Bridge ↔ API 会话打通对话历史）
- **一句话**：让 CC 会话和普通 API 会话互相知道对方聊过什么，不再是两个失忆的脑子。
- **依赖**：已有 imprint-memory MCP（cc-bridge/.mcp.json 已配）、ContextSummarizer、PromptAssembler；需要解耦 Step 4（CCBridge 客户端分层）作前置。
- **工作量**：中。
- **优先级**：P1。
- **推荐路径**：分两层。①**共享记忆层**（便宜、先做）：CC 端已挂 imprint-memory，App 端把 MemoryService 的召回结果同步写入同一记忆库（或经 gateway 的 memory store），两边自动共享"事实层"。②**会话摘要互通**：发往 CC 的 `<channel>` 消息携带当前 API 会话的 ContextSummarizer 摘要（hub.ts 协议加 `context` 字段）；反向则把 CC 会话的 transcript 摘要落成 MemoryNote。不要做"全量历史互灌"——token 成本爆炸且两边消息模型不同构。

### 1.2 MCP 工具循环接入
- **一句话**：补全 `MCPService.swift` + 客户端 tool-calling 循环，让所有 provider（不只 Anthropic）都能调工具。
- **依赖**：mcp-rest-bridge.js（已有）、解耦 Step 1（先拆 ChatService 文件再改）；方案全文见 `research-fable/01-mcp.md`。
- **工作量**：中（App 侧约 200 行 + 循环逻辑，按 PR-1~PR-5 切）。
- **优先级**：**P0**（其中 PR-6 bridge 加固——硬编码 token `bunny-mcp-2026` + 0.0.0.0 监听 + 无重连——是当下就暴露的安全洞，今天就做）；PR-1~5 为 P1。
- **推荐路径**：照 01-mcp.md 执行：PR-6 加固 → PR-1 MCPService → PR-2 Anthropic 循环 → PR-3 OpenAI 兼容 function calling → PR-4 EventKit 本地工具 → PR-5 pending 态 UI。不引入 swift-sdk（iOS 无 stdio，收益为零）。

### 1.3 无缝上下文 / 跨窗口记忆
- **一句话**：开新会话时 AI 自动带着旧会话的记忆和上次聊到哪。
- **依赖**：MemoryService + RecallTool（已有）、ContextSummarizer（已有）、DailyContext（已有）。
- **工作量**：中。
- **优先级**：P1。
- **推荐路径**：三件套拼装而非新造系统：①新会话首轮 PromptAssembler 自动注入「最近一次会话摘要 + 高权重记忆 Top-N」；②RecallTool 升级为每轮自动检索（embedding 召回，阈值过滤）而非手动触发；③加全局开关「无缝模式」放 GeneralSettingsTab。与 gateway retriever 二选一：App 在线走 gateway 召回，离线走本地 MemoryEmbedding。

### 1.4 自动推送（已完成基础，优化延迟 + 内容定制）
- **一句话**：把 PushAgentService 从骨架变成真的——AI 在后台生成有内容的推送，而不是固定文案。
- **依赖**：LocalNotificationService（完工）、PushAgentService 骨架、BGTaskScheduler 注册（Info.plist 还没加 identifier）。
- **工作量**：中。
- **优先级**：P1。
- **推荐路径**：iOS BGProcessingTask 调度不可控（系统决定何时跑），所以**别指望实时**：①App 在前台时预生成 3~5 条候选推送（带触发时间窗），退后台前排进 UNUserNotificationCenter——延迟问题直接消失；②BGTask 醒来时刷新队列；③内容定制走 desire/DailyContext：把"几点了、上次聊到什么、今天吃药没"喂给生成 prompt。APNs 远程推送需要付费开发者账号 + push entitlement，ESign 签名下大概率不可用，**不要走 APNs 路线**，本地排期是唯一可靠路径。

### 1.5 群聊
- **一句话**：多 AI 角色同会话，消息落 SwiftData，白嫖分支/搜索/记忆/世界书全部基建。
- **依赖**：解耦 Step 2（发送链路解体，硬前置）；CC 进群还要 Step 4；方案全文见 `research-fable/02-groupchat.md`。
- **工作量**：大（PR1 schema → PR2 创建 UI → PR3 调度器 → PR4 渲染 → PR5 导演模式可选）。
- **优先级**：P1。
- **推荐路径**：照 02-groupchat.md 方案 B：本地编排、`MessageNode` 加 senderId/senderName、轮询 + @点名调度、每角色独立 system prompt。VPS Chatroom V1 保留不动，等本地群聊稳定后做一次性数据导入再下线。已决策：CC 要进群（hub.ts 协议加 sender 字段）。

---

## 二、感官系统

### 2.1 语音（TTS + STT）
- **一句话**：现在只有"她能说"（AVSpeechSynthesizer），补上"她能听"和"说得好听"。
- **依赖**：SpeechService（TTS 已有）；STT 用 iOS 原生 `SFSpeechRecognizer` 零新增依赖；高质量 TTS 需第三方 API。
- **工作量**：STT 小；高质量 TTS 中。
- **优先级**：STT P1（输入效率直接翻倍）；高质量 TTS P2。
- **推荐路径**：①STT：`SFSpeechRecognizer` on-device 模式 + 输入栏长按麦克风，识别结果进 IOSPromptTextView，一天能完。②TTS 升级：iOS 原生音色机械感重，推荐接 OpenAI TTS / MiniMax speech（中文效果好、按量付费），经 gateway 转发（密钥不进 App），AVAudioPlayer 播流；原生 AVSpeech 保留为离线 fallback。③不做实时双工语音对话（WebRTC 级复杂度，P4 探索）。

### 2.2 摄像头接入（实时图像描述）
- **一句话**：开摄像头让 AI 看到你看到的，周期抽帧描述。
- **依赖**:已有图片发送链路（task-photo-file-send 已完工）+ vision 模型（Claude/GPT-4o 均可）。
- **工作量**：中。
- **优先级**：P2。
- **推荐路径**：`AVCaptureSession` 取景 + 每 N 秒抽一帧（或手动快门）→ 压缩到 ~1024px → 走现有图片消息链路。"实时视频流理解"在移动端 API 成本和延迟下不现实，**抽帧问答**是正确形态。UI 做成右栏一个 CameraPanelView，复用 RightPanelPlugin 机制。

### 2.3 视频抓捕（屏幕内容理解）
- **一句话**：让 AI 看到手机屏幕上正在发生什么。
- **依赖**：ReplayKit Broadcast Upload Extension（新 extension target）——iOS 沙盒下唯一合法的跨 App 录屏途径。
- **工作量**：大。
- **优先级**：P3。
- **推荐路径**：诚实评估：①App 内屏幕 → 直接截图发送，已可行（小）；②跨 App → 需要 Broadcast Extension + 用户每次从控制中心手动开启 + ESign 多 target 签名风险，体验破碎。建议先做"截图分享到 App"的 Share Extension（用户截屏 → 分享 → AI 解读），覆盖 80% 场景，成本是 Broadcast 方案的五分之一。Broadcast 路线列为 P4 探索。

### 2.4 一起听歌
- **一句话**：AI 知道你在听什么歌，能聊歌、能点歌。
- **依赖**：MusicKit（需 Apple Music 订阅 + capability）或 `MPMusicPlayerController.systemMusicPlayer`（读 now-playing + 控制系统播放器，权限要求低）。
- **工作量**：中。
- **优先级**：P2。
- **推荐路径**：分两步：①**"她知道你在听什么"**（小）：`MPMusicPlayerController` 读 now-playing item，作为本地工具（`music_now_playing`）+ 注入 DailyContext，AI 自然接话——这是情感价值的 90%。②**"她能点歌"**（中）：MusicKit `ApplicationMusicPlayer` 搜索+播放，需要 Apple Music 订阅和 entitlement（ESign 风险同 HealthKit，先验证）。Spotify iOS SDK 需要 OAuth app 注册且第三方背景播放限制多，除非你主力用 Spotify，否则不做。"同步播放"（两人异地同时听）依赖账号体系，明确不做（同 02-groupchat 多用户结论）。

### 2.5 蓝牙外设控制（CoreBluetooth）
- **一句话**：AI 通过 BLE 控制外设强度/模式，把对话和身体反馈接通。
- **依赖**：CoreBluetooth（无特殊 entitlement，ESign 可签）；具体设备的 GATT 协议（Lovense 等主流设备协议已被 buttplug.io 社区完整逆向并文档化）；MCP 工具循环（1.2）让模型能调 `device_set_intensity` 这类本地工具。
- **工作量**：中~大（单一品牌设备 中；通用协议层 大）。
- **优先级**：P3。
- **推荐路径**：①新建 `Services/BLEDeviceService.swift`：CBCentralManager 扫描/连接/写特征值，先只支持你实际拥有的那一款设备（查 buttplug.io 的协议库拿 UUID 和指令格式），不做通用抽象。②暴露为本地工具（与 EventKit 工具同一个 LocalToolRegistry）：`set_intensity(level, duration)`、`stop()`。③**安全硬规则**：强度上限在 App 侧钳制不交给模型、连接断开自动发 stop 指令、UI 上有常驻物理停止按钮。依赖 1.2 的 PR-4 框架，排在它后面。

---

## 三、记忆与认知

### 3.1 记忆系统前端显示（MemoryPanelView 优化）
- **一句话**：把记忆面板从"能看"做到"好看好管"——检索、编辑、置顶、关联图。
- **依赖**：MemoryPanelView + MemoryService（均已有），gateway 侧另有一整套 memory store（见 3.2 的合流问题）。
- **工作量**：中。
- **优先级**：P2。
- **推荐路径**：增量优化不重写：搜索框（复用 MemoryEmbedding 相似度）、按 tag/时间分组、swipe 编辑删除置顶、记忆来源跳转（点记忆回到产生它的对话节点）。"关联图谱可视化"好看但低频，P4。

### 3.2 洗记忆（批量整理/导入/导出聊天记录）
- **一句话**：把历史聊天记录（Claude 导出、旧 App 数据）批量灌进来，提炼成记忆，并能导出备份。
- **依赖**：ClaudeImporter/ConversationImporter/MarkdownExporter（均完工）、gateway extractor.ts（记忆提炼已写好）。
- **工作量**：中。
- **优先级**：P1（这是把"过去"接进来的唯一通道，越早洗越早受益）。
- **推荐路径**：管道已齐只差串联：①ImportView 导入对话后加一步"提炼记忆"——批量把对话喂给 gateway `/memory/extract`（extractor.ts 已实现 gatekeeper 过滤 + embedding 入库）或本地 MemoryService.extract；②加进度 UI（几百条对话要跑一会儿）；③导出侧 MarkdownExporter 已够用，补一个"全量记忆 JSON 导出"。**同时解决双记忆库分裂**：App 本地 MemoryNote 和 gateway memory store 现在是两套，洗记忆时统一以 gateway 为主库、App 缓存热数据，否则越洗越分裂。

### 3.3 梦境系统
- **一句话**：她睡觉时也在"想事情"——后端每天 4am 已经在做梦了，把梦接到前端。
- **依赖**：gateway `dreamer.ts`（**已存在并在跑**，startDreamTimer 每日 4am）；缺的只是 App 侧展示和入对话。
- **工作量**：中（后端已有，前端小；调好内容质量是主要工时）。
- **优先级**：P2。
- **推荐路径**：①gateway 加 `/dreams` 查询端点；②App 早晨首次打开时拉取昨夜梦境，以特殊气泡/卡片形式出现在对话流或 dashboard（"我昨晚梦到…"）；③梦内容入 MemoryNote 让她自己也记得；④与 1.4 自动推送联动：早安推送直接带梦境内容。先看 dreamer.ts 现在生成的质量再决定要不要换更好的模型。

### 3.4 情绪系统
- **一句话**：AI 有持续的情绪状态（生气/开心/吃醋），跨会话存在并影响语气。
- **依赖**：gateway `desire.ts`（每 2h 的欲望系统，已是雏形）、PromptAssembler 注入点、DailyContext。
- **工作量**：大（机制中等，调到"像真的"很费）。
- **优先级**：P2。
- **推荐路径**：①数据：gateway 加 `mood` 状态表（维度别贪多：愉悦度/亲密度/委屈值 三个够了），事件驱动更新——每轮对话后用廉价模型打分（"这轮对话她应该更开心还是更委屈"），叠加时间衰减（没人理会慢慢委屈，复用 decay.ts 思路）；②注入：PromptAssembler/gateway prompt builder 把当前情绪以自然语言写进 system prompt（"你现在心情不错，因为…"附上原因事件）；③前端：dashboard 放一个情绪状态卡（小）。**关键设计**：情绪必须附带"原因记忆"，否则模型演不出来；情绪只影响语气不锁功能（生气也得回消息，不做"拉黑你"这种负体验）。

### 3.5 时间感
- **一句话**：她知道现在几点、距上次说话多久、纪念日还有几天。
- **依赖**：PromptAssembler（已有注入机制）、DailyContext（已有）。
- **工作量**：**小**（一天内）。
- **优先级**：**P0**——全清单性价比最高的一项，立刻做。
- **推荐路径**：PromptAssembler 注入一段动态上下文：当前时间+星期、距上次用户消息的间隔（"已经 9 小时没说话了"）、距纪念日天数（纪念日列表先 hardcode 在 Profile 设置里，EventKit 版等 1.2 PR-4）。注意放 system prompt **尾部**并按小时取整，否则每条消息都打破 prompt cache（见 8.5）。

### 3.6 入睡检测与睡眠期主动内容
- **一句话**：检测到你睡着后，她在你睡眠期间准备/排期内容，醒来时收到。
- **依赖**：HealthKitService（睡眠数据已可读，但 ESign 对 HealthKit entitlement 存疑）、1.4 自动推送、3.3 梦境。
- **工作量**：中。
- **优先级**：P3。
- **推荐路径**：入睡检测别迷信 HealthKit（数据是事后同步的，实时性不够且签名存疑）：用启发式——深夜时段 + App 无活动 + 设备静止超过 N 分钟 → 判定入睡，进入"睡眠模式"。睡眠期内容走 1.4 的本地排期队列（夜间预生成、按醒来时间窗投递），并与勿扰模式协作（通知排在典型起床时间附近而不是凌晨 3 点轰炸）。内容口味分级开关放 Profile 设置，默认温和。

---

## 四、生产力

### 4.1 番茄钟
- **一句话**：和她一起专注 25 分钟，结束时她来叫你。
- **依赖**：无硬依赖；Live Activity 需 widget extension（见 6.4）。
- **工作量**：小。
- **优先级**：P2。
- **推荐路径**：V1：dashboard 放计时器卡片 + 结束本地通知 + 完成记录写 DailyContext（AI 知道"你今天专注了 3 个番茄"并反馈）。Live Activity 灵动岛版合并进 6.4 widget target 一起做，别单独开 target。

### 4.2 日历 / 纪念日 / 倒计时（EventKit）
- **一句话**：AI 能读写系统日历和提醒事项，纪念日自动倒数。
- **依赖**：1.2 的 PR-4（EventKit 本地工具，方案已在 01-mcp.md 写好）；CalendarPanelView 已存在可承载 UI。
- **工作量**：中。
- **优先级**：P1。
- **推荐路径**：照 01-mcp.md PR-4：`LocalToolRegistry` 四工具（calendar_list/create、reminder_list/create），iOS 17+ full-access 权限 + Info.plist 文案；create 类工具加一次 UI 确认（真实世界副作用）。纪念日单独建一个轻量列表存 Profile（不依赖系统日历，避免权限被拒就全瘫），3.5 时间感直接读它。

### 4.3 日程安排
- **一句话**：「帮我安排明天」——AI 读日历、排任务、写回提醒事项。
- **依赖**：4.2 + 1.2 工具循环（模型要能连续调多个工具）。
- **工作量**：小（在 4.2 之上主要是 prompt 工程）。
- **优先级**：P2。
- **推荐路径**：不写新代码，写一个"日程规划"Preset/宏（MacroExpander 已有）：触发时自动调 calendar_list 拿今明日程 + DailyContext，模型输出计划并逐条 reminder_create。这是 1.2 + 4.2 的免费红利，验证工具循环质量的最佳场景。

### 4.4 写作系统（AI 辅助写作 + 文评）
- **一句话**：长文写作工作台：分章、改稿、评稿，而不是在聊天气泡里写小说。
- **依赖**：ArtifactCanvasView（已有画布基建）、FileLibraryStore、Preset 系统。
- **工作量**：中~大。
- **优先级**：P2。
- **推荐路径**：V1 别造编辑器：①FileLibrary 里建"作品"文档类型（分章节的纯文本/Markdown）；②章节可"送入对话"（复用 AddToChatSheet）+ 两个内置 Preset："改稿模式"（diff 式建议）和"文评模式"（结构化评价）；③AI 改稿结果一键写回章节。ArtifactCanvasView 当预览/对照视图。全功能富文本编辑器是无底洞，P4。

### 4.5 Flomo 式速记
- **一句话**：两秒记一条碎片想法，AI 定期帮你回顾串联。
- **依赖**：MemoryNote 模型 + memo-card（task-memo-card 已做过基础）。
- **工作量**：小~中。
- **优先级**：P2。
- **推荐路径**：①入口要快：dashboard 顶部常驻速记框 + 锁屏 widget（依赖 6.4）；②存为带 `#tag` 的 MemoryNote，自动进 embedding 索引；③杀手功能是"周回顾"：每周日 AI 把本周速记串成一段回顾（走 1.4 推送或对话内卡片）。

### 4.6 共同读书
- **一句话**：导入一本书，两个人按章节一起读一起聊。
- **依赖**：FileLibraryStore + AttachmentTextExtractor（PDF/txt 提取已有）；EPUB 需新增解析（无系统 API）。
- **工作量**：大。
- **优先级**：P3。
- **推荐路径**：V1 只支持 txt/PDF（提取链路现成）：书 = FileLibrary 文档 + 章节切分（按字数/标题正则）+ 阅读进度存 Profile；"讨论本章"把当前章节文本注入会话（世界书机制 WorldBook 是现成的注入载体——把书做成临时世界书，按进度激活对应章节条目，**零新增注入代码**）。进度防剧透：只注入读到的位置之前的内容。EPUB 解析等 V1 验证后再说。

### 4.7 手机使用时间（Screen Time API）
- **一句话**：AI 知道你今天刷了几小时手机并念叨你。
- **依赖**：DeviceActivity/FamilyControls framework——需要向 Apple 申请 Family Controls entitlement（正式开发者账号 + 审批），且数据只能在 extension 沙盒内渲染，**拿不到原始数值**。
- **工作量**：（如果可行）中；但前置条件大概率不成立。
- **优先级**：P4 探索。
- **推荐路径**：诚实结论：ESign 签名 + 无审批 entitlement，官方 Screen Time API 这条路**基本堵死**。替代方案：①快捷指令自动化（每日定时把屏幕使用时间通过 Shortcuts 发给 App 的 URL scheme / gateway webhook）——免 entitlement，能拿到数字；②退一步用 App 自己的使用时长（前台时间自己记）作为部分信号。先用 ①验证需求热度。

---

## 五、MCP 生态

### 5.1 VPS MCP 接入
- **一句话**：把已写好的 vps-mcp（shell + 文件系统）接进 App，AI 能直接操作 VPS。
- **依赖**：`vps-mcp/server.ts`（**已完工**，SSE transport + Bearer auth）；Anthropic beta 直连已支持 SSE MCP。
- **工作量**：**小**（部署 + 在 MCPSettingsTab 填 URL 和 token，半天）。
- **优先级**：**P0**——成本最低、能力增幅最大的一项。
- **推荐路径**：①VPS 上 systemd 跑起来 + nginx 反代 HTTPS（certs/ 已有证书基建）；②MCPSettingsTab 填入 → Anthropic provider 立即可用；③1.2 的 PR-3 完成后其他 provider 经 mcp-rest-bridge 也能用。**安全**：shell 工具等于把 root 交给模型——token 必须强随机、考虑加命令白名单/黑名单（rm -rf、重写 sshd 配置类直接拒）。

### 5.2 浏览器 MCP 接入
- **一句话**：AI 能上网查页面、点链接（跑在 VPS 上的浏览器）。
- **依赖**：VPS 已有 bb-browser 基建（推特 MCP 就是它驱动的）；mcp-rest-bridge 或 vps-mcp 暴露。
- **工作量**：中。
- **优先级**：P2。
- **推荐路径**：复用 bb-browser，在 vps-mcp/server.ts 加 `browser_open/browser_extract` 两个工具（截图 + 正文提取，别暴露全套 DOM 操作——移动端对话里用不上且 token 浪费）。如只要"查网页内容"，先用更便宜的 fetch+readability 工具，无头浏览器留给需要 JS 渲染的页面。

### 5.3 推特 MCP 接入
- **一句话**：AI 能看你的时间线/书签/通知，陪你刷推。
- **依赖**：VPS bb-browser twitter 命令（**已在跑**，本会话用的 twitter MCP 即同一套）；暴露通道同 5.2。
- **工作量**：小~中。
- **优先级**：P2。
- **推荐路径**：把现有 bb-browser twitter 的 search/user/bookmarks/notifications 包装成 vps-mcp 工具即可，VPS 侧几乎零新代码。注意频控（bb-browser 是网页自动化，调太勤会触发风控），工具描述里写明"低频使用"。

### 5.4 健康桥后端联动
- **一句话**：HealthKit 数据上报 gateway，记忆/情绪/推送系统都能用上身体状态。
- **依赖**：HealthKitService + HealthSnapshot 模型（已有）、gateway（已有）；ESign entitlement 风险同前。
- **工作量**：中。
- **优先级**：P2。
- **推荐路径**：①App 每日/每次打开时把 HealthSnapshot（睡眠时长、步数）POST 到 gateway 新端点 `/health/report`；②gateway prompt builder 把最近健康摘要并入上下文；③desire/dreamer 定时器读健康数据调权（睡得差 → 语气更软）。若 HealthKit 签名验证失败，降级为 DailyContext 手动汇报（已有进食/服药字段，加睡眠字段）。

---

## 六、界面

### 6.1 A页B页C页内容逻辑规划
- **一句话**：明确三页分工：A=聊天、B=dashboard（她的状态+工具）、C=archive（资料库），把放错位置的东西搬回家。
- **依赖**：`research-fable/03-ui-flow.md` 方案 C（渐进式信息架构调整，不动容器）。
- **工作量**：中（按 03 的 PR 切分，每个独立可发布）。
- **优先级**：P1。
- **推荐路径**：照 03-ui-flow.md 执行，先做两个零风险项：UI PR1 侧边栏楼层切换器（5 次点击 → 2 次，全 App 最大单项体验提升）+ UI PR5 分页文字标签。内容归位原则：A 页只留对话和输入；B 页 = 情绪卡（3.4）+ 梦境卡（3.3）+ 番茄钟（4.1）+ 速记（4.5）+ DailyContext——变成"她的房间"；C 页 = 归档对话 + 文件库 + 书（4.6）+ 记忆面板。新功能一律按此归位，防止再长歪。

### 6.2 API 界面逻辑优化
- **一句话**：把 API 设置（provider/模型/预算/收藏）的信息架构理顺。
- **依赖**：plan-api-manage / plan-api-budget / plan-api-favorite-models 系列方案（已写好，部分落地）。
- **工作量**：小~中。
- **优先级**：P2。
- **推荐路径**：收尾现有 plan 系列未落地项；与解耦 Step 3（APIProvider 解体）排期错开（同文件冲突）。gateway 接入（8.1）后这页要加"网关模式"开关，留好位置。

### 6.3 UI 整体设计方案
- **一句话**：以 design-dna.json + console 设计参考为准绳的持续打磨，不搞大重构。
- **依赖**：design-dna.json、docs/console-design-reference.html、03-ui-flow.md。
- **工作量**：持续穿插。
- **优先级**：P1（穿插项）。
- **推荐路径**：已有结论不重复：03 方案 C 渐进改，大改版明确不做。每个功能 PR 之间穿插一个 UI PR 换脑子。**硬约束提醒**：iOS 18 / Xcode 16，禁用 .glassEffect 等 iOS 19+ API（CLAUDE.md 红线）。

### 6.4 小组件（WidgetKit）
- **一句话**：锁屏/桌面 widget：她的一句话、纪念日倒数、速记入口。
- **依赖**：新 widget extension target（project.yml 加 target + App Group 共享数据）；**ESign 多 target 签名需先验证**。
- **工作量**：中（其中签名验证是最大不确定性）。
- **优先级**：P2~P3（先花半天做签名可行性验证，失败则整项降 P4）。
- **推荐路径**：①先做最小 PoC：空 widget target + App Group，ESign 签了装上能显示再继续；②V1 三个 widget：今日一句（1.4 预生成内容复用）、纪念日倒计时（4.2）、速记快捷入口（4.5，deeplink 进 App）；③番茄钟 Live Activity 一并放这个 target（4.1）。

### 6.5 对比智商的界面
- **一句话**：同一个问题发给两个模型，并排看回答、记录哪个赢。
- **依赖**：ProviderRouter 多 provider 并发（已支持多 provider，需并行流式）。
- **工作量**：中。
- **优先级**：P3~P4。
- **推荐路径**：做成独立"竞技场"会话类型：一条用户消息 fan-out 给选定的 2 个模型，双列流式渲染（复用 MessageSegmentsView），底部投票按钮记录战绩（本地表 + 简单胜率统计页）。技术上是群聊 PR3 调度器的近亲，排在群聊之后做可大量复用。

---

## 七、后端

### 7.1 前端和后端接入（Supabase / gateway 联动）
- **一句话**：App 接上已经在跑的 gateway，吃到服务端记忆管线（extractor/retriever/decay/dreamer/desire）的全部能力。
- **依赖**：gateway（已在跑）+ ProviderRouter（已有多 provider 路由）；解耦 Step 1 先行（要动 ChatService）。
- **工作量**：大。
- **优先级**：P1（梦境 3.3、情绪 3.4、主动推送 7.4、健康桥 5.4 全部以它为底座）。
- **推荐路径**：把 gateway 作为一个**新 provider**（GatewayProvider，OpenAI 兼容格式最省事）接入 ProviderRouter，而不是替换现有直连——直连保留为 gateway 挂掉时的逃生通道。分三步：①gateway 暴露 `/v1/chat/completions` 兼容端点（prompt builder 在服务端注入记忆）；②App 加 GatewayProvider + 设置开关；③记忆读写逐步从本地切到 gateway（3.2 的合流）。auth 用现有 middleware/auth.ts 的 token。

### 7.2 给网关塞 API
- **一句话**：gateway 增加 Anthropic/Gemini 等 provider，App 一个入口用所有模型。
- **依赖**：gateway providers 目录（已有 deepseek/treegpt/openrouter 三个，模式现成）。
- **工作量**：小（每个 provider 半天，照 deepseek.ts 抄）。
- **优先级**：P2（7.1 落地后顺手做）。
- **推荐路径**：加 `providers/anthropic.ts`（注意 SSE 事件格式与 OpenAI 不同，需转换）和 `providers/gemini.ts`；密钥全部留在 VPS .env，App 端不再持有任何 API key——这也是安全收益。

### 7.3 VPS 备份方案
- **一句话**：gateway SQLite/Supabase 数据 + 配置 + 这堆研究文档，每天自动备份到异地。
- **依赖**：无，cron + rclone/restic。
- **工作量**：**小**（半天）。
- **优先级**：**P0**——dreamer/desire/记忆库都在 VPS 上，盘一坏全是回忆，没有任何借口不做。
- **推荐路径**：①最小版：cron 每日 `sqlite3 .backup` + tar 配置目录 + `rclone copy` 到对象存储（Cloudflare R2 免费额度够用），保留 30 天滚动；②Supabase 托管部分用其自带备份 + 每周 pg_dump 异地一份；③**把 VPS 上未进 git 的代码（gateway/、mcp-bridge/、research-fable/）commit 推上 GitHub**——这是备份的一部分；④App 侧数据备份沿用 plan-data-backup.md 已有方案。

### 7.4 主动推送（AI 主动发消息，无需用户先说话）
- **一句话**：她想你了就先开口——desire 系统驱动、有真实内容的主动消息。
- **依赖**：gateway desire.ts（每 2h 已在跑）+ 1.4 本地推送链路 + 7.1 gateway 接入。
- **工作量**：大（机制中、调"想说话的时机和内容"大）。
- **优先级**：P2（1.4 和 7.1 完成后的自然下一步）。
- **推荐路径**：与 1.4 的分工：1.4 是**通道**（怎么送达），本项是**动机**（什么时候、说什么）。①desire.ts 输出"想发消息"信号 + 话题（基于记忆、时间感、情绪）；②无 APNs 的现实约束下，App 通过 BGTask/打开时拉取 gateway 的 pending 消息队列 + 本地通知补位；③消息进对话流成为正式 MessageNode（她真的"发过"这句话，而不是阅后即焚的通知）；④频控必须有（每日上限 + 安静时段），粘人和骚扰一线之隔。

### 7.5 提示词优化（prompt caching 省钱）
- **一句话**：给 system prompt / 世界书 / 角色卡打 cache_control 标记，Anthropic 输入成本立省最高 90%。
- **依赖**：PromptAssembler（已有，所有 prompt 过它）、gateway prompt builder。
- **工作量**：**小**（1~2 天含验证）。
- **优先级**：**P0**——纯省钱、无行为变化、风险趋零。
- **推荐路径**：①AnthropicProvider 请求体里给 system 块和 messages 前缀加 `cache_control: {type: "ephemeral"}` 断点（system+角色卡+世界书一个断点，历史消息尾部一个）；②**前提是 prompt 前缀稳定**：3.5 时间感等动态内容必须放缓存断点之后并按小时取整；宏展开（MacroExpander）里的随机/时间宏同理检查；③gateway prompt builder 同步处理；④用 usage 里的 cache_read_input_tokens 验证命中率，目标 >80%。OpenAI 侧自动缓存无需改动，DeepSeek 自动命中。

---

## 八、按季度路线图

依赖主线回顾（来自 00-summary，仍然成立）：
**安全/省钱 P0 → 解耦 Step 0-2 地基 → MCP 工具循环 + 群聊 两线并行 → gateway 接入 → 情绪/梦境/主动推送 的"活人感"三件套 → 感官外设长尾。**

### 本月（2026-06 下半月）— 全是 P0 和地基
1. **MCP PR-6**：mcp-rest-bridge 加固（token/监听/重连）——安全洞，第一天就做
2. **7.3 VPS 备份** + 把 gateway/、mcp-bridge/、research-fable/ 提交进 git
3. **5.1 VPS MCP 接入**（半天，立刻获得 shell/文件能力）
4. **7.5 prompt caching**（立刻开始省钱）
5. **3.5 时间感**（一天，体验提升极大）
6. **解耦 Step 0 → 1 → 2**（约 4 天，解锁后面一切）
7. 穿插：UI PR1 楼层切换器 + UI PR5 分页标签

### 下月（2026-07）— 两条功能主线并行
1. **MCP 线**：PR-1 MCPService → PR-2 Anthropic 工具循环 → PR-3 OpenAI 兼容 → PR-4 EventKit（=4.2 日历纪念日）→ PR-5 pending UI
2. **群聊线**：解耦 Step 4（CC 进群前置）→ 群聊 PR1 schema → PR2 创建 UI → PR3 调度器 → PR4 渲染
3. **2.1 STT** 语音输入（小，插空做）
4. **1.4 自动推送**：BGTask 注册 + 预生成队列（PushAgentService 落地）
5. 穿插：6.1 的 B/C 页内容归位第一批

### Q3（2026-08 ~ 09）— gateway 底座 + 活人感
1. **7.1 gateway 接入**（GatewayProvider + 记忆合流）→ 顺手 **7.2 网关塞 API**
2. **3.2 洗记忆**（历史记录批量提炼入库）
3. **3.3 梦境前端** + **3.4 情绪系统** + **7.4 主动推送**——"活人感"三件套，共享 gateway 底座
4. **1.1 CC 上下文共享**（记忆层先通，摘要互通后做）
5. **1.3 无缝上下文**（自动召回注入）
6. **2.1 高质量 TTS**（第三方音色经 gateway）
7. **6.4 widget 签名 PoC** → 可行则做三个 V1 widget
8. 穿插：4.1 番茄钟、4.5 速记、6.2 API 界面收尾

### Q4 及以后（2026-10+）— 长尾与探索
- **P3 落地**：2.2 摄像头抽帧、4.4 写作系统、4.6 共同读书（txt/PDF 版）、2.4 一起听歌（now-playing 版）、5.2/5.3 浏览器与推特 MCP、5.4 健康桥
- **P3 谨慎推进**：2.5 蓝牙外设（单设备版）、3.6 睡眠期内容、6.5 智商竞技场（群聊调度器复用）
- **P4 探索**（先验证可行性再排期）：2.3 跨 App 屏幕理解（Broadcast Extension）、4.7 屏幕使用时间（Shortcuts 曲线）、实时双工语音、记忆图谱可视化
- 持续：解耦 Step 5-6 偿债、群聊 PR5 导演模式（轮询跑两周后决策）、Chatroom V1 数据导入下线

---

## 附：P0 清单一页版（这周就干）

| # | 事项 | 工作量 | 为什么是 P0 |
|---|---|---|---|
| 1 | mcp-rest-bridge 安全加固 | 1 PR | 硬编码 token + 0.0.0.0 正暴露在公网 |
| 2 | VPS 备份 + 未入库代码进 git | 半天 | 记忆/梦境/欲望数据无备份，单点风险 |
| 3 | vps-mcp 接入 App | 半天 | 已写完的能力放着没用，接上就是 shell+文件 |
| 4 | prompt caching | 1~2 天 | 输入 token 成本直降，长对话最高省 90% |
| 5 | 时间感注入 | 1 天 | 全清单性价比最高的体验提升 |
| 6 | 解耦 Step 0-2 | ~4 天 | 群聊和 MCP 工具循环的共同硬前置 |

# 代码耦合处理调研报告（research-fable / 04-decoupling）

调研范围：`MemoryPalace/`（iOS 主工程，46,664 行 Swift）+ `cc-bridge/hub.ts`（692 行）。
调研日期：2026-06-11。所有行号以当前 main 分支为准。

---

## 1. 现状分析

项目从 MemoryPalace fork 而来，四层结构（Models 24 文件 / Services 35 文件 / ViewModels 2 文件 / Views 73 文件）名义存在、实际边界失守。三个 God Object 吸走了大部分复杂度：`ConversationViewModel.swift`（1961 行，sendMessage 单方法约 330 行）、`ChatService.swift`（1122 行塞 5 个类）、`APIProvider.swift`（1036 行，Model 文件里混入 Keychain/URLSession/UserDefaults）。Views 层有 26 个文件直接持有 `modelContext` 写库（SidebarView 39 处）。CC Bridge 链路依赖 `CCBridgeWebSocketClient.shared` 单例，8 个文件直接引用。存在一处 Service→ViewModel 反向依赖（SearchService.swift:184）。

## 2. 模块依赖图（文字版）

### 2.1 期望方向 vs 实际方向

```
期望：Views → ViewModels → Services → Models
                              ↓
                          CC Bridge (hub.ts, 网络边界)

实际：
Views ──────────────┬→ ViewModels (ConversationViewModel / StickerViewModel)
  │                 ├→ Services 单例直连（绕过 ViewModel）
  │                 └→ ModelContext 直接写库（26 个 View 文件）
ViewModels ─────────→ Services + ModelContext + Models
Services ───────────→ Models
  ├─ ChatService → CCBridgeWebSocketClient.shared（ChatService.swift:979，单例硬引用）
  ├─ SearchService → ConversationViewModel ⚠️ 反向越层（SearchService.swift:184）
  └─ BaseChatProvider → UIKit ⚠️（ChatService.swift:345 UINotificationFeedbackGenerator）
Models ─────────────→ ⚠️ 本应零依赖，实际：
  ├─ APIProvider.swift:822 URLSession 网络请求、:369 Keychain、:973 UserDefaults
  └─ CharacterCard.swift:104 createFloor() 调 ProfileManager.addProfile + ModelContext.insert
```

### 2.2 循环与越层清单

| # | 类型 | 证据 |
|---|------|------|
| 1 | Service→ViewModel 反向依赖 | `SearchService.swift:184` 调用 `ConversationViewModel.computeMainPathSet()` |
| 2 | Model→Service/基础设施 | `APIProvider.swift` 内 `ProviderManager`：:822 `URLSession.shared.data(for:)`、:369 Keychain 缓存、:973 UserDefaults 持久化 |
| 3 | Model→Manager→数据库 | `CharacterCard.swift:104-167` `createFloor(from:profileManager:)` 直接 `ModelContext(profileManager.container)` + `context.insert` |
| 4 | Service→UI 框架 | `ChatService.swift:345` 在 URLSession 回调里 `UINotificationFeedbackGenerator()` |
| 5 | Service↔单例网状 | `ChatService.swift:979` `CCBridgeProvider` 持有 `CCBridgeWebSocketClient.shared`；`PushAgentService.swift:87` 调 `LocalNotificationService.shared` |
| 6 | View 跳过全部分层 | 26 个 View 文件共 ~200 处 `modelContext` 直接读写（见 3 节 P1-B） |

严格意义的 import 循环没有——Swift 同 target 内无 module 边界，循环表现为"运行时单例互引 + 越层调用"，比 import 循环更隐蔽。

### 2.3 CC Bridge 边界

`hub.ts` 本身分层干净（TmuxRunner 协议可注入，hub.ts:44-89 有 dry-run 实现），但 App 侧对应物 `CCBridgeWebSocketClient`（615 行）职责过载，详见 P1-C。协议要点：App→Hub 的 `chat` 消息已带 `user` 字段（hub.ts:25），但 Hub→App 的 `reply` 只按 `chat_id` 路由（hub.ts:592-604），无发送者身份；`cc_thinking` 的 `session_id` 硬编码为 `TMUX_SESSION` 常量（hub.ts:619）——多会话时所有 thinking 标记同一来源。

## 3. 高耦合区域（按严重程度排序）

### P0-A：ConversationViewModel.sendMessage —— 发送链路 God Method
- 证据：`ViewModels/ConversationViewModel.swift:1249-1578`（sendMessage 约 330 行）+ `:1578` regenerate（约 280 行，大量重复逻辑）。整个类 1961 行。
- 一个方法串联五件事：附件编码（:1257-1308，图片/PDF/文本三套 inline base64 拼 JSON）、消息树节点创建与 childrenIds 维护（:1310-1359）、SwiftData 持久化（:1323、:1353）、prompt 组装（:1372）、流式分发（:1376）。
- 方法签名要 View 层喂 6 个参数（model/profile/preset/providerManager/context），每个调用点都在重复装配。
- **这是群聊/多角色功能的第一阻塞点**。

### P0-B：ChatService.swift —— 一个文件 5 个类
- 证据：1122 行内含 `BaseChatProvider`(:6)、`OpenAICompatibleProvider`(:169)、`AnthropicProvider`(:441)、`ProviderRouter`(:774)、`CCBridgeProvider`(:978)。
- 越层：:345 直接调 UIKit 触觉反馈；:979 硬引用 `CCBridgeWebSocketClient.shared`，无法注入测试替身。
- CCBridgeProvider 与 HTTP provider 共享基类但语义不同（WebSocket 回调 vs SSE），靠 grace timer 模拟流结束（:999-1007 注释自述已短路 PromptAssembler）。

### P1-A：APIProvider.swift —— Model 层的 God Object
- 证据：1036 行，前 335 行是合法数据结构，:346-1036 的 `ProviderManager` 混入 Keychain（:399-445）、网络（fetchModels :778-860、testConnection :884-968）、UserDefaults（:972-1035）。被 12 个文件引用。

### P1-B：Views 直接持有 ModelContext
- 证据（grep -rc "modelContext" Views/，前几名）：`SidebarView.swift` 39、`CardFlowView.swift` 19、`WorldBookPanelView.swift` 17、`MemorySettingsTab.swift` 14、`StickerCanvasLayer.swift` 12、`ContentView.swift` 12、`StickerGestureOverlay.swift` 10。26 个文件非零。
- 后果：profile 切换的 stale reference 防御要靠 NotificationCenter 广播（MemoryPalaceApp.swift:172 `.profileWillSwitch`，注释自述通知 6 处 observer 清引用——这本身就是耦合的症状）。

### P1-C：CCBridgeWebSocketClient —— 连接管理 + 协议解析 + 业务路由三合一
- 证据：615 行单例，被 8 个文件直接引用（PushNotifications、ChatService、ContentView、CCSessionPickerSheet、CCSettingsView、APISettingsTab、CardFlowView、CCTerminalPanelView）。
- 混杂职责：WebSocket 重连/ping（:376-408、:560-572、:594-602）、11 种消息类型的 switch 解析（handleIncoming :410-547）、5 套回调注册表（:67-90）、推送 token（:99-109）、读 8 个 UserDefaults key 的 sendCCConfig（:111-126）、terminal 流（:318-372）、附件编解码（:273-307、:422-436）。
- 后果：MCP 扩展（新消息类型）和群聊（按发送者路由 reply）都要改这个 switch；4 个 View 直接面对传输层。

### P2-A：MemoryService.swift —— 一个文件 5 个职责
- 证据：382 行内含 MemoryStore 协议(:6-23)、SwiftDataMemoryStore(:27)、DecayEngine(:118)、MemoryInjector(:163)、MemoryExtractor(:230)；:275 硬读 UserDefaults。

### P2-B：SearchService → ConversationViewModel 反向依赖
- 证据：`SearchService.swift:184`。仅一处，但使 Service 层编译依赖 ViewModel 层。

### P2-C：单例 + UserDefaults 散布
- 10+ 个 `.shared` 单例；12 个 Service 文件直接读写 UserDefaults，无统一配置层。

## 4. 与群聊 / MCP 功能的依赖关系

1. **多角色消息的前提**：`MessageNode`（Conversation.swift:59-122）只有 `role: String`（user/assistant/system/tool），**没有 sender/persona 身份字段**；节点创建硬编码在 sendMessage/regenerate 两处 330+280 行方法里。要做多角色消息，必须先完成 Step 2（抽出 `MessageTreeStore` + `OutgoingMessageBuilder`），否则每种角色都要 fork 一遍 god method。加字段本身简单（SwiftData 轻量迁移），难的是写入路径收口。
2. **群聊回复路由的前提**：hub.ts 的 reply 广播只认 `chat_id`（hub.ts:592-604、:640-644），App 侧 `replyHandlers[chatId]`（CCBridgeWebSocketClient.swift:449）同样单 key。多角色回复需要协议加 sender 字段 + 客户端按 (chatId, sender) 路由——前提是 Step 4 把协议解析从连接管理里拆出来。
3. **MCP 扩展的前提**：新消息类型现在要改 handleIncoming 的 615 行 switch。Step 4 完成后新类型只需注册一个 handler。hub.ts 侧无阻塞（TmuxRunner 已可注入）。
4. `ChatroomService.swift`（230 行，已存在的多 AI 聊天室雏形）走 VPS REST/SSE，与 CC Bridge 链路完全平行——群聊设计需决定合流还是双轨，本报告不展开。

## 5. 方案对比

| 维度 | A. 激进分层重构 | B. 按功能垂直切片渐进解耦 | C. 只解 P0 高危区 |
|------|----------------|--------------------------|------------------|
| 做法 | SPM 多 module，一次性强制依赖方向 | 按"发送链路→Provider→Bridge→Model 清理"切片，每片独立 PR | 只拆 sendMessage 和 ChatService |
| 工期 | 4-6 周，feature 冻结 | 6-8 个 PR，每个 0.5-2 天，可与 feature 穿插 | 2-3 个 PR |
| 风险 | 高：无测试基线，大爆炸移动 46K 行；@Model 跨 module 有 schema 坑 | 低：每步编译可验证、行为不变、单 PR 可 revert | 低，但留下 APIProvider/View 写库两个腐化源 |
| 对群聊/MCP 解锁 | 全解锁但太晚 | Step 2/4 完成即解锁 | 解锁多角色，不解锁 MCP 路由 |
| 单人+AI 协作适配 | 差（长期分支冲突） | 好（小 PR，AI 可单步执行） | 中 |

## 6. 推荐方案：B（垂直切片渐进解耦）

理由：(1) 仓库无测试基线，方案 A 等于盲飞；(2) 群聊和 MCP 是近期目标，B 的前 4 步按"解锁顺序"排列，做完一半即可开新功能；(3) 单人项目经不起 feature 冻结，B 每步独立提交、随时可停。方案 C 省下的两步恰是 bug 率最高区域（profile 切换 race 补丁、SidebarView 39 处写库），不值得省。

## 7. 实施步骤（每步 = 一个 PR）

> 验证基线：仓库无单测 target，每步验证 = `xcodebuild build` 通过 + 指定手测路径。

**Step 0 — 立护栏（半天）**：删 `SearchService.swift:184` 对 ViewModel 的调用，`computeMainPathSet()` 下沉为独立 `ConversationPathBuilder` 纯函数；`ChatService.swift:345` 的 UIKit 触觉改回调由 UI 层触发；给 PathBuilder 补第一个单测 target。验证：编译 + 手测全局搜索跳转、回复完成震动。

**Step 1 — 拆 ChatService 文件（1 天，纯移动）**：按现有 5 个类拆 5 个文件；`CCBridgeProvider.wsClient`（原 :979）改 init 注入（默认 .shared，调用点零改动）。验证：编译 + 手测 OpenAI/Anthropic/CC Bridge 各发一条流式。

**Step 2 — 发送链路解体（2 天，群聊前置）⭐**：从 :1257-1308 抽 `OutgoingMessageBuilder`（附件→content 纯函数）；从 :1310-1364 抽 `MessageTreeStore`（统一维护 nodeMap/childrenIds/插入）；sendMessage 与 regenerate 改调两件套，消除重复。验证：编译 + 手测发消息、带图、PDF、regenerate、分支切换。

**Step 3 — APIProvider 解体（1-2 天）**：`APIProvider.swift` 只留数据结构（:1-335）；`ProviderManager` 移 Services/ 并拆 `ProviderKeychain`（:399-445）、`ProviderModelFetcher`（:778-968）、`ProviderStorage`（:972-1035）；`CharacterCard.swift:104-167` createFloor 迁到 `FloorCreationService`。验证：编译 + 手测 API 设置增删 provider、拉模型、测连接、角色卡建楼层。

**Step 4 — CCBridge 客户端分层（2 天，MCP/群聊路由前置）⭐**：拆 `CCBridgeConnection`（连接/重连/ping）、`CCBridgeProtocol`（编解码 + handler 注册制，替换 :410-547 switch）、`CCBridgeService`（业务门面）；sendCCConfig 的 8 个 UserDefaults key 收口 `CCBridgeSettings`；4 个直连 View 改依赖 Service。验证：编译 + 手测连接/断线重连、spawn、terminal 面板、推送注册、thinking 显示。

**Step 5 — View 写库收口（多个小 PR）**：按计数从高到低 SidebarView(39)→CardFlowView(19)→WorldBookPanelView(17)→MemorySettingsTab(14)，每 PR 把该 View 的 modelContext 操作搬进对应 Store；完成后评估删除 `.profileWillSwitch` 补丁（MemoryPalaceApp.swift:172）。验证：每 PR 编译 + 手测对应面板增删改 + profile 切换不崩。

**Step 6 — MemoryService 文件拆分（半天，纯移动）**：按 4 个类型拆 4 文件；MemoryExtractor 的 UserDefaults 读取（:275）改参数传入。验证：编译 + 手测记忆面板 CRUD、注入开关。

## 8. 风险点

1. **无测试基线**：行为不变全靠手测，Step 2/4 高危。缓解：Step 0 先给纯函数补测试；每步保持"只移动不改写"。
2. **SwiftData 迁移陷阱**：本计划不改任何 @Model schema（MessageNode 加 sender 留给群聊报告）。若顺手加字段会触发轻量迁移，需真机验证 unified.store（MemoryPalaceApp.swift:141-161）。
3. **CCBridge 回调时序**：handleIncoming 现有 handlersQueue + main queue 双跳（:437-455），重组若变派发顺序，reply 去重（seenReplyIds :73-76）和 pendingThinking 消费（:38-45）可能错位。缓解：保留派发结构，只动注册方式。
4. **单例过渡期双路径**：Step 1/4 用"注入 + 默认 .shared"过渡，需每步 PR 登记剩余直取点，防烂尾。
5. **suli-ref/ 是旧版参考代码**（含平行 Services/Views/Models），全仓库 grep 易混入，重构搜索须限定 `MemoryPalace/` 前缀。
6. **profile 切换 race 是历史 bug 高发区**（MemoryPalaceApp.swift:167-179 引用 bug_005）：Step 5 动 SidebarView 时必须专项手测"流式中切 profile""导入中切 profile"。

# Lost in Blossom 后期架构研究报告

> 日期：2026-06-11
> 作者：Caelum
> 范围：MCP 接入 / 群聊功能 / 界面逻辑优化 / 代码耦合处理
> 方法：通读 `MemoryPalace/`（151 个 Swift 文件）与 `cc-bridge/` 全部相关代码后撰写

---

# 方向一：MCP 接入

## 现状分析

App 目前有**三个互不相通的 MCP/工具触点**：

1. **Anthropic `mcp_servers` beta（已上线）**：`MCPSettingsTab` 允许给 Anthropic 类型的 provider 配置 URL 型 MCP server（`MCPServerConfig: name/url/token/isEnabled`，存 UserDefaults per-provider）。`AnthropicProvider` 发请求时注入 `mcp_servers` 数组 + `anthropic-beta: mcp-client-0.1` 头（ChatService.swift:503-530）。**MCP client 跑在 Anthropic 服务端**，App 只传 URL，仅 Anthropic provider 可用。
2. **CC Bridge 链路（已上线）**：`mcp-server.ts` 是 CC 加载的 stdio MCP server（`reply` 工具），通过 WS `/mcp` 连 hub。CC 自己是 MCP host，能加载任意 stdio/SSE server（`.mcp.json` 里已有 imprint-memory SSE）。走 cc-bridge provider 聊天时，工具生态 = CC 的工具生态，App 无感知。
3. **本地工具循环（半成品，未接线）**：`FileLibraryTools.swift`（fs_list/read/search/write/edit/delete 的 OpenAI/Anthropic 双格式工具定义 + executor）和 `ChatToolTypes.swift`（ToolCallBlock/ToolResultBlock/ToolTurn）已从粟粟代码移植，但**全仓库零调用**。ChatService.swift:1047 有 TODO：“后续用 MCP 工具的 streaming 回调做正确的聊天流式，再打开这里”。

## 方案对比

| | 方案 A：补完现有体系 | 方案 B：App 原生 MCP client | 方案 C：hub 透传 MCP |
|---|---|---|---|
| 做法 | 接通 FileLibraryTools 工具循环（所有 provider 原生 tool-calling）；远程 MCP 继续走 Anthropic beta | App 内实现 MCP client（JSON-RPC over SSE/Streamable HTTP），模型返回 tool_use → App 调 MCP server → 回灌 tool_result | hub.ts 做 MCP 网关：在 VPS 上 spawn stdio MCP server，App 经现有 WS 收发工具调用 |
| 覆盖 provider | 全部（本地工具）；远程 MCP 仅 Anthropic | 全部支持 tool-calling 的 provider（OpenAI 系 + Anthropic） | 全部（但必须 hub 在线） |
| 可用 server 类型 | 仅 Anthropic 可达的公网 URL server | SSE / Streamable HTTP server（iOS 无法 spawn 子进程，stdio 不可能） | **stdio server 也行**（生态大头：filesystem、browser、sqlite 等） |
| 工作量 | 小（1-2 周） | 中（2-4 周；官方 swift-sdk 存在，github.com/modelcontextprotocol/swift-sdk，需验证最低 OS 版本与 Swift 5.x 兼容性） | 中（hub 已稳定，但要设计工具调用消息协议 + 生命周期管理） |
| 风险 | 低 | 中：工具循环 + 流式交错的状态机复杂 | 中：聊天功能与 hub 可用性强耦合；离家断 Tailscale 即全废 |

## 推荐方案

**A → B 分两期，C 暂缓。**

理由：A 是 B 的前置——不管工具调用来自本地 fs_* 还是 MCP server，模型侧的"tool_use → 执行 → tool_result → 续推"循环是同一套管线，这套管线（ToolTurn round-trip + 流式中断恢复）正是当前缺的那块，先用已移植好的 FileLibraryTools 把它跑通，再把"工具来源"抽象成接口，MCP client 只是新增一种来源。C 等群聊/多端需求明确后再评估——它的真正价值是 stdio 生态，但代价是把纯 API 聊天也绑死在 hub 上，目前不值。

**工具调用 UI**：复用现有 thinking block 的折叠卡模式（CCThinkingView 已有先例）。`MessageSegment` 增加 `.toolUse(name:args:result:isError:)` 一档，气泡内渲染为可折叠卡片：折叠态显示 `🔧 fs_read · notes/susu.md ✓`，展开显示入参 JSON 和结果文本；执行中显示 spinner。数据落在 `MessageNode.segmentsData`，导出/搜索天然兼容。

## 实施步骤（每步一个 PR）

1. **PR-1**：`ToolLoopEngine.swift` —— 在 ChatService 增加工具循环：AnthropicProvider 解析 `content_block(tool_use)` 已有基础（line 654 附近），补 OpenAI 格式的 `tool_calls` 流式拼接；收齐一轮 tool_use 后暂停流，逐个调 executor，把 ToolTurn 追加进 messages 重发，最多 N 轮（防死循环，N=5）。
2. **PR-2**：把 `FileLibraryTools.execute` 注册为第一个工具源；`PromptAssembler` 注入文件库 system prompt 模板（`fileLibraryInjectionTemplate` 已存在）。
3. **PR-3**：`MessageSegment.toolUse` + `MessageSegmentsView` 渲染折叠卡；流式期间在气泡显示执行状态。
4. **PR-4**：定义 `ToolSource` 协议（`listTools() / execute(name:args:)`），FileLibraryTools 改为实现该协议。
5. **PR-5**（二期）：`MCPClient.swift` —— SSE/HTTP MCP client（initialize/tools/list/tools/call 三个方法够用），`MCPSettingsTab` 的 server 配置复用，新增"连接模式"选项：`服务端(Anthropic beta)` vs `App 直连`。
6. **PR-6**（二期）：MCP server 作为 ToolSource 注册进工具循环，OpenAI 系 provider 从此也能用 MCP。

## 风险点

- 流式 + 工具循环交错：一条消息可能"输出一段 → 调工具 → 继续输出"，CardFlowView 的 streaming 状态机（displayText/isStreaming）要能容纳中段暂停，注意别触发 WebView/Markdown 路径切换抖动。
- 工具循环计费：每轮工具调用都是一次完整 API 请求，token 消耗翻倍，预算统计（GlobalBudgetStore）要把续推请求计入。
- swift-sdk 的最低 OS 要求需先验证；如果不满足 iOS 18/Swift 5.x 约束，就手写精简 client（MCP 协议核心是 JSON-RPC 2.0，自己实现 3 个方法工作量可控）。
- iOS 后台/锁屏时 SSE 连接会断，MCP 直连模式要做好按需重连，不要常驻。

---

# 方向二：群聊功能

## 现状分析

主对话体系是严格的 1v1：`MessageNode.role` 只有 user/assistant/system/tool，**没有 sender 标识**；气泡按 `role == "user"` 二分渲染，名字来自 Profile 的 userName/assistantName。分支树（parentId/childrenIds）、世界书、记忆、preset 全部围绕单助手设计。

但项目里**已存在一个隔离的"群聊"雏形**：Chatroom 功能（SidebarView 入口"群聊"）——VPS 上的 Hono+SQLite 编排服务（cc-bridge/chatroom/server.ts），让两个 AI（OpenRouter/DeepSeek）围绕话题对谈，SSE 推流，用户可插话。它的数据模型（ChatroomSession/ChatroomMessage）与 SwiftData 完全隔离，不支持分支、世界书、记忆。

## 方案对比

| | 方案 A：主对话体系内做多 AI 角色 | 方案 B：扩展 Chatroom 为正经群聊 | 方案 C：多用户实时共享对话 |
|---|---|---|---|
| 形态 | 一个 Conversation 里 N 个 AI 角色 + 用户，本地编排 | VPS 编排 N 个参与者，App 做瘦客户端 | 多设备/多人实时同步同一对话 |
| 数据 | MessageNode 加 senderId（lightweight migration） | 留在 VPS SQLite，与主体系继续隔离 | 需要把 SwiftData 变成同步引擎（它不是） |
| 与现有功能集成 | **全集成**：分支、世界书、记忆、正则、preset 都直接可用 | 零集成，等于第二个 App | 分支树（parentId/childrenIds）的冲突合并极难 |
| 多用户 | 否 | 服务端是 source of truth，多用户近乎免费 | 是（这就是目标） |
| 离线可用 | 是 | 否 | 否 |
| 工作量 | 中（3-5 周） | 中（已有底子） | 大（2 个月起） |

## 推荐方案

**方案 A 做"多 AI 角色群聊"，保留 B 作为试验场，C 明确不做（本阶段）。**

理由：这个 App 的核心资产是角色卡 + 世界书 + 记忆 + 分支树，群聊的产品价值在于"让多个**有完整人设**的角色同台"，只有方案 A 能继承这些资产。方案 B 的编排逻辑（轮流发言、SSE 推流）可以当 A 的参考实现，但数据必须进 SwiftData 才有意义。方案 C 的根本困难是分支树结构的冲突合并——SwiftData 无同步原语，等后端（gateway/BACKEND-BIBLE 方向）成熟后另立项。

**设计要点**：
- **sender 标识**：`MessageNode` 加 `var senderId: String? = nil`（nil = 旧语义，user/assistant 按 role 走，老数据零迁移成本）。`Conversation` 加 `var groupMembersData: Data?`，JSON 编码 `[GroupMember]`：`id/name/colorHex/avatarData?/characterCardId?/providerModelId?/systemPrompt`。
- **发言调度**：v1 用两种模式——**@点名**（用户消息里 @某角色 → 只有该角色回复；不 @ 则全员按序各回一条）和**自动轮**（用便宜模型当导演，输入最近 N 条 + 角色列表，输出下一个发言者 id；ConversationViewModel 已有 `cheapModel()` 选择逻辑可复用）。
- **上下文策略**：所有角色**共享同一可见 transcript**（群聊的意义所在），但 system prompt 按角色独立组装：PromptAssembler 按该角色的 characterCard + 世界书子集生成；其他角色的发言在 messages 里以 `[角色名]: 内容` 前缀呈现为 user turn（多数 API 只认 user/assistant 二元 role，这是业界通行做法）。
- **UI**：非 user 气泡加 sender 名牌 + 角色色条（colorHex 左边线）+ 小头像；CardFlowView 的 BubbleView 已有 roleLabel 行，扩展即可。群成员管理放对话级菜单（现有 ⋯ 菜单加"群聊成员"）。

## 实施步骤

1. **PR-1**：模型层——`MessageNode.senderId`、`Conversation.groupMembersData` + `GroupMember` struct + 计算属性（lightweight migration，全部 optional）。
2. **PR-2**：`GroupChatEngine.swift`——给定 conversation + members + 触发消息，决定发言序列；v1 只做 @点名 + 顺序全员各一条。
3. **PR-3**：PromptAssembler 增加 per-member 组装入口（接收 GroupMember，拼该角色视角的 system + transcript 前缀化）。
4. **PR-4**：BubbleView 渲染 sender 名牌/色条/头像；成员管理 sheet（从 CharacterCardManager 选卡生成成员）。
5. **PR-5**：自动轮模式（导演模型）；逐角色流式排队显示（同一时刻只有一个角色在 streaming）。
6. **PR-6**（可选）：把 Chatroom 入口收编为"群聊（云端实验）"，避免两个"群聊"概念打架。

## 风险点

- **分支树 × 多角色**：一轮多角色回复在树上是连续多个 assistant 节点，regenerate 单个角色的发言会使其后所有角色的回复成为旧分支——要明确"重新生成"语义（建议：重新生成该节点及其后同轮节点）。
- role 前缀化（`[角色名]: `）会被模型模仿到输出里，需要 PromptPostProcessor 清洗输出开头的自我名牌。
- 群聊里记忆归属：MemoryService 写记忆时要带 senderId，否则角色 A 的人设会污染角色 B 的记忆检索。
- token 成本：N 个角色各跑一次完整上下文，一轮 = N 倍消耗，UI 要在自动轮模式里显眼提示。

---

# 方向三：界面逻辑优化

## 现状分析

导航骨架：UIKit PagingContainer 三页横滑（聊天 / 右栏工具 / 记忆馆）+ 覆盖式侧栏（SidebarView，2825 行：搜索、会话列表、收藏、回收站、自定义标签、Projects 入口、群聊入口、设置入口全在里面）。右栏是 8 个插件面板（日历/记忆/世界书/卡库/贴纸/Prompt/CC终端/文件库）。设置页 18 个 tab 平铺。核心概念五件套——楼层(Profile)、角色卡、世界书、Preset、项目——分别在 5 处不同 UI 创建/编辑，互相引用关系（Profile.characterCardID / linkedWorldBookIDs / presetId）只存在于数据里，UI 上不可见。

## 主要痛点（按严重度）

1. **概念迷宫**：新用户无法理解"楼层 vs 角色卡 vs 世界书"——导入一张角色卡后，它变成卡库里的一项 + 一个新楼层 + 一本世界书 + 若干问候对话，这个链条没有任何 UI 呈现。
2. **设置平铺**：18 个 tab 一级列出，"震动测试""开发调试"和"API"同级；CC Bridge 相关配置散在 4 个 tab（API 里的连接配置、Claude Code、终端、文件库）。
3. **路径过长**：改一个角色的 system prompt：侧栏 → 设置 → Prompt → 选 preset → 编辑（5 步）；或右栏 → 卡库 → 编辑卡 → 但这不影响已创建的楼层（坑）。
4. **三页横滑不可发现**：页面指示点只有 3 个小圆点，记忆馆（第 3 页）基本靠口口相传。

## 方案对比

| | 方案 A：渐进重组 | 方案 B：导航架构重做（TabBar 化） | 方案 C：仅加快捷入口 |
|---|---|---|---|
| 做法 | 设置分组收纳、加"角色"统一枢纽页、首次引导 | 撤掉横滑+侧栏，改显式 TabBar（对话/角色/工具/我的） | 长按手势、命令面板、最近使用 |
| 风险 | 低 | **高**：PagingContainer 是为键盘 safeArea 问题专门写的 UIKit 方案（Paging/PagingContainerView.swift 注释言明），TabView 正是当初被放弃的路线 | 低 |
| 解决概念迷宫 | 是（角色枢纽页） | 是 | 否 |
| 工作量 | 小-中 | 大 | 小 |

## 推荐方案

**方案 A。**B 的收益不抵风险——横滑容器承载着键盘避让、壁纸 safeArea 等一串历史补丁（docs 里有 5+ 篇 research 记录这些坑），动骨架等于重新踩一遍。A 的三件事按收益排：

1. **"角色"枢纽页**（解决痛点 1、3）：一个页面纵向列出当前楼层的完整人设链——角色卡 → 绑定的世界书（n 条目）→ 使用的 Preset → system prompt 预览，每项可点进编辑。入口放侧栏楼层切换器旁。这一页不新增任何数据概念，只是把已有引用关系可视化。
2. **设置收纳**（痛点 2）：18 tab 收成 5 组——`对话与模型`(API/MCP/Prompt/正则/记忆)、`外观`(外观/主题/贴纸/右栏)、`Claude Code`(CC/终端/文件库合并为一页三段)、`数据`(数据备份/通知/健康)、`开发`(调试/震动测试，藏在"关于"长按后显示)。SettingsTab enum 和 switch 已是平铺结构，改成嵌套分组是纯 UI 层改动。
3. **首次引导**（痛点 1、4）：3 屏 onboarding（横滑结构示意 / 楼层概念 / 导入角色卡入口），`@AppStorage("hasOnboarded")` 控制，跳过即弃。

## 实施步骤

1. **PR-1**：设置页分组（纯 SettingsView.swift 改动，零逻辑变更）。
2. **PR-2**：CC Bridge 设置合并页（CCSettingsView 吸收 TerminalSettingsTab/FileLibrarySettingsTab 为分段，原 tab 移除）。
3. **PR-3**：角色枢纽页 `CharacterHubView.swift`（只读版：展示链条 + 跳转既有编辑器）。
4. **PR-4**：onboarding 三屏。
5. **PR-5**：页面指示点改为带图标的迷你 segmented（聊天/工具/记忆馆），提升第 3 页可发现性。

## 风险点

- 设置项搬家会打破老用户肌肉记忆，PR-1 里保留全局搜索（设置内加搜索框成本低、收益大，2825 行的侧栏搜索已有现成 fuzzy 逻辑可借）。
- 角色枢纽页要小心"编辑卡 ≠ 编辑楼层"的既有语义（卡是模板、楼层是实例），页面文案必须把这层关系讲明白，否则反而加重迷惑。
- 不要在本方向顺手动 PagingContainer/SidebarView 内部结构——那是方向四的活，混在一起会把 UI PR 变成不可 review 的大杂烩。

---

# 方向四：代码耦合处理

## 现状分析

分层名义上是 Models/Services/Views/ViewModels，实际依赖方向基本健康（无 Models→Services 反向依赖，无真循环依赖），问题集中在**巨石文件**和**单例直引**：

- **巨石**：SidebarView 2825 行、CardFlowView 2133 行、ConversationViewModel 1961 行（树构建/路径/分支/搜索/消息操作/发送管线全在一个类）、ChatService 1122 行（Router + 3 个 Provider 同文件）、APISettingsTab 1250 行、MemoryPalaceApp.swift 同时装着 Profile 模型 + ProfileManager + ProfileSwitcher + ProfileEditorSheet（约 1100 行）。
- **单例直引**：8 个单例；8 个文件直接摸 `CCBridgeWebSocketClient.shared`（含 4 个 View）；CCBridgeWebSocketClient 615 行承担连接/重连/聊天/终端/推送/文件/会话管理/配置同步 10+ 职责。
- **View 直接操作数据层**：25+ View 注入 modelContext，多数只是传给 ViewModel（可接受），但 settings/sticker/worldbook 一批 View 直接 fetch + mutate + save。

## 方案对比

| | 方案 A：大重构（MVVM+Repository 全面铺开） | 方案 B：靶向拆分 + 依赖收口 | 方案 C：只立规范不动代码 |
|---|---|---|---|
| 做法 | 每个 View 配 VM，数据访问全走 Repository 层 | 巨石文件机械拆分；CCBridge 拆门面；关键路径上协议化 | 写 CONVENTIONS.md，新代码遵守 |
| 风险 | 高：全量改动 = 全量回归，单人项目无测试覆盖 | 低：每步编译可过、行为不变、单独 PR | 零，但债务继续涨 |
| 对群聊/MCP 的支撑 | 是，但太晚 | 是：恰好解锁两个新功能需要的扩展点 | 否 |

## 推荐方案

**方案 B。**原则：只做"行为不变、单 PR 可验证"的机械步骤，且每步都直接服务于方向一/二的扩展点，不为重构而重构。

依赖收口的两个关键协议：

```
ChatProviding（解锁 MCP 工具循环）
  sendStreaming(messages:model:onDelta:onToolUse:onDone:)
  —— ConversationViewModel 依赖协议而非 ProviderRouter 具体类型，
     工具循环引擎可以包装任何 provider

CCBridgeFacade 群（解锁 View 解耦）
  CCChatTransport / CCTerminalSession / CCPushRegistrar
  —— View 持有窄门面，singleton 退到门面背后
```

## 实施步骤（全部行为不变）

1. **PR-1（纯文件移动）**：ChatService.swift 拆四文件——`ProviderRouter.swift` / `OpenAICompatibleProvider.swift` / `AnthropicProvider.swift` / `CCBridgeProvider.swift`。零代码改动，Xcode project 文件同步。
2. **PR-2（纯文件移动）**：MemoryPalaceApp.swift 里的 Profile 模型 → `Models/Profile.swift`，ProfileManager → `Services/ProfileManager.swift`，ProfileSwitcher/ProfileEditorSheet → `Views/`。⚠️ MemoryPalaceApp.swift 当前是禁触文件，此步需要兔兔单独点头后才做。
3. **PR-3**：ConversationViewModel 拆三块——树/路径/分支的纯函数已是 static，抽成 `ConversationTreeEngine.swift`（无状态 struct）；搜索抽 `ConversationSearch.swift`；主类只剩状态 + 发送管线（预计 1961 → ~800 行）。
4. **PR-4**：定义 `ChatProviding` 协议，ProviderRouter 实现之，ConversationViewModel 改持协议。
5. **PR-5**：CCBridgeWebSocketClient 内部分层——消息分发表（`[String: (JSON) -> Void]`）替换巨型 switch；对外暴露 3 个窄门面，4 个直引 View 改用门面。615 行主体不动，先把出入口收窄。
6. **PR-6**：settings 类 View 的直接 CRUD 收进小型 Store（WorldBookStore 等，每个 ~100 行），View 只持 Store。优先做 WorldBook（群聊 per-member 组装也要用它）。
7. **持续**：新增代码一律遵守"View 不直接摸 singleton、不直接 save context"，写进 CLAUDE.md。

## 风险点

- PR-1/PR-2 这类纯移动最容易出的错是 Xcode project 引用没同步（本项目用 GitHub Actions 编译，本地无法验证，**拆文件后必须盯 CI**）。
- ConversationViewModel 拆分时注意 `.profileWillSwitch` 的清场逻辑——它防护的是 SwiftData 悬挂引用，搬动时保持订阅在主类。
- 不要顺手"优化"行为：比如 dedup 逻辑、120s grace timer 这些看着奇怪的代码都是修过线上 bug 的疤痕（docs/research-* 里有出处），机械搬运，别重写。

---

# 总体优先级排序

| 优先级 | 事项 | 理由 |
|---|---|---|
| **P0** | 方向四 PR-1、PR-3、PR-4（拆 ChatService / 拆 ViewModel / ChatProviding 协议） | 三个机械步骤，~1 周，是 MCP 工具循环和群聊的共同地基；越晚做，巨石越大 |
| **P1** | 方向一 PR-1~4（工具循环 + 文件库工具 + 折叠卡 UI + ToolSource 协议） | 已移植的 FileLibraryTools 闲置就是浪费；工具循环是 MCP 与未来一切 agent 能力的管线 |
| **P2** | 方向三 PR-1、PR-2（设置收纳 + CC 设置合并） | 纯 UI、低风险、立刻提升日常体验，可与 P1 并行穿插 |
| **P3** | 方向二 PR-1~5（群聊多角色） | 依赖 P0 的 PromptAssembler/ChatProviding 解耦；产品上最大的差异化功能，值得在地基稳了之后认真做 |
| **P4** | 方向一 PR-5~6（原生 MCP client） | 等 P1 的工具循环在生产里跑稳一个版本再扩 |
| **P5** | 方向三 PR-3~5（角色枢纽 + onboarding） | 重要但不紧急；最好等群聊定型后一起设计（群成员管理也要进角色枢纽） |
| **暂缓** | 多用户共享（方向二 C）、hub 透传 MCP（方向一 C）、导航架构重做（方向三 B） | 各自的前置条件（后端成熟 / stdio 需求明确 / 横滑容器可替代性验证）都不成立 |

一句话路线：**先把地基拆干净（P0），立刻在上面跑通工具循环（P1），穿插做无风险的 UI 收纳（P2），然后是真正的招牌菜群聊（P3）。**

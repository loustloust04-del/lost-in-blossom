# 调研：MCP 接入（research-fable 01）

> 日期：2026-06-11
> 范围：App 直接与外部 MCP 工具交互的架构选型
> 先行研究：`docs/research-mcp-integration.md`（2026-05-25）、`docs/task-mcp-client.md`（2026-06-04）、`docs/task-mcp-settings-ui.md`。本文是它们的增量更新，**不重复已落地的部分**，重点核对实现现状并补全缺口。

---

## 1. 现状分析

仓库里实际存在**三条 MCP 相关链路，两条已完工，一条做了一半**：

1. **CC Bridge 反向通道**（完工）：`cc-bridge/mcp-server.ts` 是一个 stdio MCP server，只暴露 `reply` 工具（mcp-server.ts:85-116），把 CC 的回复经 WS 推到 `hub.ts` 的 `/mcp` 路径（hub.ts:583-676）再广播给 App。这里 MCP 是「CC→App 出口」，与"App 调外部工具"无关。
2. **Anthropic `mcp_servers` beta 直连**（完工）：`ChatService.swift:503-531` 注入 `mcp_servers` + `mcp-client-0.1` header（:530），SSE 的 tool_use/tool_result 解析在 :640-699；配置模型 `MCPServerConfig`（`Models/APIProvider.swift:7-13`）、设置页 `Views/MCPSettingsTab.swift` 均已接入。
3. **VPS REST 翻译层**（半成品）：`mcp-bridge/mcp-rest-bridge.js` 已实现 4 个端点（/mcp/tools :34、/mcp/call :49、/mcp/connect :61、/mcp/status :72），但 **App 端消费者 `MCPService.swift` 不存在**，非 Anthropic provider 至今没有任何工具能力。

---

## 2. 方案对比

研究问题 1、2、4 的答案集中在此表。

| 维度 | A. Anthropic `mcp_servers` beta（现状主路径） | B. VPS REST Bridge + 客户端 tool calling（补全半成品） | C. App 原生 MCP client（swift-sdk） |
|---|---|---|---|
| 数据流 | App → Anthropic API → MCP server（Anthropic 服务器代为连接执行） | App → `mcp-rest-bridge.js`(:3200) → MCP server（Streamable HTTP，mcp-rest-bridge.js:21） | App → MCP server（直连，Streamable HTTP/SSE） |
| 适用 provider | 仅 Anthropic（MCPSettingsTab.swift 已有此提示） | 全部（OpenAI/DeepSeek function calling + Anthropic tools） | 全部 |
| App 端复杂度 | 极低，已落地 | 中：一个 HTTP client + 一个 tool-calling 多轮循环 | 高：协议握手、session 管理、OAuth、重连全在 Swift 侧 |
| 新增依赖 | 无 | 无（URLSession 即可） | `modelcontextprotocol/swift-sdk`（官方 SDK，存在且活跃维护，支持 stdio + Streamable HTTP client transport；要求 Swift 6.0 / iOS 17+。注意 iOS 无法 spawn 子进程，**stdio transport 在 iOS 上不可用**，只能用 HTTP/SSE/streamable，所以本地 stdio 型 server（如 npx 系）一律接不了，必须有公网/局域网 HTTP 端点） |
| MCP server 可达性要求 | 必须公网可达（Anthropic 服务器要能连上） | VPS 可达即可（内网 server 也行） | 公网或 Tailscale 可达 |
| 单点/故障面 | Anthropic beta 接口本身 | bridge 进程是单点；长连接断后无重连（见风险 R2） | 无中间层，但每台设备各自维护 N 条长连接，移动网络切换下最脆弱 |
| 与 CC Bridge 关系 | 无关 | 无关（独立于 hub.ts） | 无关 |

**「MCP 走 CC Bridge 透传」单独说明**：即把 App 的工具调用请求经 hub.ts WS 转给 CC 执行。不建议作为通用方案——hub 的 `/mcp` 路径只处理 `type:"reply"`（hub.ts:592），扩展它等于在 WS 协议里再造一遍 JSON-RPC，且把工具能力绑死在「CC 会话存活」这个前提上；CC 会话本来就能用自己的 `.mcp.json` 工具（cc-bridge/.mcp.json 已配 imprint-memory SSE），透传没有增量价值。

**研究问题 3：哪些工具值得接 + EventKit 这条路**

| 工具 | 建议路径 | 理由 |
|---|---|---|
| 日历、提醒事项 | **iOS 原生本地工具，不走 MCP** | EventKit（`EKEventStore`）直接读写系统日历/提醒，离线可用、零网络延迟、权限走系统弹窗。把它包装成本地 tool（与 MCP 工具一起进 `tools` 数组，模型无感知差异），比起经 VPS 绕一圈 CalDAV 强得多 |
| 备忘录 | 降级处理 | Apple Notes 无公开读写 API（只有 Shortcuts/分享扩展），MCP 也救不了。建议用 App 自己的写作/记录系统替代 |
| 文件系统 | 方案 B（VPS 侧 filesystem MCP server） | 真正想操作的是 VPS 上的文件；iOS 沙盒内文件意义不大 |
| 浏览器 | 方案 B（VPS 侧 Playwright/browser MCP server） | 必须有宿主机，天然属于 VPS |
| imprint-memory | 方案 A（已可用） | 公网 SSE endpoint，填进 MCPSettingsTab 即可 |

---

## 3. 推荐方案

**A + B 分层并行，C 不做（暂时），日历/提醒走 EventKit 本地工具。**

- 方案 A 已经写完并接好 UI，是 Anthropic provider 的零成本主路径，保留。
- 方案 B 的 VPS 侧已存在（mcp-rest-bridge.js），只差 App 侧约 200 行：补 `MCPService.swift` + provider 层 tool-calling 循环，即可让所有 provider 获得工具能力。这是性价比最高的下一步。
- 方案 C（swift-sdk）放弃的理由：B 的 REST 翻译层已把 MCP 协议复杂度（session、重连、transport 协商）留在 Node 侧，Swift 侧只剩两个 HTTP 接口；引入 swift-sdk 等于推倒已有资产重做，换来的唯一好处是去掉 bridge 单点——而 iOS 上 stdio 不可用的限制意味着即便用 SDK，可接的 server 集合和 B 完全一样。等 swift-sdk 生态再成熟一轮（以及 beta `mcp-client-0.1` 若被弃用时）再评估。
- UI（研究问题 5）：不写新组件。`MessageSegment.toolUse/.toolResult`（Models/MessageSegment.swift:10-22）+ `ToolCallCardView`（Views/MessageSegmentsView.swift:382-461，已支持折叠、错误态、toolUse+toolResult 自动配对成 `.toolPair`，:130-138）直接复用；本地 EventKit 工具的调用也输出同样的 segment，渲染层零改动。唯一缺口是「调用进行中」状态——现在是 block 结束后一次性出卡片（与 ThinkingBlockView :347-378 一致），客户端 tool calling 下执行期可能长达数秒，需要 pending 态。

---

## 4. 实施步骤（单 PR 粒度）

**PR-1：`MCPService.swift`（REST bridge 客户端）**
- 新建 `MemoryPalace/Services/MCPService.swift`：`fetchTools() async throws -> [MCPToolDescriptor]`、`callTool(server:tool:arguments:) async throws -> [MCPContentBlock]`，对应 mcp-rest-bridge.js 的 GET /mcp/tools 与 POST /mcp/call。
- bridge baseURL + token 配置：在 `MCPSettingsTab.swift` 加「工具桥」区块；token 存 Keychain，不进 UserDefaults。
- 工具列表带 5 分钟内存缓存（每条消息都拉一次列表不可接受）。

**PR-2：客户端 tool-calling 循环（Anthropic `tools` 路径）**
- `ChatService.swift` 的 `AnthropicProvider`：当配置了 bridge 工具时，请求体注入 `tools`（name/description/input_schema 来自 PR-1 缓存）；复用现有 `ActiveBlock` 解析（:640-699），在 `message_stop` 且 `stop_reason == "tool_use"` 时调 `MCPService.callTool`，把 `tool_result` 追加进 messages 再发一轮，循环上限 5 次。
- `ConversationViewModel` 在每轮把 toolUse/toolResult append 进 `assistantNode.segments`（沿用 research-mcp-integration.md §7 的 onSegment 回调，已有实现则复用）。

**PR-3：OpenAI 兼容 provider 的 function calling**
- `OpenAICompatibleProvider`：注入 `tools`（function 格式），解析 `delta.tool_calls`，同一套 `MCPService.callTool` 循环。与 PR-2 共享循环逻辑（抽 `ToolCallLoop` helper）。

**PR-4：EventKit 本地工具**
- 新建 `MemoryPalace/Services/LocalToolRegistry.swift`：`calendar_list_events`、`calendar_create_event`、`reminder_list`、`reminder_create` 四个工具，`EKEventStore` 实现；iOS 17+ 用 `requestFullAccessToEvents()/requestFullAccessToReminders()`，Info.plist 加 `NSCalendarsFullAccessUsageDescription`、`NSRemindersFullAccessUsageDescription`。
- 在 ToolCallLoop 里先查 LocalToolRegistry 再 fallback 到 MCPService——本地工具与远程工具对模型暴露为同一个 `tools` 数组。

**PR-5：工具调用 pending 态 UI**
- `ToolCallCardView` 加 `isRunning` 态（toolUse 已出现、toolResult 未到）：spinner + 「调用中…」；`MessageSegmentsView` 的 `.toolPair` 配对逻辑（:130-138）允许 result 为 nil。

**PR-6（VPS 侧，可选但建议尽早）：bridge 加固**
- `mcp-rest-bridge.js`：给 `connectMCP` 加断线重连（transport `onclose` 时标记 stale，`/mcp/call` 遇 stale 先重连再调用）；监听地址从 `0.0.0.0`（:80）收紧到 127.0.0.1 + nginx 反代；去掉 `BRIDGE_TOKEN` 的硬编码默认值 `'bunny-mcp-2026'`（:9），改为缺失即拒绝启动（参考 hub.ts:327-330 的做法）。

---

## 5. 风险点

- **R1（beta 依赖）**：`mcp-client-0.1` 是 Anthropic beta，字段或行为可能变动甚至下线；且要求 MCP server 公网可达、鉴权只支持静态 `authorization_token`（无 OAuth flow）。缓解：PR-2/3 的客户端循环天然是它的替代路径。
- **R2（bridge 单点 + 无重连）**：`mcp-rest-bridge.js:19-32` 建连后没有任何 `onclose`/心跳处理，Streamable HTTP 长连接一断，`connections` 里的 client 变僵尸，后续 `/mcp/call` 全部 500。PR-6 必须做，否则 B 路径在生产上不可靠。
- **R3（安全）**：token 硬编码默认值 + `0.0.0.0` 监听 + `/mcp/connect` 允许任意 URL（SSRF 面）。token 必须强制配置，connect 端点建议加 URL 白名单。
- **R4（多轮循环成本与时延）**：客户端 tool calling 每次工具调用都要带全量上下文重发一轮请求，长对话下 token 成本翻倍、首字时延叠加；移动网络下 app 切后台还可能让 URLSession 挂起，循环中断后对话停在 tool_use 半截。需要循环上限 + 中断恢复（把未完成的 tool_use 标记 isError 落库）。
- **R5（EventKit 权限）**：iOS 17 改了日历/提醒权限模型，拒绝授权后工具要优雅降级（返回 isError 的 tool_result 而不是抛错中断流式）；写日历是真实世界副作用，create 类工具建议加一次 UI 确认。
- **R6（swift-sdk 误判）**：如果未来转方案 C，注意官方 swift-sdk 仍较新（相对 TypeScript SDK 功能滞后），且 iOS 上永远没有 stdio——选型评估时不要拿 macOS 的 demo 当 iOS 可行性证据。

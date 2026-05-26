# Research: Phase 2 MCP 工具调用集成

> 日期：2026-05-25  
> 版本：v2（基于完整代码阅读，覆盖 task-phase2-mcp-integration.md 全部研究点）  
> 状态：研究完成，等天奕确认后进入 Plan

---

## 0. 结论先行（TL;DR）

1. **UI 层已就绪**：`MessageSegment.toolUse/.toolResult` 数据模型 + `ToolCallCardView` 渲染组件已由粟粟实现，工具调用结果的展示**不需要新写任何 UI 代码**。
2. **最轻接入路径**（Anthropic `mcp_servers` beta）：在 `AnthropicProvider.sendStreaming()` 里加一个 `mcp_servers` 字段，加一个 beta header，**imprint-memory 就接进来了**，Anthropic 服务器侧自动处理工具执行，iOS 只需解析 tool 相关 SSE 事件并渲染。
3. **需要改的地方只有三处**：
   - `APIProvider` / `Preset` 加 MCP server 配置字段
   - `AnthropicProvider` 注入 `mcp_servers` + 解析 `tool_use`/`tool_result` SSE 事件
   - 流式过程中把 `MessageSegment.toolUse/.toolResult` append 到 `assistantNode.segments`

---

## 1. 现有请求构建管道精读

### 1.1 整体数据流

```
ConversationViewModel.sendMessage()
  │
  ├─ assemblePrompt()
  │     ├─ PromptAssembler.assemble()     ← 组装 system + messages（slot 系统）
  │     ├─ MemoryStore.listHot()           ← 注入 AUDN 记忆
  │     └─ WorldBook 条目注入
  │
  ├─ prepareRouterPayload()               ← ccBridge 特殊处理；其余透传
  │
  └─ ProviderRouter.sendStreaming()
        └─ 按 model.providerId 路由到具体 Provider
              ├─ OpenAICompatibleProvider  → POST /chat/completions (SSE)
              ├─ AnthropicProvider         → POST /messages (SSE)
              └─ CCBridgeProvider          → WebSocket → hub → tmux
```

### 1.2 PromptPostProcessor 的角色

`PromptPostProcessor` **不参与实际 HTTP 请求**，只用于：
- `buildRequestPreview()` —— 预览面板展示发出去的 JSON 是什么样
- `process()` —— squash/merge/strict 三种消息后处理模式

实际请求体的构建在 **各 Provider 的 `sendStreaming()`** 里直接手写，和 PostProcessor 是平行的两套。这意味着：

> ✅ MCP server 配置注入只需改 Provider 层，**不需要动 PromptPostProcessor**。  
> ⚠️ 如果未来想让预览面板也显示 `mcp_servers`，才需要改 PostProcessor。

### 1.3 AnthropicProvider 当前请求体

```swift
var body: [String: Any] = [
    "model": model,
    "messages": apiMessages,   // [{role, content}]
    "max_tokens": maxTok,
    "stream": true,
]
// 可选: system, temperature, top_p, top_k
```

缺失：`mcp_servers`、`tools`（本次要加的）。

### 1.4 AnthropicProvider 当前 SSE 解析

现有处理的事件类型：

| 事件 | 处理 |
|---|---|
| `message_start` | 记录 input_tokens |
| `content_block_delta` (text) | `onToken` 回调，流式更新 UI |
| `message_delta` | 记录 output_tokens |
| `message_stop` | `onComplete` 回调 |
| `error` | `onError` 回调 |

**缺失**（工具调用时会出现）：

| 事件 | 当前处理 | 需要新增 |
|---|---|---|
| `content_block_start` (tool_use) | `default: break` 丢弃 | 开始收集 tool_use 字段 |
| `content_block_delta` (input_json_delta) | 和 text delta 走一样逻辑，text 字段为空则丢弃 | 累积 tool input JSON |
| `content_block_stop` | 无 | 收尾 tool_use，写入 segment |
| `content_block_start` (tool_result) | — | mcp_servers 模式下出现，表示 Anthropic 已执行工具 |
| `content_block_delta` (tool_result text) | — | 累积结果文本 |

---

## 2. 已有的 UI 基础设施

### 2.1 MessageSegment 枚举（MessageSegment.swift）

```swift
enum MessageSegment: Codable, Hashable {
    case text(String)
    case thinking(text: String, signature: String?)
    case toolUse(id: String, name: String, inputJSON: String,
                 integrationName: String?, iconName: String?)
    case toolResult(toolUseId: String, text: String, isError: Bool,
                   integrationName: String?)
    case flag(...)
    case attachment(...)
    case file(...)
}
```

**结论**：工具调用所需的数据模型**完全现成**，直接用。

### 2.2 MessageSegmentsView + ToolCallCardView

- `MessageSegmentsView` 自动将相邻的 `toolUse + toolResult` 合并成一张卡片
- `ToolCallCardView`：可折叠的 🔧 工具调用卡，展示工具名、输入 JSON、结果文本
- 错误态（`isError: true`）和正常态样式已区分

**结论**：工具调用的 UI 展示**不需要写新代码**，直接往 `assistantNode.segments` 里 append 正确的 `MessageSegment.toolUse/.toolResult` 即可渲染。

---

## 3. Anthropic API —— mcp_servers 参数（Beta）

### 3.1 请求格式

```http
POST https://api.anthropic.com/v1/messages
x-api-key: {{API_KEY}}
anthropic-version: 2023-06-01
anthropic-beta: mcp-client-0.1        ← 必须加这个 Beta header
Content-Type: application/json

{
  "model": "claude-opus-4-7",
  "max_tokens": 4096,
  "stream": true,
  "mcp_servers": [
    {
      "type": "url",
      "url": "https://imprint.amberrib.com/sse",
      "name": "imprint-memory"
    }
  ],
  "messages": [
    {"role": "user", "content": "帮我记住我今天喜欢喝乌龙茶"}
  ]
}
```

### 3.2 mcp_servers 字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `type` | `"url"` | 目前 beta 版只支持 `"url"` |
| `url` | string | MCP server 的 SSE endpoint |
| `name` | string | server 标识，出现在 tool 名称的 namespace 中（`name__tool_name`） |
| `authorization_token` | string? | 可选，放在 MCP 请求的 Authorization header |
| `tool_configuration` | object? | 可选，指定 allowed_tools 限制调用哪些工具 |

### 3.3 工作原理

启用 `mcp_servers` 后，**Anthropic 服务器**（不是 iOS app）负责：
1. 连接 MCP server，获取 tool schema 列表
2. 当 Claude 决定调用工具时，Anthropic 代劳发 HTTP 请求给 MCP server
3. 把工具结果注入对话，Claude 继续生成

iOS app 的职责：
- 发送含 `mcp_servers` 的请求
- 解析 SSE 中的 `tool_use` / `tool_result` content blocks（透明可见）
- 渲染工具调用卡片

> ✅ 这个模式**不需要 iOS 自己去调用 MCP server**，大幅降低复杂度。  
> ⚠️ 要求 MCP server URL 可被 Anthropic 服务器访问（公网或 ngrok）。  
> `https://imprint.amberrib.com/sse` 是公网 URL，满足条件。

### 3.4 流式事件变化（mcp_servers 启用后）

工具调用时 SSE 流的典型序列：

```
event: message_start
event: content_block_start   {"index":0, "content_block":{"type":"text","text":""}}
event: content_block_delta   {"delta":{"type":"text_delta","text":"好的，我来帮你记住..."}}
event: content_block_stop    {"index":0}

event: content_block_start   {"index":1, "content_block":{"type":"tool_use","id":"toolu_01Abc","name":"imprint-memory__memory_remember","input":{}}}
event: content_block_delta   {"delta":{"type":"input_json_delta","partial_json":"{\"content\":\"喜欢乌龙茶\","}}
event: content_block_delta   {"delta":{"type":"input_json_delta","partial_json":"\"tags\":[\"饮食偏好\"]}"}}
event: content_block_stop    {"index":1}

event: content_block_start   {"index":2, "content_block":{"type":"tool_result","tool_use_id":"toolu_01Abc","content":"ok"}}
event: content_block_stop    {"index":2}

event: content_block_start   {"index":3, "content_block":{"type":"text","text":""}}
event: content_block_delta   {"delta":{"type":"text_delta","text":"已经记住了！"}}
event: content_block_stop    {"index":3}

event: message_delta         {"usage":{"output_tokens":42}}
event: message_stop
```

关键变化：
- `content_block_start` 现在可能包含 `type: "tool_use"` 或 `type: "tool_result"`
- `content_block_delta` 的 `delta.type` 新增 `"input_json_delta"` （tool 输入 JSON 片段）
- 需要按 `index` 追踪多个并发 content block

---

## 4. OpenAI Compatible API —— Function Calling 格式

OpenAI 格式使用 `tools` 数组（不支持 `mcp_servers`，需要客户端执行工具）：

```json
{
  "model": "gpt-4o",
  "messages": [...],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "memory_remember",
        "description": "存储一条记忆",
        "parameters": {
          "type": "object",
          "properties": {
            "content": {"type": "string"},
            "tags": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["content"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
```

SSE 响应中 tool 调用通过 `delta.tool_calls` 传递：
```json
{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"memory_remember","arguments":"{\"content\":"}}]}}]}
```

> ⚠️ OpenAI function calling 需要 **iOS 自己去执行 tool**（调用 MCP server），然后追加 `tool` role 消息发第二轮请求，比 Anthropic mcp_servers 复杂得多。  
> **Phase 2 不做 OpenAI function calling**，专注 Anthropic mcp_servers 路径。OpenAI 路径留 Phase 3 或按需。

---

## 5. 配置层设计

### 5.1 APIProvider 加 MCP Server 列表

在 `APIProvider` 里新增 `mcpServers: [MCPServerConfig]`，代表该 provider 可连接的 MCP server。

```swift
struct MCPServerConfig: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String              // "imprint-memory" — 对应 mcp_servers.name
    var url: String               // "https://imprint.amberrib.com/sse"
    var authToken: String?        // 可选鉴权 token
    var isEnabled: Bool = true
}

struct APIProvider: ..., Codable {
    // 现有字段 ...
    var mcpServers: [MCPServerConfig] = []   // 新增
}
```

**设计原则**：MCP server 挂在 `APIProvider` 上，不是 `Preset` 上。原因：
- MCP server 是基础设施（类似 provider 的 baseURL），跟具体角色无关
- 一个 provider 配好一次，所有对话都能用
- 如果挂 Preset，每个角色预设都要配一遍，繁琐

### 5.2 Preset/Profile 层的 MCP 开关

在 `SamplingParams` 加一个开关字段，按对话粒度控制是否启用 MCP：

```swift
struct SamplingParams: Codable, Hashable {
    // 现有字段 ...
    var mcpEnabled: Bool = true      // 是否在请求里附带 mcp_servers（默认开）
}
```

这样：
- Provider 配置了哪些 MCP server（基础设施）
- Preset 的 SamplingParams.mcpEnabled 控制是否在这次对话里用（对话粒度开关）

### 5.3 ProviderRouter 注入逻辑

`ProviderRouter.sendStreaming()` 已经拿到 `provider`（含 mcpServers）和 `samplingParams`（含 mcpEnabled）。  
只需在调用 `AnthropicProvider.sendStreaming()` 时把 mcpServers 传进去：

```swift
// ProviderRouter 现有
chatProvider.sendStreaming(
    messages: ...,
    model: ...,
    ...
)

// 改为（如果是 anthropic 且 mcpEnabled）
if case .anthropic = provider.type, samplingParams?.mcpEnabled == true {
    (chatProvider as? AnthropicProvider)?.sendStreamingWithMCP(
        mcpServers: provider.mcpServers.filter(\.isEnabled),
        ...
    )
} else {
    chatProvider.sendStreaming(...)
}
```

---

## 6. AnthropicProvider 改造方案

### 6.1 请求构建改动

```swift
// 现有
var body: [String: Any] = [
    "model": model,
    "messages": apiMessages,
    "max_tokens": maxTok,
    "stream": true,
]

// 新增：注入 mcp_servers
if !mcpServers.isEmpty {
    body["mcp_servers"] = mcpServers.map { s -> [String: Any] in
        var d: [String: Any] = ["type": "url", "url": s.url, "name": s.name]
        if let token = s.authToken { d["authorization_token"] = token }
        return d
    }
}

// 新增：beta header
request.setValue("mcp-client-0.1", forHTTPHeaderField: "anthropic-beta")
```

### 6.2 SSE 解析改动

新增两个累积器追踪多个并行 content block：

```swift
// 现有字段（仅有文本流）
fileprivate var streamingContent = ""   // 所有 text block 合并

// 新增：per-block 状态
fileprivate var activeBlocks: [Int: ActiveBlock] = [:]  // index → block

struct ActiveBlock {
    enum Kind { case text, toolUse(id: String, name: String), toolResult(toolUseId: String) }
    var kind: Kind
    var accumulated: String = ""
    var integrationName: String?
}
```

事件处理补充：

```swift
case "content_block_start":
    let block = obj["content_block"] as? [String: Any]
    let index = obj["index"] as? Int ?? 0
    switch block?["type"] as? String {
    case "tool_use":
        let id = block?["id"] as? String ?? ""
        let name = block?["name"] as? String ?? ""
        activeBlocks[index] = ActiveBlock(kind: .toolUse(id: id, name: name))
    case "tool_result":
        let toolUseId = block?["tool_use_id"] as? String ?? ""
        activeBlocks[index] = ActiveBlock(kind: .toolResult(toolUseId: toolUseId))
    case "text":
        activeBlocks[index] = ActiveBlock(kind: .text)
    default: break
    }

case "content_block_delta":
    let index = obj["index"] as? Int ?? 0
    let delta = obj["delta"] as? [String: Any]
    switch delta?["type"] as? String {
    case "text_delta":
        let text = delta?["text"] as? String ?? ""
        activeBlocks[index]?.accumulated += text
        // 只有 text block 走 onToken 实时更新
        if case .text = activeBlocks[index]?.kind {
            DispatchQueue.main.async { ... onToken?(text) }
        }
    case "input_json_delta":
        let partial = delta?["partial_json"] as? String ?? ""
        activeBlocks[index]?.accumulated += partial
    default: break
    }

case "content_block_stop":
    let index = obj["index"] as? Int ?? 0
    if let block = activeBlocks.removeValue(forKey: index) {
        finalizeBlock(block)  // append 到 pendingSegments
    }
```

`finalizeBlock` 把收集好的数据转成 `MessageSegment` 并通过新回调传给 `ConversationViewModel`。

---

## 7. ConversationViewModel 改动点

### 7.1 onSegment 回调

`BaseChatProvider.sendStreaming()` 新增一个 `onSegment: ((MessageSegment) -> Void)?` 回调：

```swift
// 工具调用完成时触发（不是实时流式，而是一次性）
onSegment: { [weak self] segment in
    guard let self else { return }
    assistantNode.segments.append(segment)
}
```

### 7.2 MessageNode.segments

检查 `MessageNode` 是否有 `segments` 字段：

```swift
// 如果没有，需要新增
@Model final class MessageNode {
    // ...
    var segments: [MessageSegment] = []   // 结构化分段，如有则优先用于渲染
}
```

（粟粟的 ClaudeImporter 写入了 segments，但普通流式聊天可能只用 content 字符串，需要核实。）

---

## 8. 关键问题和决策点（等天奕确认）

### Q1：imprint-memory 的 SSE endpoint 鉴权方式？

`https://imprint.amberrib.com/sse` 需要什么鉴权？Bearer token？还是公开？  
影响 `MCPServerConfig.authToken` 字段的使用。

### Q2：tool 名称 namespace

Anthropic mcp_servers 模式下，工具名称会带 server name 前缀：  
`imprint-memory__memory_remember`  
`ToolCallCardView` 的 `name` 字段直接展示这个，视觉上可能不好看。  
要不要在渲染时把 `__` 前的 server 名去掉，只显示 tool 名？

### Q3：streaming 中 tool_use 的用户体验

工具调用期间（`content_block_start(tool_use)` 到 `content_block_stop`），  
用户在 UI 上看到什么？  
- 选项 A：什么都不显示，等工具完成后突然出现一张卡片
- 选项 B：实时展示"⏳ 调用 memory_remember..."
- 粟粟的 ThinkingBlockView 是 block 结束后一次性展示的，ToolCallCard 跟进同样逻辑即可

**建议**：先用选项 A（和 thinking block 一致），Phase 3 再优化流式体验。

### Q4：是否检查 MessageNode.segments

需要确认流式聊天（非导入）路径下，`assistantNode.segments` 是否已经被渲染使用。  
如果 `MessageSegmentsView` 依赖 `MessageNode.segmentsJSON`（JSON 编码的 segments），  
需要在 `onComplete` 时把 `segments` 序列化进去。

---

## 9. 实施计划（供 Plan 阶段参考）

```
Step 1  新增 MCPServerConfig，APIProvider 加 mcpServers 字段，SamplingParams 加 mcpEnabled
Step 2  APISettingsView 加 MCP Servers 配置 UI（类似 extraHeaders 的列表）
Step 3  AnthropicProvider.sendStreaming() 注入 mcp_servers + beta header
Step 4  AnthropicProvider 新增 content_block_start/stop 解析 + tool segment 收集
Step 5  BaseChatProvider 新增 onSegment 回调，AnthropicProvider 在 block_stop 时触发
Step 6  ConversationViewModel 接收 onSegment，append 到 assistantNode.segments
Step 7  确认 MessageSegmentsView 渲染路径正确读取 segments
Step 8  端到端测试：发一条触发记忆工具的消息，验证 ToolCallCardView 出现
```

每步独立可测试。Step 1-2 数据模型+UI；Step 3 只改请求体；Step 4-6 改解析；Step 7 验证现有渲染。

---

## 附录：涉及文件速查

| 文件 | 改动 |
|---|---|
| `Models/APIProvider.swift` | 新增 `MCPServerConfig`，`APIProvider.mcpServers` |
| `Models/Preset.swift` | `SamplingParams.mcpEnabled` |
| `Services/ChatService.swift` | `AnthropicProvider` 请求构建 + SSE 解析 |
| `Services/PromptPostProcessor.swift` | 可选：`buildAnthropicBody()` 加 mcp_servers（预览用）|
| `ViewModels/ConversationViewModel.swift` | `onSegment` 回调处理 |
| `Views/APISettingsTab.swift` | MCP server 配置 UI |
| `Models/MessageSegment.swift` | **不需要改**，已有 toolUse/toolResult |
| `Views/MessageSegmentsView.swift` | **不需要改**，已有 ToolCallCardView |

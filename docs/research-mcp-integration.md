# Research: 在现有架构中接入 MCP 工具调用（imprint-memory 等）

> 日期：2026-05-25  
> 状态：研究阶段，待天奕确认后进入 Plan

---

## 1. 现有网络层架构速览

### 1.1 三层 Provider 体系

```
ConversationViewModel.sendMessage()
    └─ assemblePrompt()         ← PromptAssembler + MemoryStore + WorldBook 注入
    └─ ProviderRouter           ← 按 model.providerId 路由
           ├─ OpenAICompatibleProvider   ← /chat/completions SSE
           ├─ AnthropicProvider          ← /messages SSE（含 tool_use 事件，但目前未处理）
           └─ CCBridgeProvider           ← WebSocket → hub.ts → tmux → Claude Code
```

### 1.2 CCBridge 消息链（已有的本地 Claude 桥接）

```
iOS App                 hub.ts (Node)           Claude Code (tmux)
   │                       │                          │
   │──ws://127.0.0.1:7890/cc──>                       │
   │  {type:"send",          │                         │
   │   chat_id, content}     │                         │
   │                   <channel> tag via tmux.sendKeys  │
   │                         │─────────────────────────>│
   │                         │                    runs mcp-server.ts as MCP tool
   │                         │<──── ws://127.0.0.1:7890/mcp ────────────────────│
   │                         │     {type:"reply", chat_id, content}              │
   │<──{type:"reply",        │                          │
   │   chat_id, content}─────│                          │
```

mcp-server.ts 是一个标准 MCP server，暴露单个 `reply` 工具，让 Claude Code 回写消息到 iOS。

### 1.3 本地记忆系统（AUDN）

```
MemoryStore (protocol)
    └─ SwiftDataMemoryStore     ← 本地 SwiftData 存储
           ├─ listHot()         ← conversation 开始前注入 system prompt
           ├─ listHotAndWarm()  ← memory agent 使用
           └─ applyDecay()      ← 权重随时间衰减

MemoryExtractor                 ← conversation 结束后，独立 LLM call 提取记忆
MemoryInjector                  ← 把记忆格式化成 XML 注入 system prompt

注入位置：PromptSlot.memoryInjectionId → PromptAssembler.resolveSlotContent()
```

---

## 2. imprint-memory 是什么

imprint-memory 是一个 MCP server，提供跨会话、跨设备的持久记忆存储，核心工具集（典型）：

| 工具 | 说明 |
|------|------|
| `memory_add` | 存一条记忆（content, tags, category）|
| `memory_search` | 语义/关键词搜索记忆 |
| `memory_list` | 列出记忆（支持 profileId 过滤）|
| `memory_delete` | 删除指定记忆 |
| `memory_update` | 更新记忆内容 |

它运行在 Mac 本地（或云端），通过 stdio / SSE 与 Claude Code 通信。

---

## 3. 接入方案分析

### 方案 A：纯 Claude 侧（零改动 iOS）⭐ 推荐入门

**原理**：imprint-memory MCP 已在 Claude Code 的 `.claude/settings.json` 里配置。  
iOS 通过 CCBridge 发消息给 Claude Code，Claude 在处理时直接使用 imprint-memory 工具读写记忆。iOS 侧无感知，完全透明。

```
iOS ──(ccbridge)──> Claude Code ──uses──> imprint-memory MCP
                                 ──uses──> reply MCP (回写 iOS)
```

**优点**：
- 立刻可用，不写 iOS 代码
- Claude 可以自主决定何时读/写记忆（比规则系统更灵活）
- imprint 的记忆跨所有工具共享（CC Agent、其他 session）

**缺点**：
- 需要 Mac 在线（本地桥接方案的固有局限）
- iOS 看不到记忆列表（MemoryPanelView 显示的是 AUDN 本地记忆，不是 imprint 的）
- 对话开始时没有"预热注入"——imprint 读取发生在 Claude 处理请求时，而不是 system prompt 组装时

**适合场景**：Phase 2 早期快速验证，确认 imprint 记忆的有效性。

---

### 方案 B：Hub 扩展——工具调用代理 ⭐ 推荐中期

**原理**：扩展 hub.ts，新增 `/tools` WebSocket 路径。iOS 发送工具调用请求，hub 转发给已连接的 imprint-memory MCP server，把结果回传 iOS。

```
iOS ──ws://127.0.0.1:7890/tools──> hub.ts ──mcp stdio/sse──> imprint-memory
     {type:"call_tool",                    <── result ──────────────────────
      tool:"memory_search",
      args:{query:"..."}}
     <── {type:"tool_result", content}
```

**iOS 侧改动**：
1. `CCBridgeWebSocketClient` 新增 `callTool(name:args:) async throws -> [String: Any]` 方法
2. 新建 `ImprintMemoryStore: MemoryStore` 实现，内部调用 `CCBridgeWebSocketClient.callTool`
3. `ConversationViewModel.assemblePrompt()` 的 `MemoryStore` 切换为 `ImprintMemoryStore`（或并联两个 store）

**hub.ts 侧改动**：
1. 新增 MCP client（mcp-server.ts 反过来作为 client 连接 imprint-memory）
2. `/tools` 路径：接收 iOS 的 call_tool → 调 MCP → 把结果回写给 iOS

**优点**：
- iOS 可以在 `assemblePrompt()` 里拿到 imprint 记忆，注入 system prompt（和现有 AUDN 系统平级）
- MemoryPanelView 可以展示 imprint 记忆（通过 `ImprintMemoryStore.listAll()`）
- 两个记忆系统可以互补：AUDN 负责本地快速访问，imprint 负责持久化和跨设备

**缺点**：
- 需要 Mac 在线（同方案 A）
- hub.ts 变复杂（需要 MCP client 能力）
- 首次连接有延迟（WebSocket round-trip）

**适合场景**：Phase 2 正式接入，imprint 成为主记忆后端。

---

### 方案 C：Anthropic Tool Use API（直连 Claude API + 工具）

**原理**：直接使用 Anthropic API 的 tool use 功能。iOS 在请求体里声明 imprint-memory 工具 schema，Claude 返回 `tool_use` 事件，iOS 捕获后调用实际的 MCP server（通过 hub 或 HTTP proxy），把 `tool_result` 回传给 Claude，Claude 继续生成文本。

```
iOS ──POST /messages──> Claude API
    {tools: [{name:"memory_search",...}], messages: [...]}
    <── tool_use event: {id, name:"memory_search", input:{query:"..."}}
iOS ──调用 hub 转发 MCP──> imprint-memory
    <── tool result
iOS ──POST /messages──> Claude API (追加 tool_result)
    <── text response
```

**iOS 侧改动**：
1. `AnthropicProvider` 处理 `content_block_start(type="tool_use")` 事件（目前未处理）
2. `ProviderRouter` 在 `.anthropic` 路径中，把工具定义注入请求体
3. `ConversationViewModel` 实现工具调用的 turn loop（捕获 tool_use → 执行 → 回传 tool_result）
4. 中间需要一个"工具执行器"层调用 hub

**优点**：
- 纯 API 方案，不依赖本地 Mac（imprint-memory server 可以是云端的）
- Claude 自主决定何时使用工具、用几次（agentic 能力）
- 符合 Anthropic 官方推荐的工具调用方式

**缺点**：
- iOS 代码改动最大（turn loop、工具调用中间层）
- `AnthropicProvider.sendStreaming()` 需要改成可暂停/继续的多轮流式
- 工具执行延迟会打断流式体验（用户看到"思考中..."）
- API 成本翻倍（每次工具调用都是一轮新请求）

**适合场景**：Phase 2-3，目标是真正的 agentic 能力（Claude 自主决定记忆读写策略）。

---

### 方案 D：iOS 原生 MCP 客户端（未来）

理论上 iOS 可以通过 URLSession WebSocket + JSON-RPC 直接与 imprint-memory MCP server（SSE transport）通信，无需 hub 中转。但 MCP 的 stdio transport 在 iOS 上不可行，需要 imprint-memory 支持 SSE/WebSocket transport。目前不建议，等生态成熟。

---

## 4. 两个记忆系统的互补关系

| | AUDN（现有） | imprint-memory（新接入） |
|---|---|---|
| 存储位置 | 本地 SwiftData | 外部（Mac/云端） |
| 提取方式 | 对话结束后 LLM 提取 | Claude 主动调用工具存储 |
| 检索方式 | 权重+时间衰减排序 | 语义搜索 |
| 注入时机 | system prompt 组装时 | Claude 按需读取（或 B 方案预热） |
| 跨设备 | ❌ | ✅ |
| 离线可用 | ✅ | ❌（需 Mac/网络） |

**建议策略**：两者并联，不互相替代。
- AUDN 继续负责离线场景和快速本地访问
- imprint 负责持久化、语义检索、跨设备同步
- 注入时：`MemoryInjector` 合并两个 store 的结果，各自限 token budget

---

## 5. 推荐实施路径

```
Phase 2.1  方案 A（零改动）    → 验证 imprint 记忆质量，Claude 侧透明使用
Phase 2.2  方案 B（hub 扩展）  → iOS 能在 system prompt 预热注入 imprint 记忆
                                 → MemoryPanelView 展示 imprint 记忆列表
Phase 2.3+  方案 C（可选）     → 需要 agentic 能力时再做，成本大
```

---

## 6. 关键代码接口（方案 B 的修改点）

### 6.1 hub.ts 新增 `/tools` 路由（示意）

```typescript
} else if (req.url === "/tools") {
  // iOS 连接，转发工具调用给 MCP
  ws.on("message", async (raw) => {
    const req = JSON.parse(raw.toString())  // {call_id, tool, args}
    const result = await mcpClient.callTool(req.tool, req.args)
    ws.send(JSON.stringify({type: "tool_result", call_id: req.call_id, content: result}))
  })
}
```

### 6.2 iOS 新增 ImprintMemoryStore（示意）

```swift
struct ImprintMemoryStore: MemoryStore {
    func listHot(profileId: String, context: ModelContext) -> [Memory] {
        // 同步包装异步工具调用（在 assemblePrompt() 的 async 上下文中）
        // callTool("memory_list", args: {profileId, limit: 20, tier: "hot"})
        // → 解析返回的 JSON → 转换为 [Memory]
    }

    func add(content: String, ...) async throws {
        // callTool("memory_add", args: {content, category, keywords, profileId})
    }
}
```

### 6.3 ConversationViewModel 并联两个 store（示意）

```swift
// 现在
let memories = memoryStore.listHot(profileId: profile.id, context: context)

// 方案 B 后
let localMemories = localMemoryStore.listHot(profileId: profile.id, context: context)
let imprintMemories = imprintStore.listHot(profileId: profile.id, context: context)
let memories = (localMemories + imprintMemories)
    .sorted { DecayEngine.effectiveWeight($0) > DecayEngine.effectiveWeight($1) }
    .prefix(MemoryInjector.maxItems)
```

---

## 7. 下一步

- [ ] 天奕确认：Phase 2.1 先用方案 A 跑一段时间，观察记忆质量
- [ ] 研究 imprint-memory 的具体工具 schema（读它的 MCP manifest）
- [ ] 决策：imprint 记忆注入放 system prompt 还是作为 assistant 前置消息
- [ ] 确认 hub.ts 是否值得扩展（还是 Phase 2 先用 AUDN，Phase 3 再做 imprint 深度接入）

# 任务：MetaTools 元工具（71 个工具目录化，紧急）

> 参考：`/root/projects/SusuPalace` origin/master → `MetaTools.swift`
> 紧急程度：高（71 个工具全量注入 schema 每轮浪费几千 token）
> 原理：MCP 工具不再全量内联 schema，改成 3 个元工具目录化访问

---

## 原理

改前（71 个工具全量注入）：
```
system prompt + 71 个工具 schema（每个约 200 token）= ~14000 token 浪费
AI 大部分时候只用其中 2-3 个
```

改后（MetaTools 目录化）：
```
system prompt + 3 个元工具 + fs_/search 等核心工具（~10 个）= ~2000 token
AI 需要时：tool_search "天气" → tool_inspect ["get_weather"] → tool_invoke
```

核心工具（fs_*、search_web、browse_url 等）仍直接内联，只有 MCP 工具走目录化。

---

## 步骤

### 1. 复制 + 适配 MetaTools.swift

```bash
cp /root/projects/SusuPalace/MemoryPalace/Services/MetaTools.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/
```

适配我们的类型（粟粟用 `MCPResolvedTool` + `ToolDefinition`，我们用 `MCPToolDescriptor`）：

全局替换：
- `MCPResolvedTool` → `MCPToolDescriptor`
- `t.tool.name` → `t.name`
- `t.tool.description` → `t.description`
- `t.serverName` → `t.server`
- `namespace(_ t:)` 里的 `t.serverName` → `t.server`

`inspect` 函数里的 `t.tool.schemaAny()` 改成：
```swift
let schemaText = t.inputSchemaJSON  // 我们的已经是 JSON 字符串
```

`definitions` 属性用到 `ToolDefinition`，我们没有这个类型。改成返回 `[MCPToolDescriptor]`：
```swift
static var toolDescriptors: [MCPToolDescriptor] {
    specs.map { (name, desc, props, req) in
        let schema: [String: Any] = ["type": "object", "properties": props, "required": req]
        let schemaJSON = (try? JSONSerialization.data(withJSONObject: schema))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return MCPToolDescriptor(server: "meta", name: name, description: desc, inputSchemaJSON: schemaJSON)
    }
}
```

### 2. ProviderRouter 切换目录化模式

文件：`MemoryPalace/Services/ProviderRouter.swift`

在 `sendStreaming` 函数里，`sanitizedBridgeTools()` 调用之后，加目录化切换：

```swift
let allMCPTools = sanitizedBridgeTools()

// 核心工具阈值：MCP 工具超过 15 个时启用目录化
let META_THRESHOLD = 15

if allMCPTools.count > META_THRESHOLD {
    // 目录化模式：MCP 工具不注入 schema，改成 3 个元工具
    let metaDescriptors = MetaTools.toolDescriptors
    
    // provider 只拿元工具（+ 搜索等核心工具在别处注入）
    openAIProvider.bridgeTools = metaDescriptors
    // 或 anthropicProvider.bridgeTools = metaDescriptors
    
    // 完整目录存起来给 ToolCallLoop 用
    openAIProvider.metaToolCatalog = allMCPTools
    // 或 anthropicProvider.metaToolCatalog = allMCPTools
} else {
    // 工具少时照旧全量注入
    openAIProvider.bridgeTools = allMCPTools
    // 或 anthropicProvider.bridgeTools = allMCPTools
}
```

**注意**：OpenAI 和 Anthropic 两条路径都要改（找到对应的 `bridgeTools =` 赋值处）。

### 3. Provider 加 metaToolCatalog 属性

文件：`MemoryPalace/Services/ChatService.swift`（BaseChatProvider）

```swift
/// 目录化模式：完整 MCP 工具列表（MetaTools 启用时由 ProviderRouter 填入）
var metaToolCatalog: [MCPToolDescriptor] = []
```

### 4. ToolCallLoop 处理元工具调用

文件：`MemoryPalace/Services/ToolCallLoop.swift`

在 `execute` 函数的 `for call in calls` 循环里，**联网搜索拦截之后、MCP 查找之前**加：

```swift
// ── 元工具：目录化 MCP 访问 ──
if MetaTools.names.contains(call.name) {
    let catalog = bridgeTools.isEmpty ? [] : bridgeTools  // fallback
    // 优先用 metaToolCatalog（从 provider 传入）
    // 注意：execute 函数需要新增 metaToolCatalog 参数
    let result: String
    switch call.name {
    case MetaTools.searchName:
        let query = call.arguments["query"] as? String ?? ""
        result = MetaTools.search(query: query, catalog: metaToolCatalog)
    case MetaTools.inspectName:
        let names = call.arguments["names"] as? [String] ?? []
        result = MetaTools.inspect(names: names, catalog: metaToolCatalog)
    case MetaTools.invokeName:
        let toolName = call.arguments["name"] as? String ?? ""
        let toolArgs = call.arguments["arguments"] as? [String: Any] ?? [:]
        if let resolved = MetaTools.resolve(toolName, catalog: metaToolCatalog) {
            // 找到真实工具 → 转发给 MCP
            guard let server = metaToolCatalog.first(where: { $0.name == resolved })?.server else {
                result = "工具 '\(resolved)' 找到但无法定位服务端"
                outcomes.append(ToolOutcome(id: call.id, name: call.name, text: result, isError: true))
                continue
            }
            do {
                let blocks = try await MCPService.shared.callTool(server: server, tool: resolved, arguments: toolArgs)
                result = MCPContentBlock.flatten(blocks)
            } catch {
                result = "调用 \(resolved) 失败: \(error.localizedDescription)"
            }
        } else {
            result = "工具 '\(toolName)' 未找到。用 tool_search 搜索可用工具。"
        }
    default:
        result = ""
    }
    outcomes.append(ToolOutcome(id: call.id, name: call.name, text: result, isError: false))
    continue
}
```

### 5. execute 函数签名加 metaToolCatalog 参数

```swift
static func execute(
    _ calls: [ToolCall],
    bridgeTools: [MCPToolDescriptor],
    metaToolCatalog: [MCPToolDescriptor] = []  // ← 新增
) async -> [ToolOutcome] {
```

所有调用 `execute` 的地方补上这个参数：
```bash
grep -rn "ToolCallLoop.execute" MemoryPalace/ --include="*.swift"
```

从 provider 拿 `metaToolCatalog` 传进去。

---

## 验证

1. 编译通过
2. 打开 MCP 工具（应该 71 个），发消息 → AI 收到的 tools 列表只有 ~13 个（3 元工具 + fs_ + search 等核心工具），而不是 71 个
3. 让 AI "帮我查看现在几点" → AI 调 `tool_search "时间"` → 返回 `current_time` → AI 调 `tool_invoke current_time {}` → 返回时间
4. Token 统计里 input token 应该明显下降（少了 ~12000 token 的工具 schema）

---

## 注意

1. **不要碰 CLAUDE.md**
2. 核心工具（fs_*、search_web、browse_url、inner_voice 等本地注册的）**不走目录化**，仍然直接内联。只有 MCP 工具（来自 MCPToolCache.shared.tools）走目录化
3. 阈值 `META_THRESHOLD = 15` 可调，15 以下全量注入不影响体验
4. commit message：`feat(metatools): MCP 工具目录化 — 71 个工具降到 3 个元工具`

# 任务：MetaTools 元工具 + 记忆星图

> 参考：`/root/projects/SusuPalace` origin/master
> 两个任务互相独立，可乱序做

---

## 任务一：MetaTools 元工具（省 token 神器）

### 背景
我们有 33 个 MCP 工具，全量注入 schema 占大量 token。MetaTools 把它们收成 3 个元工具：
- `tool_search` — 按关键词搜工具目录
- `tool_inspect` — 查看某个工具的完整参数
- `tool_invoke` — 调用工具

AI 不需要一次看到 33 个工具的完整 schema，而是先搜 → 看参数 → 调用。

### 步骤

#### 1. 复制 MetaTools.swift

```bash
cp /root/projects/SusuPalace/MemoryPalace/Services/MetaTools.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/
```

#### 2. 适配类型

粟粟用 `MCPResolvedTool`，我们用 `MCPToolDescriptor`。需要把所有 `MCPResolvedTool` 改成 `MCPToolDescriptor`：

```bash
sed -i 's/MCPResolvedTool/MCPToolDescriptor/g' /root/projects/BunnyPalace/MemoryPalace/Services/MetaTools.swift
```

然后修几个字段名差异：
- 粟粟的 `t.tool.name` → 我们的 `t.name`
- 粟粟的 `t.tool.description` → 我们的 `t.description`
- 粟粟的 `t.serverName` → 我们的 `t.server`
- 粟粟的 `t.tool.schemaAny()` → 我们的 `t.inputSchemaJSON`（JSON 字符串，不需要 schemaAny）
- `namespace(_ t:)` 改成 `"mcp:\(t.server)"`

#### 3. ProviderRouter 里切换模式

在 `ProviderRouter.swift` 的 `sendStreaming` 里，当工具超过阈值时用 MetaTools 替代全量注入：

```swift
// bridgeTools 赋值之后加：
let mcpToolCount = openAIProvider.bridgeTools.count  // 或 anthropicProvider
if mcpToolCount > 15 {
    // 工具太多，换 MetaTools 目录化模式
    let catalog = openAIProvider.bridgeTools
    openAIProvider.bridgeTools = []  // 清空 MCP 工具
    // 加 3 个元工具
    for spec in MetaTools.toolDefinitions() {
        openAIProvider.bridgeTools.append(spec)
    }
    // 把 catalog 存起来给 ToolCallLoop 用
    openAIProvider.metaToolCatalog = catalog
}
```

注意：需要在 `OpenAICompatibleProvider` / `AnthropicProvider` 上加一个 `var metaToolCatalog: [MCPToolDescriptor] = []` 属性。

#### 4. ToolCallLoop 处理元工具调用

在 `ToolCallLoop.swift` 的 execute 函数里，搜索工具之前加：

```swift
// 元工具处理
if MetaTools.names.contains(call.name) {
    let catalog = provider.metaToolCatalog  // 从 provider 拿完整目录
    let result: String
    switch call.name {
    case MetaTools.searchName:
        let query = (call.arguments["query"] as? String) ?? ""
        result = MetaTools.search(query: query, catalog: catalog)
    case MetaTools.inspectName:
        let names = (call.arguments["names"] as? [String]) ?? []
        result = MetaTools.inspect(names: names, catalog: catalog)
    case MetaTools.invokeName:
        let toolName = (call.arguments["name"] as? String) ?? ""
        let toolArgs = (call.arguments["arguments"] as? [String: Any]) ?? [:]
        // 解析真实工具名，转发给 MCP
        if let resolved = MetaTools.resolve(toolName, catalog: catalog) {
            // 构造一个新的 tool call 转发给 MCP
            // ... 按现有 MCP 调用逻辑处理
            result = "（调用 \(resolved) 中...）"
        } else {
            result = "工具 '\(toolName)' 未找到。用 tool_search 查询。"
        }
    default: result = ""
    }
    outcomes.append(ToolOutcome(id: call.id, name: call.name, text: result, isError: false))
    continue
}
```

#### 5. MetaTools.toolDefinitions() 函数

需要在 MetaTools 里加一个函数返回 MCPToolDescriptor 格式的 3 个元工具定义。参考粟粟的 specs 数组，转成我们的格式。

### 验证
1. 编译通过
2. MCP 工具 > 15 个时，AI 收到的 tools 列表只有 3 个元工具 + fs_ 等核心工具
3. 让 AI "用搜索工具帮我查天气" → AI 先调 tool_search → 找到 search_web → 调 tool_invoke

---

## 任务二：记忆星图（超酷可视化）

### 背景
Obsidian 式力导向图：每条记忆 = 一个节点，关联记忆之间连线。热记忆深薄荷色，冷记忆暗灰，选中一个节点高亮它的邻域。

### 步骤

#### 1. 添加 Grape SPM 依赖

在 `project.yml` 的 `packages:` 加：
```yaml
  Grape:
    url: https://github.com/swiftgraphs/Grape
    from: "1.1.0"
```

在 targets 的 dependencies 加：
```yaml
      - package: Grape
```

#### 2. 复制 MemoryGraphView.swift

```bash
cp /root/projects/SusuPalace/MemoryPalace/Views/MemoryGraphView.swift \
   /root/projects/BunnyPalace/MemoryPalace/Views/
```

#### 3. 适配 DecayEngine.tier

粟粟用 `DecayEngine.tier(m)` 返回 `.hot/.warm/.cold`。查看我们有没有：
```bash
grep -rn "DecayEngine\|func tier\|enum.*Tier" /root/projects/BunnyPalace/MemoryPalace/ --include="*.swift" | head -5
```

如果我们没有 `DecayEngine.tier`，用简化版替代：
```swift
private func nodeTier(_ m: Memory) -> Int {
    // 简化：按 accessCount 分三档
    if m.accessCount >= 5 { return 2 }  // hot
    if m.accessCount >= 2 { return 1 }  // warm
    return 0  // cold
}
```

然后把 `nodeColor` 里的 `DecayEngine.tier(m)` 换成 `nodeTier(m)`，把 case 改成 Int 匹配。

#### 4. 适配 Memory.relatedIds

粟粟的 Memory 有 `relatedIds: [UUID]` 字段（记忆之间的关联）。查看我们有没有：
```bash
grep -n "relatedIds" /root/projects/BunnyPalace/MemoryPalace/Models/Memory.swift
```

如果没有，有两个选择：
- **方案 A**：Memory 模型加 `var relatedIds: [UUID] = []` 字段（需要关联算法填充）
- **方案 B**：用 embedding 向量相似度动态计算邻居（>0.7 的连线），不存字段：
```swift
private var edges: [Edge] {
    var out: [Edge] = []
    for i in 0..<memories.count {
        for j in (i+1)..<memories.count {
            if let va = memories[i].embeddingData, let vb = memories[j].embeddingData {
                let sim = cosineSimilarity(va, vb)
                if sim > 0.7 {
                    out.append(Edge(a: memories[i].id, b: memories[j].id))
                }
            }
        }
    }
    return out
}
```
方案 B 更简单但记忆多时 O(n²) 慢，可以加 fetchLimit=100 只取最近的记忆。

#### 5. 接入 UI

在记忆设置页（`MemorySettingsTab.swift`）或 Page 2 记忆面板加入口：

```swift
NavigationLink("记忆星图") {
    MemoryGraphView(memories: allMemories)
        .navigationTitle("记忆星图")
}
```

或者在记忆面板顶部加 tab 切换「列表 | 星图」。

#### 6. xcodegen 重新生成

```bash
cd /root/projects/BunnyPalace && xcodegen generate
```
因为加了新 SPM 包。

### 验证
1. 编译通过（Grape 下载成功）
2. 记忆面板/设置页有"记忆星图"入口
3. 点进去看到力导向图，节点 = 记忆
4. 热记忆深绿色，冷记忆灰色
5. 点击一个节点 → 高亮邻域 → 底部显示内容卡
6. 捏合缩放、拖拽节点正常

---

## 通用红线

1. **不要碰 CLAUDE.md**
2. 两个任务互相独立
3. commit message：`feat(metatools): ...` / `feat(memory-graph): ...`
4. 记忆星图加了新 SPM 包（Grape），CI 需要能下载 github.com

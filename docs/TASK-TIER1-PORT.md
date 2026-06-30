# 第一梯队搬运任务：从粟粟搬代码到 BunnyPalace

> 来源仓库：`/root/projects/SusuPalace`（需先 `cd /root/projects/SusuPalace && git checkout origin/master`）
> 目标仓库：`/root/projects/BunnyPalace`
> 原则：**能直接复制的复制，需要改的标注改动原因，不动已有功能**

---

## 施工顺序

**先做任务三**（最小）→ **任务二**（缓存优化）→ **任务一**（联网搜索，最大）。
每个任务完成后单独 commit + push，等 CI 绿再做下一个。

---

## 任务一：联网搜索（最大，最重要）

### 目标
让 Caelum 能联网搜索 + 读网页。用户问实时信息时，AI 先搜再答。

### 从粟粟复制的文件

先确保粟粟代码是最新的：
```bash
cd /root/projects/SusuPalace && git checkout origin/master
```

整个目录复制：
```bash
mkdir -p /root/projects/BunnyPalace/MemoryPalace/Services/Search/Providers
mkdir -p /root/projects/BunnyPalace/MemoryPalace/Services/Search/InternalBrowser

# 核心文件
cp MemoryPalace/Services/Search/WebSearchService.swift \
   MemoryPalace/Services/Search/WebSearchToolService.swift \
   MemoryPalace/Services/Search/WebSearchSettings.swift \
   MemoryPalace/Services/Search/WebSearchCitation.swift \
   MemoryPalace/Services/Search/WebSearchSource.swift \
   MemoryPalace/Services/Search/WebSearchServiceOptions.swift \
   MemoryPalace/Services/Search/WebSearchProbe.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/Search/

# InternalBrowser（browse_url 工具）
cp MemoryPalace/Services/Search/InternalBrowser/InternalBrowser.swift \
   MemoryPalace/Services/Search/InternalBrowser/BrowseURLTool.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/Search/InternalBrowser/

# Providers（先只搬免费的两个，不需要 API key）
cp MemoryPalace/Services/Search/Providers/DuckDuckGoProvider.swift \
   MemoryPalace/Services/Search/Providers/BingLocalProvider.swift \
   /root/projects/BunnyPalace/MemoryPalace/Services/Search/Providers/
```

### 接线改动

#### 1. project.yml
确认 sources 包含新目录。BunnyPalace 用 xcodegen，通常 sources 是 glob：
```bash
grep -n "sources" /root/projects/BunnyPalace/project.yml
```
如果 sources 用 `MemoryPalace/**`，不用改。

#### 2. ToolCallLoop.swift — 注册搜索工具

文件：`MemoryPalace/Services/ToolCallLoop.swift`
在 `execute` 函数的 `for call in calls` 循环开头，**在 MCP 查找之前**加本地工具拦截：

```swift
// ── 本地工具：联网搜索 ──
if call.name == WebSearchToolService.toolName {
    let result = await WebSearchToolService.execute(inputJSON: call.argumentsJSON)
    outcomes.append(ToolOutcome(id: call.id, name: call.name,
                                text: result.text, isError: result.isError))
    continue
}
if call.name == BrowseURLTool.toolName {
    let result = await BrowseURLTool.execute(inputJSON: call.argumentsJSON)
    outcomes.append(ToolOutcome(id: call.id, name: call.name,
                                text: result.text, isError: result.isError))
    continue
}
```

#### 3. ConversationViewModel+Chat.swift — 注入搜索工具定义

找构建 tools 数组的地方（搜 `anthropicTools` 或 `openAITools`），追加搜索工具：

```swift
if WebSearchSettings.shared.searchEnabled {
    if providerRouter.currentProviderType == .anthropic {
        // Anthropic 直连用 server tool（Claude 后端自己搜索）
        tools.append(WebSearchToolService.anthropicServerTool())
    } else {
        // 其他模型走 client function
        tools.append(WebSearchToolService.openAITool())
        tools.append(BrowseURLTool.openAITool())
    }
}
```

搜索工具定义放 MCP 工具之后，保证 prompt cache 前缀稳定。

#### 4. ChatService.swift — 解析 web_search_tool_result

在 `AnthropicProvider` 流式解析的 `content_block_start` 事件里，已有 `tool_use` 判断之后加：

```swift
} else if type == "web_search_tool_result",
          let content = cb["content"] as? [[String: Any]] {
    for item in content {
        if item["type"] as? String == "web_search_result",
           let url = item["url"] as? String,
           let title = item["title"] as? String {
            print("[WebSearch] source: \(title) - \(url)")
        }
    }
}
```

#### 5. PromptAssembler.swift — 搜索 system prompt

搜索开启 + 非 Anthropic 模型时，追加搜索提示到 volatile 层：

```swift
if WebSearchSettings.shared.searchEnabled {
    // Anthropic server tool 不需要额外提示，其他模型需要教它用工具
    // 追加到 volatile 层不影响缓存
    let searchPrompt = WebSearchToolService.systemPrompt(assistantName: profile.aiName ?? "Caelum")
    // 加到 system 的 volatile 部分
}
```

#### 6. 设置页入口

在 `SettingsView.swift` 加搜索设置：

```swift
Section("联网搜索") {
    Toggle("启用搜索", isOn: Binding(
        get: { WebSearchSettings.shared.searchEnabled },
        set: { WebSearchSettings.shared.searchEnabled = $0 }
    ))
    if WebSearchSettings.shared.searchEnabled {
        Text("搜索引擎：DuckDuckGo").font(.caption).foregroundColor(.secondary)
    }
}
```

#### 7. WebSearchSettings 默认 provider

确保首次启动有默认 provider。在 `WebSearchSettings.swift` 的 `load()` 末尾：

```swift
if providers.isEmpty {
    let ddg = WebSearchServiceOptions.duckduckgo(DuckDuckGoOptions())
    providers = [ddg]
    selectedId = ddg.id
    save()
}
```

### 编译适配注意
- 粟粟代码可能引用 `KeychainStore`。免费 provider 不需要 key，注释掉 Keychain 代码
- `InternalBrowser.swift` 用 WKWebView，iOS 支持没问题
- 遇到缺少类型定义，先看粟粟仓库有没有对应文件
- macOS 专用代码（`#if os(macOS)`）删掉或跳过

### 验证
1. `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS build` 通过
2. 设置页能看到"联网搜索"开关
3. 开关打开后发"今天天气怎么样" → AI 调 search_web 工具
4. 返回搜索结果 → AI 基于结果回答

---

## 任务二：缓存 per-block 挂标优化

### 目标
易变内容下沉，不污染 system prompt 缓存前缀。

### 改动

#### 1. Preset 加 cacheFriendly 字段

在 `Preset` 的 `Sampling`/`SamplingParams` 结构体里加：
```swift
var cacheFriendly: Bool = false
```

#### 2. PromptAssembler.swift — cacheFriendly 下沉

我们已有 `stableCore`/`semiStable` 分层。加 cacheFriendly 逻辑：

当 `preset.sampling.cacheFriendly == true` 时：
- 记忆命中内容、世界书关键词命中条目、时间/日期/健康宏展开 → 收集到 `volatileParts: [String]`
- 拼成一条 `role: "user"` 消息：`[动态上下文｜仅供参考，不要复述]\n` + 内容
- 插入消息数组倒数第二位（用户当前消息之前）
- system prompt 里只留稳定内容

参考：
```bash
cd /root/projects/SusuPalace && git show origin/master:MemoryPalace/Services/PromptAssembler.swift | grep -B5 -A20 "cacheFriendly"
```

#### 3. OpenAICompatibleProvider — OR per-block 挂标

当 `cacheFriendly && baseURL 含 openrouter && model 含 claude` 时：
1. system 消息 content 改 `[{"type":"text","text":"...","cache_control":{"type":"ephemeral"}}]`
2. 最后一条 assistant 消息同样加 `cache_control`
3. 不给动态上下文伪 user 消息挂标

#### 4. OR session-id 钉上游

cacheFriendly 且 OpenRouter 时加 header：
- `x-session-id: {对话UUID}` — 钉住上游 provider
- body 加 `"provider": {"order": ["Anthropic"]}` — 指定官方上游

#### 5. 设置页开关

Preset 编辑页的采样参数区加 `cacheFriendly` Toggle。

### 验证
1. 编译通过
2. 打开 cacheFriendly 发几轮对话
3. TokenStatsView 缓存命中 > 0

---

## 任务三：缓存可见性（气泡 usage footer）— 最先做

### 目标
每条 AI 回复气泡底部显示 token 用量和缓存命中。

### 改动

#### 1. MessageNode 加 usage 字段

找到 MessageNode 的 @Model 定义（可能在 `Conversation.swift`），加：

```swift
@Attribute var usageInputTokens: Int?
@Attribute var usageCacheReadTokens: Int?
@Attribute var usageCacheCreationTokens: Int?
@Attribute var usageOutputTokens: Int?
```

SwiftData @Model 加可选字段安全，旧数据自动 nil，不需要 migration。

#### 2. 流式结束时写 usage

在 `ConversationViewModel+Chat.swift`，AI 回复保存 MessageNode 的地方，写入 usage：

```swift
if let usage = providerRouter.lastUsage {
    node.usageInputTokens = usage.inputTokens
    node.usageCacheReadTokens = usage.cacheReadInputTokens
    node.usageCacheCreationTokens = usage.cacheCreationInputTokens
    node.usageOutputTokens = usage.outputTokens
}
```

先确认 `ProviderRouter` 或 `ChatService` 暴露了 lastUsage。我们的 `AnthropicProvider` 已经解析 `cache_read_input_tokens`，数据应该有。搜索 `cacheReadInputTokens` 看它存在哪。

#### 3. 气泡底部显示

在 `CardFlowView.swift` 的 assistant 消息渲染里，底部加：

```swift
if let input = node.usageInputTokens, input > 0 {
    HStack(spacing: 4) {
        let cacheRead = node.usageCacheReadTokens ?? 0
        let total = input + (node.usageOutputTokens ?? 0)
        Text("\(total)t")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        if cacheRead > 0 {
            let pct = Int(Double(cacheRead) / Double(input) * 100)
            Text("缓存\(pct)%")
                .font(.system(size: 10))
                .foregroundColor(.green)
        }
    }
    .padding(.top, 2)
}
```

### 验证
1. 编译通过
2. 发消息 → AI 回复气泡底部出现 token 数
3. Anthropic 模型应能看到绿色缓存百分比
4. 历史消息（无 usage）不显示

---

## 通用红线

1. **不要碰 CLAUDE.md**
2. **不要改 Gateway 代码**（三个任务全在 App 端）
3. **不要删 .bak 文件**
4. 编译报错先看是不是缺粟粟的类型定义，有就一起复制
5. macOS 条件编译块删掉或跳过，我们只要 iOS
6. commit message：`feat(search): ...` / `feat(cache): ...` / `feat(usage): ...`

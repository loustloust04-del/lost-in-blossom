# Plan: 五 Tab Prompt Pipeline — 编辑(3) + 组装预览 + 最终请求

## 目标

把 SettingsView 的 Prompt 区域从 3 个编辑模式 + 折叠预览 → 5 个 Tab：
- Tab 1-3：简单/插槽/JSON（已完成，不动）
- Tab 4：组装预览（只读，PromptAssembler 输出，后处理前）
- Tab 5：最终请求（只读，经过后处理 + provider 适配的真实 request body JSON）

同时实现第3层后处理管线（PostProcessor），让 Tab 5 有东西显示。

## 现状分析

### 当前代码位置

| 组件 | 文件 | 行号 | 说明 |
|------|------|------|------|
| 模式切换 Picker | SettingsView.swift | 941-947 | `$personaEditMode`，"简单"/"插槽"/"原始" 三选一 |
| 模式内容 switch | SettingsView.swift | 958-965 | "simple"/"slots"/"raw" |
| 折叠预览 | SettingsView.swift | 968-975 | `DisclosureGroup("实时预览")` → `personaPromptPreview()` |
| personaPromptPreview | SettingsView.swift | 1481-1502 | 调 `PromptAssembler.preview()`，monospaced 文本展示 |
| PromptAssembler.assemble | PromptAssembler.swift | 15-85 | 返回 `(systemPrompt: String?, messages: [(role, content)])` |
| PromptAssembler.preview | PromptAssembler.swift | 88-116 | 返回格式化 String（═══ SYSTEM ═══ 等标签） |
| OpenAI request 构建 | ChatService.swift | 158-209 | system 加到 messages[0]，stream/sampling 参数 |
| Anthropic request 构建 | ChatService.swift | 326-379 | system 作为顶层字段，messages 只有 user/assistant |
| Provider 类型 | APIProvider.swift | 5-8 | `.openaiCompatible` / `.anthropic` |
| 发送调用链 | ConversationViewModel.swift | 596-616 | `assemblePrompt()` → router.sendStreaming() |
| SamplingParams | Preset.swift | 31-48 | squashSystemMessages / continuePrefill 已定义，未接入 |

### 缺失的

1. **PostProcessor**：不存在。PromptAssembler 输出直接传给 ChatService，中间没有后处理
2. **provider 适配逻辑**：散在 ChatService 的 OpenAI/Anthropic 两个类里，不可复用
3. **request body 预览**：无法在设置页看到最终发给 AI 的 JSON
4. **squash/prefill**：参数存了但没代码执行

## 架构决策

### PostProcessor 的位置

```
之前：
  PromptAssembler.assemble() → (systemPrompt, messages)
  → ChatService 各 provider 自己拼 body → 发送

之后：
  PromptAssembler.assemble() → (systemPrompt, messages)     ← Tab 4 展示这个
  → PostProcessor.process() → ProcessedPrompt                ← 新增
  → RequestBuilder.build() → RequestBody (JSON dict)         ← Tab 5 展示这个
  → ChatService 直接序列化发送
```

### 新增类型

```swift
// PostProcessor 的输出
struct ProcessedPrompt {
    var systemPrompt: String?          // OpenAI: nil (合进 messages)
    var systemBlocks: [[String: Any]]? // Anthropic: [{type:"text", text:"..."}]
    var messages: [(role: String, content: String)]
    var providerType: ProviderType     // 用了哪种 provider 适配
    var transforms: [String]           // 经历了哪些变换 (供 UI 展示)
}

// 最终 request body
struct RequestPreview {
    var body: [String: Any]            // 完整 request body (可序列化为 JSON)
    var providerType: ProviderType
    var tokenEstimate: Int             // 粗略 token 估算
}
```

### 不改的

- Tab 1-3（简单/插槽/JSON）— 不动
- PromptAssembler — 不动（第2层）
- ChatService 的 OpenAI/Anthropic 实际网络调用 — 暂不重构（先让预览能用，后续再统一）

## 具体改动

### Step 1: 新建 `PromptPostProcessor.swift`

**文件**: `MemoryPalace/Services/PromptPostProcessor.swift`

```swift
import Foundation

enum PostProcessingMode: String, Codable, CaseIterable {
    case none = "none"        // 不处理
    case merge = "merge"      // 合并连续同 role
    case strict = "strict"    // 合并 + user first + 中途 system 降级
}

struct ProcessedPrompt {
    var systemPrompt: String?
    var messages: [(role: String, content: String)]
    var transforms: [String]  // 变换日志
}

struct RequestPreview {
    var body: [String: Any]
    var providerType: ProviderType
    var tokenEstimate: Int
}

struct PromptPostProcessor {
    
    /// 后处理：squash + post-processing mode + provider 适配
    static func process(
        systemPrompt: String?,
        messages: [(role: String, content: String)],
        sampling: SamplingParams,
        providerType: ProviderType
    ) -> ProcessedPrompt {
        var sys = systemPrompt
        var msgs = messages
        var transforms: [String] = []
        
        // 1. squash system messages
        if sampling.squashSystemMessages {
            (sys, msgs) = squashConsecutiveSystem(systemPrompt: sys, messages: msgs)
            transforms.append("squash: 合并连续 system 消息")
        }
        
        // 2. post-processing mode (merge/strict)
        let mode = PostProcessingMode(rawValue: sampling.postProcessingMode) ?? .none
        switch mode {
        case .merge:
            msgs = mergeConsecutiveSameRole(msgs)
            transforms.append("merge: 合并连续同 role 消息")
        case .strict:
            (sys, msgs) = strictProcess(systemPrompt: sys, messages: msgs)
            transforms.append("strict: user first + 中途 system 降级 + 合并")
        case .none:
            break
        }
        
        // 3. provider 适配
        switch providerType {
        case .anthropic:
            (sys, msgs) = adaptForAnthropic(systemPrompt: sys, messages: msgs)
            transforms.append("anthropic: system 抽到顶层，相邻同 role 合并")
        case .openaiCompatible:
            // OpenAI: system 留在 messages 里不用特殊处理
            break
        }
        
        return ProcessedPrompt(systemPrompt: sys, messages: msgs, transforms: transforms)
    }
    
    /// 构建最终 request body（用于预览，不实际发送）
    static func buildRequestPreview(
        processed: ProcessedPrompt,
        model: String,
        sampling: SamplingParams,
        providerType: ProviderType
    ) -> RequestPreview {
        // ... 按 provider 类型构建 JSON dict
    }
}
```

**包含函数**：
- `squashConsecutiveSystem()` — 合并连续 system 消息
- `mergeConsecutiveSameRole()` — 合并连续同 role 消息（`\n\n`）
- `strictProcess()` — 强制 user first + 中途 system 降级 + 合并
- `adaptForAnthropic()` — 开头连续 system 移到 systemPrompt，中途 system 改 user，相邻同 role 合并
- `buildRequestPreview()` — 按 provider 构建完整 request body dict
- `estimateTokens()` — 粗略估算 token 数（字符数/3.5）

### Step 2: SamplingParams 加 `postProcessingMode` 字段

**文件**: `Preset.swift`，SamplingParams 结构体

```swift
var postProcessingMode: String = "none"  // "none" | "merge" | "strict"
```

加在 `squashSystemMessages` 旁边。默认 "none"，不影响现有行为。

### Step 3: 5-Tab Picker 改造

**文件**: `SettingsView.swift`

**改动 1**：`personaEditMode` 的值域扩展

原来：`"simple"` | `"slots"` | `"raw"`
新增：`"assembly"` | `"request"`

**改动 2**：Picker 从 3 选项改为 5 选项（line 941-947）

```swift
Picker("", selection: $personaEditMode) {
    Text("简单").tag("simple")
    Text("插槽").tag("slots")
    Text("JSON").tag("raw")
    Text("组装").tag("assembly")
    Text("请求").tag("request")
}
.pickerStyle(.segmented)
.frame(width: 300)   // 加宽
```

**改动 3**：switch 加两个 case（line 958-965）

```swift
switch personaEditMode {
case "slots":
    personaSlotsMode(preset: preset, psm: psm)
case "raw":
    personaRawMode(preset: preset, psm: psm)
case "assembly":
    personaAssemblyPreview(preset: preset, profile: profile)    // 新
case "request":
    personaRequestPreview(preset: preset, profile: profile)     // 新
default:
    personaSimpleMode(preset: preset, psm: psm)
}
```

**改动 4**：删除折叠预览（line 968-975）

`DisclosureGroup("实时预览")` 整块删掉 — 功能已被 Tab 4 替代。

### Step 4: Tab 4 — 组装预览视图

**文件**: `SettingsView.swift`

新增 `personaAssemblyPreview(preset:profile:)` 方法：

```swift
private func personaAssemblyPreview(preset: Preset, profile: Profile) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        // 调用 PromptAssembler.assemble() (不是 preview())
        let store = SwiftDataMemoryStore()
        let memories = store.listHot(profileId: profile.id, context: modelContext)
        let result = PromptAssembler.assemble(
            preset: preset, profile: profile, memories: memories, chatHistory: []
        )
        
        // 顶部统计
        HStack {
            Text("组装结果（后处理前）")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text("≈ \(estimateTokens(result)) tokens")
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
        
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // System Prompt 块
                if let sys = result.systemPrompt {
                    MessageBlock(role: "system", content: sys, color: .purple)
                }
                // Messages 列表
                ForEach(Array(result.messages.enumerated()), id: \.offset) { _, msg in
                    MessageBlock(role: msg.role, content: msg.content,
                                 color: msg.role == "user" ? .blue : .green)
                }
                // 对话历史占位
                PlaceholderBlock("对话历史将在这里插入（深度: \(preset.sampling.contextDepth) 条）")
            }
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.mainBg))
    }
}
```

**MessageBlock**：小组件，显示 role 标签（彩色圆角 tag）+ content 文本。

### Step 5: Tab 5 — 最终请求预览视图

**文件**: `SettingsView.swift`

新增 `personaRequestPreview(preset:profile:)` 方法：

```swift
private func personaRequestPreview(preset: Preset, profile: Profile) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        // 1. 组装
        let store = SwiftDataMemoryStore()
        let memories = store.listHot(profileId: profile.id, context: modelContext)
        let assembled = PromptAssembler.assemble(
            preset: preset, profile: profile, memories: memories, chatHistory: []
        )
        
        // 2. 后处理
        let providerType = currentProviderType()  // 读当前选中的 provider 类型
        let processed = PromptPostProcessor.process(
            systemPrompt: assembled.systemPrompt,
            messages: assembled.messages,
            sampling: preset.sampling,
            providerType: providerType
        )
        
        // 3. 构建 request body
        let modelId = currentModelId()
        let preview = PromptPostProcessor.buildRequestPreview(
            processed: processed,
            model: modelId,
            sampling: preset.sampling,
            providerType: providerType
        )
        
        // 顶部：provider 类型 + token 估算 + 变换日志
        HStack {
            Text("最终请求（\(providerType == .anthropic ? "Anthropic" : "OpenAI")）")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text("≈ \(preview.tokenEstimate) tokens")
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
        
        // 变换步骤（如果有）
        if !processed.transforms.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(processed.transforms, id: \.self) { t in
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        Text(t)
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }
        }
        
        // JSON 视图
        ScrollView {
            let jsonString = prettyJSON(preview.body)
            Text(jsonString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.mainBg))
        
        // 复制按钮
        Button("复制 JSON") { ... }
    }
}
```

**辅助函数**：
- `currentProviderType()` — 从 profile + providerManager 获取当前 provider 类型
- `currentModelId()` — 获取当前选中的 model ID
- `prettyJSON()` — dict → 格式化 JSON 字符串

### Step 6: 插槽模式加后处理设置 UI

**文件**: `SettingsView.swift`，在 `personaSamplingSection` 或 `personaSlotsMode` 里加：

```swift
// 后处理设置（紧接在采样参数后面）
HStack {
    Text("后处理")
        .font(.system(size: 11))
        .foregroundColor(Theme.textSecondary)
    Picker("", selection: postProcessingModeBinding) {
        Text("无").tag("none")
        Text("合并").tag("merge")
        Text("严格").tag("strict")
    }
    .pickerStyle(.segmented)
    .frame(width: 160)
}

Toggle("合并连续 System", isOn: squashBinding)
    .font(.system(size: 11))
Toggle("续写 Prefill", isOn: continuePrefillBinding)
    .font(.system(size: 11))
```

这些控件直接绑定 `preset.sampling.squashSystemMessages`、`preset.sampling.postProcessingMode`、`preset.sampling.continuePrefill`。

### Step 7: 删除旧的折叠预览 + 清理

- 删除 `personaPromptPreview()` 方法（1481-1502 行）
- 删除 `DisclosureGroup("实时预览")` 块（968-975 行）
- `PromptAssembler.preview()` 方法暂时保留（可能其他地方用到），但 SettingsView 不再调用

## 文件改动总览

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `Services/PromptPostProcessor.swift` | **新建** | 后处理管线：squash + merge/strict + provider 适配 + request body 构建 |
| `Models/Preset.swift` | 小改 | SamplingParams 加 `postProcessingMode: String` 字段 |
| `Views/SettingsView.swift` | 中改 | 5-Tab Picker + 组装预览 + 请求预览 + 后处理 UI + 删折叠预览 |

## 不动的

- `PromptAssembler.swift` — 第2层不改
- `ChatService.swift` — 暂不重构（后续可以让 ChatService 调用 PostProcessor，但本次先让预览能用）
- `ConversationViewModel.swift` — 发送调用链暂不改
- Tab 1-3 的编辑功能 — 不动

## 执行步骤

- [ ] Step 1: 新建 `PromptPostProcessor.swift`（核心逻辑）
- [ ] Step 2: `Preset.swift` 加 `postProcessingMode` 字段
- [ ] Step 3: `SettingsView.swift` 改 5-Tab Picker + switch 分支 + 删折叠预览
- [ ] Step 4: 实现 `personaAssemblyPreview()` (Tab 4)
- [ ] Step 5: 实现 `personaRequestPreview()` (Tab 5)
- [ ] Step 6: 在采样区域加后处理设置 UI（postProcessingMode / squash / prefill）
- [ ] Step 7: Build + 验证
- [ ] Step 8: Commit + Push

## 验证标准

- [ ] 5 个 Tab 都能正常切换，不白屏
- [ ] Tab 4（组装）：显示 system prompt + messages 列表，带 role 标签
- [ ] Tab 5（请求）：显示完整 JSON request body
- [ ] Tab 5 随 provider 类型变化（OpenAI 的 system 在 messages 里，Anthropic 的在顶层）
- [ ] 开启 squash：Tab 4 有多条 system → Tab 5 合并为一条
- [ ] 开启 strict：Tab 5 中途 system 变 user，第一条是 user
- [ ] Tab 1-3 编辑 → 切到 Tab 4/5 立刻反映
- [ ] token 估算数字合理
- [ ] Build 通过（macOS + iOS）

## 风险

1. **5 个 Tab 太挤**：segmented picker 5 项可能在窄窗口下溢出。备选：分两行（编辑行 + 预览行）或用 TabView 带自定义标签
2. **性能**：每次切到 Tab 4/5 都要跑 assemble + process。因为没有实际对话历史（chatHistory: []），应该很快。如果卡可以加 debounce
3. **PostProcessor 和 ChatService 重复逻辑**：本次先容忍重复（PostProcessor 用于预览，ChatService 用于实际发送），后续再统一

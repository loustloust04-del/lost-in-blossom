# Plan: Phase 3 — AI 行为控制（人格 + 参数 + Prompt 组装）

> 基于 research-persona-system.md + 酒馆预设实物分析，CC 制定，粟粟批注
> **don't implement yet**

---

## 目标

让用户完全控制 AI 的行为：看到什么（prompt 组装）、怎么说话（人格插槽）、怎么生成（采样参数）。提供简单模式和酒馆模式两种 UI。

## 核心概念

### Preset（预设）= 一套完整的 AI 行为配置

【即梦只是最简单的，事实上有很多种】

```
Preset
├── 采样参数: temperature, topP, topK, maxTokens, frequencyPenalty...
├── 上下文深度: contextDepth（对话历史条数）
├── 格式模板: characterFormat, scenarioFormat, personaFormat
└── 插槽列表: [PromptSlot]
    ├── ⭐ 系统指令 (system, 必开)
    ├── 🧑 用户描述 (marker: personaDescription)
    ├── 🎭 角色描述 (marker: charDescription)
    ├── 🎭 角色性格 (marker: charPersonality)
    ├── 🌍 场景 (marker: scenario)
    ├── 💬 对话示例 (marker: dialogueExamples)
    ├── 🧠 记忆注入 (marker: memoryInjection) ← 我们的 AUDN 系统
    ├── 📜 对话历史 (marker: chatHistory)
    ├── ❤️ 温柔内核 (可选开关)
    ├── ✍️ 文风-散文 (可选开关)
    ├── 🔞 NSFW指令 (可选开关)
    ├── 🛡️ 提升尊重 (可选开关)
    ├── 📌 后置提醒 (system, 必开)
    └── ... 用户自定义插槽
```

### PromptSlot（插槽）

```swift
struct PromptSlot: Identifiable, Codable {
    var id: String                    // UUID 或 well-known identifier
    var name: String                  // "⭐ 故事开始" / "❤️ 温柔内核"
    var role: String                  // "system" | "user" | "assistant"
    var content: String               // 实际 prompt 文本（marker 时为空）
    var isSystemPrompt: Bool          // true=骨架（必开），false=可选
    var isEnabled: Bool               // 开关状态（只对非 system 有效）
    var isMarker: Bool                // 占位符（由角色卡/记忆/对话填充）
    var injectionDepth: Int           // 从对话末尾数第几层插入（0=末尾）
    var injectionOrder: Int           // 排序优先级（越小越先）
}
```

### 两种模式

| | 简单模式 | 酒馆模式 |
|---|---|---|
| 目标用户 | 日常聊天 | RP/高级用户 |
| UI | 3 个文本框 + 1 个预设选择器 + 参数滑块 | 完整插槽列表 + 拖拽排序 + 开关 |
| 文本框 | 系统指令 / 角色描述 / 后置提醒 | 每个插槽单独编辑 |
| 参数 | 预设按钮（精确/平衡/创意） | 全部滑块展开 |
| 插槽管理 | 隐藏 | 可添加/删除/拖拽/导入 |

简单模式的 3 个文本框其实就是写入预设的 3 个对应插槽，底层数据结构完全一样。

---

## 文件变更总览

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | Models/Preset.swift | Preset + PromptSlot 数据模型 |
| 新建 | Services/PromptAssembler.swift | 按插槽列表组装最终 prompt |
| 修改 | MemoryPalaceApp.swift | Profile 扩展字段 + 预设存储 |
| 修改 | Services/ChatService.swift | 发送采样参数 |
| 修改 | ViewModels/ConversationViewModel.swift | 用 PromptAssembler 替换 buildAPIMessages |
| 修改 | Views/SettingsView.swift | 预设编辑 UI（简单+酒馆两种模式） |
| 修改 | Views/CardFlowView.swift | 输入栏显示当前预设/参数概要 |

---

## Checklist

### Step 1: Preset + PromptSlot 数据模型

- [ ] 1.1 新建 `Models/Preset.swift`

```swift
struct PromptSlot: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var role: String = "system"       // "system" | "user" | "assistant"
    var content: String = ""
    var isSystemPrompt: Bool = true   // 骨架 vs 可选
    var isEnabled: Bool = true
    var isMarker: Bool = false        // 占位符
    var injectionDepth: Int = 0       // 0=按顺序，>0=从对话末尾数第 N 层插入
    var injectionOrder: Int = 100     // 排序优先级
}

struct SamplingParams: Codable, Hashable {
    var temperature: Double = 0.7
    var topP: Double = 0.95
    var topK: Int = 0                 // 0=不发
    var maxTokens: Int = 4096
    var frequencyPenalty: Double = 0
    var presencePenalty: Double = 0
    var contextDepth: Int = 40        // 对话历史条数
}

struct Preset: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var description: String = ""
    var sampling: SamplingParams = SamplingParams()
    var prompts: [PromptSlot] = []

    // 格式模板（角色卡数据填入 marker 前的包装格式）
    var characterFormat: String = "[角色设定]\n{{description}}\n{{personality}}"
    var scenarioFormat: String = "[当前场景]\n{{scenario}}"
    var personaFormat: String = "[用户信息]\n{{persona}}"
}
```

- [ ] 1.2 内置预设（3 个）：

```
平衡（默认）
├── temperature: 0.7, topP: 0.95
├── 插槽: 系统指令 → 用户描述 → 角色描述 → 记忆 → 对话示例 → 对话历史 → 后置提醒
└── 后置提醒: "保持角色设定，用自然的语气回应。"

精确
├── temperature: 0.3, topP: 0.9
├── 同上插槽
└── 后置提醒: "简洁准确地回答。"

创意
├── temperature: 1.2, topP: 1.0
├── 同上插槽
└── 后置提醒: "大胆发挥，富有想象力地回应。"
```

- [ ] 1.3 Build 验证

### Step 2: Profile 扩展

- [ ] 2.1 Profile 新增字段：

```swift
struct Profile {
    // ... 现有字段 ...

    // Phase 3 新增
    var presetId: String            // 当前使用的预设 ID
    var userPersona: String         // 用户自我描述
    var characterDescription: String // AI 角色描述
    var characterPersonality: String // AI 角色性格
    var scenario: String            // 场景
    var chatExamples: String        // 对话示例
    var postInstructions: String    // 后置提醒
}
```

新字段默认空字符串，旧 Profile JSON 反序列化时自动用默认值（Codable + CodingKeys 处理）。

- [ ] 2.2 现有 `systemPrompt` 保持不变（作为预设的"系统指令"插槽内容）
- [ ] 2.3 Build 验证

### Step 3: PresetManager

- [ ] 3.1 `PresetManager` 管理预设的存储/CRUD：

```swift
@Observable
class PresetManager {
    var presets: [Preset]           // 内置 + 用户自定义
    var builtInPresets: [Preset]    // 内置 3 个（不可删除）

    func save(_ preset: Preset)
    func delete(_ preset: Preset)
    func duplicate(_ preset: Preset) -> Preset
    func importFromSillyTavern(_ json: Data) throws -> Preset
}
```

- [ ] 3.2 预设存储在 UserDefaults（JSON），跟 Profile 一样
- [ ] 3.3 Build 验证

### Step 4: PromptAssembler

- [ ] 4.1 新建 `Services/PromptAssembler.swift`：

```swift
struct PromptAssembler {
    /// 组装最终发给 API 的 system prompt + messages
    static func assemble(
        preset: Preset,
        profile: Profile,
        memories: [Memory],
        chatHistory: [(role: String, content: String)]
    ) -> (systemPrompt: String?, messages: [(role: String, content: String)])
}
```

组装逻辑：
1. 遍历 preset.prompts，按 injectionOrder 排序
2. 跳过 isEnabled=false 的插槽
3. marker 插槽用 profile 数据填充（charDescription → profile.characterDescription）
4. memoryInjection marker 用 MemoryInjector 填充
5. chatHistory marker 用对话历史填充（截取 sampling.contextDepth 条）
6. injectionDepth > 0 的插槽，不放在 system prompt 里，而是插入到对话历史的指定位置
7. role=system 的内容拼成 system prompt；role=user/assistant 的插入 messages

- [ ] 4.2 `{{user}}` / `{{char}}` 宏替换（用 profile.userName / profile.assistantName）
- [ ] 4.3 Build 验证

### Step 5: ChatService 参数传递

- [ ] 5.1 `sendStreaming()` 和 `sendNonStreaming()` 新增 `samplingParams: SamplingParams?` 参数
- [ ] 5.2 OpenAI 兼容 provider：发送 temperature, top_p, max_tokens, frequency_penalty, presence_penalty（非零时才发）
- [ ] 5.3 Anthropic provider：发送 temperature, top_p, top_k, max_tokens（非零时才发）
- [ ] 5.4 ProviderRouter 透传 samplingParams
- [ ] 5.5 Build 验证

### Step 6: ConversationViewModel 集成

- [ ] 6.1 `sendMessage()` 改用 `PromptAssembler.assemble()` 替代现有的 `buildAPIMessages()` + `buildSystemPrompt()`
- [ ] 6.2 从当前 Profile 读取 presetId → 找到 Preset → 传给 assembler
- [ ] 6.3 传 `samplingParams` 到 `providerRouter.sendStreaming()`
- [ ] 6.4 `regenerate()` 和 `editAndResend()` 同步改造
- [ ] 6.5 Build 验证

### Step 7: 设置页 — 简单模式

【设置页再加一个，完整编辑模式？就是可以直接看见发给了ai什么。直接修改的】

- [ ] 7.1 Profile 编辑器扩展：
  - 系统指令（已有 systemPrompt 文本框）
  - 角色描述（新文本框）
  - 后置提醒（新文本框）
  - 用户描述（新文本框）
  - 对话示例（新文本框）

- [ ] 7.2 预设选择器（下拉）：精确 / 平衡 / 创意 / 自定义

- [ ] 7.3 参数快捷面板（预设=自定义时展开）：
  - temperature 滑块 (0–2)
  - 上下文深度 数字输入 (1–200)
  - max_tokens 数字输入

- [ ] 7.4 Build 验证

### Step 8: 设置页 — 酒馆模式

- [ ] 8.1 模式切换开关（简单 ↔ 酒馆）

- [ ] 8.2 插槽列表视图：
  - 每个插槽一行：开关 + 名称 + role 标签 + 编辑按钮
  - marker 插槽显示为灰色（不可编辑内容，由角色卡填充）
  - 可拖拽排序
  - 添加自定义插槽按钮
  - 删除插槽（内置的不可删）

- [ ] 8.3 插槽编辑弹窗：
  - 名称
  - role 选择（system / user / assistant）
  - content 文本编辑器
  - injection_depth 数字输入
  - injection_order 数字输入
  - isSystemPrompt 开关

- [ ] 8.4 采样参数完整面板：
  - temperature, topP, topK 滑块
  - maxTokens, contextDepth 数字输入
  - frequencyPenalty, presencePenalty 滑块

- [ ] 8.5 预设管理：
  - 当前预设名 + 保存按钮
  - 另存为新预设
  - 删除自定义预设
  - 导入酒馆预设（选 JSON 文件）

- [ ] 8.6 Build 验证

### Step 9: 酒馆预设导入

- [ ] 9.1 解析酒馆 JSON 格式：
  - 顶层采样参数 → SamplingParams
  - `prompts` 数组 → [PromptSlot]
  - marker 识别（identifier 匹配 well-known: charDescription, chatHistory 等）
  - 格式模板（personality_format, scenario_format 等）

- [ ] 9.2 导入 UI：文件选择器 → 预览 → 确认导入
- [ ] 9.3 Build 验证

### Step 10: 收尾

- [ ] 10.1 CardFlowView 输入栏显示当前预设名 + temperature
- [ ] 10.2 Final build 通过
- [ ] 10.3 Commit + push

---

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 预设存哪 | UserDefaults (JSON) | 跟 Profile 一致，简单 |
| 简单模式底层 | 跟酒馆模式同一套数据结构 | 简单模式只是酒馆模式的子集 UI |
| 角色卡数据存哪 | Profile 的字段 | 一个楼层 = 一个角色 |
| 预设跟楼层的关系 | Profile.presetId 指向 Preset | 同一个预设可被多个楼层使用 |
| injection_depth | 支持 | 这是酒馆"后置指令"的核心机制 |
| 宏替换 | `{{user}}` / `{{char}}` | 酒馆标准，兼容导入 |
| 参数按 provider 过滤 | 发送前检查 | Anthropic 不支持 frequency_penalty，OpenAI 不支持 top_k |

---

## 不做的事

- ❌ 世界书 / Lorebook（需要关键词触发系统，单独做）
- ❌ TavernCard V2 PNG 解析（角色卡导入，远期）
- ❌ 群聊 / 多角色（需要回复策略系统）
- ❌ Token 精确计算（需要 tiktoken 或类似库）
- ❌ 采样参数中的 mirostat / typical_p / min_p（太小众）
- ❌ injection_trigger（关键词触发注入，属于世界书范畴）

---

## 执行顺序

Step 1-3 是数据层：模型定义 + Profile 扩展 + 预设管理。

Step 4 是核心引擎：PromptAssembler 按插槽组装 prompt。

Step 5-6 是集成层：ChatService 参数传递 + ViewModel 改造。

Step 7 是简单模式 UI（先出，快速可用）。

Step 8 是酒馆模式 UI（后出，高级用户）。

Step 9 是酒馆兼容（导入预设）。

Step 10 是收尾。

**建议先做 Step 1-7 出一版可用的，再做 8-9。**

# Research: Phase 3 — AI 行为控制（人格 + 参数 + Prompt 组装）

> CC 深读现有代码 + AI 前端调研 + 酒馆架构分析，2026-03-26

---

## 1. 问题诊断：现在模型到底看到了什么

当前每次 API 调用，发出去的就这些：

```
┌─ system prompt ─────────────────────┐
│ {Profile.systemPrompt 纯文本}        │
│                                      │
│ [关于用户]                            │
│ - 记忆条目1 [偏好]                    │
│ - 记忆条目2 [事实]                    │
│ - ...                                │
└──────────────────────────────────────┘

┌─ messages（最近 40 条，硬编码）────────┐
│ user: ...                            │
│ assistant: ...                       │
│ ...（最多 40 条，更早的直接丢弃）      │
└──────────────────────────────────────┘

参数：
- OpenAI 兼容：model + stream=true，没了
- Anthropic：model + stream=true + max_tokens=4096（硬编码），没了
- temperature/top_p/frequency_penalty：全部不发
```

### 问题清单

| # | 问题 | 严重程度 |
|---|------|---------|
| 1 | **上下文深度硬编码 40 条** — 用户不知道也改不了 | 高 |
| 2 | **无生成参数** — temperature/top_p/max_tokens 全不可调 | 高 |
| 3 | **system prompt 是一坨** — 人格描述、场景、指令全混在一个文本框里 | 高 |
| 4 | **无 token 计算** — 不知道上下文用了多少、还剩多少 | 中 |
| 5 | **无对话示例** — 酒馆的 mes_example 能教 AI "怎么说话" | 中 |
| 6 | **无后置指令** — 酒馆在对话历史后面还能插一段提醒 | 中 |
| 7 | **API 管理 UI 粗糙** — 所有 provider 平铺，无分组，无连接测试 | 中 |
| 8 | **max_tokens 硬编码** — Anthropic 4096，非流式 1024，不跟模型走 | 低 |

---

## 2. 酒馆怎么做的

### Prompt 组装顺序（12 层三明治）

```
1.  Main System Prompt        ← "你是一个..."
2.  World Info (before)        ← 关键词触发的世界设定
3.  Persona                    ← 用户自我描述
4.  Character Description      ← 角色外貌/背景
5.  Personality               ← 角色性格
6.  Scenario                  ← 当前场景/情境
7.  Enhance Definitions       ← 补充说明
8.  Auxiliary Prompt           ← 额外指令
9.  Chat Examples             ← 对话示例（教 AI 怎么说话的样板）
10. World Info (after)         ← 更多世界设定
11. Chat History              ← 实际对话
12. Post-History Instructions  ← "记住你是..."（防遗忘提醒）
```

大多数用户只用 4-5 层。完整 12 层是给重度 RP 用户的。

### 角色卡格式（TavernCard V2）

```json
{
  "name": "小克",
  "description": "外貌、背景、身份...",
  "personality": "性格特征...",
  "scenario": "当前情境...",
  "first_mes": "第一句话（打招呼）",
  "mes_example": "<START>\n{{user}}: 你好\n{{char}}: 汪汪...",
  "alternate_greetings": ["另一种打招呼方式"],
  "creator_notes": "创作者备注",
  "character_book": { /* 角色专属世界书 */ }
}
```

关键洞察：角色卡不是一个 system prompt，是**填充 prompt 组装槽位的模板**。

### 参数控制

酒馆支持的采样参数：
- temperature, top_p, top_k, typical_p
- repetition_penalty, frequency_penalty, presence_penalty
- min_p, mirostat (mode/tau/eta)
- max_tokens, context_window
- stop_sequences
- 每个参数都有滑块 + 数字输入

并且有**采样预设**（Preset）：一键切换 "Creative" / "Precise" / "Balanced" 等参数组合。

---

## 3. 原生 macOS 应用怎么做的

### macai（最接近的参考）
- 8+ providers，iCloud 同步
- **没有**参数调节 UI — 走"it just works"路线
- Keychain 存 API key

### Warden（最新，纯 SwiftUI）
- 100% SwiftUI，<150MB RAM
- **多模型对比**（最多 3 个并排）
- MCP 集成
- **没有**复杂参数 UI

### BoltAI（商业产品）
- AI Commands 模板系统（最接近酒馆的 preset 概念）
- 全局快捷键
- **最精致**的原生 macOS AI 工具

共同点：**原生 macOS 应用都走简洁路线**，没有酒馆那种满屏滑块。参数调节要么没有，要么藏在高级选项里。

---

## 4. 记忆宫殿该怎么做

### 第一性原理

用户需要控制三件事：
1. **AI 看到什么**（prompt 组装 + 上下文深度）
2. **AI 怎么说话**（人格 = prompt 槽位模板）
3. **AI 怎么生成**（temperature 等采样参数）

这三件事的载体是**角色卡（Profile 升级版）**。一张角色卡 = 一套完整的 AI 行为配置。

### Prompt 组装：酒馆 12 层 vs 我们需要几层？

12 层太多。分析实际使用场景：

| 酒馆层级 | 记忆宫殿需不需要 | 理由 |
|---------|----------------|------|
| 1. Main System | ✅ 需要 | 基础指令 |
| 2. World Info (before) | ❌ 不需要 | 暂无世界书 |
| 3. Persona | ✅ 需要 | 用户自我描述（"我叫粟粟，是..."） |
| 4. Character Description | ✅ 需要 | AI 角色描述 |
| 5. Personality | ✅ 合并到 4 | 跟描述合一个槽 |
| 6. Scenario | ⚠️ 可选 | 有些角色需要场景设定 |
| 7. Enhance Definitions | ❌ 不需要 | 太细了 |
| 8. Auxiliary Prompt | ❌ 不需要 | 跟 1 合并 |
| 9. Chat Examples | ✅ 需要 | 教 AI 说话风格的最有效手段 |
| 10. World Info (after) | ❌ 不需要 | 暂无世界书 |
| 11. Chat History | ✅ 需要（已有） | 可调深度 |
| 12. Post-History Instructions | ✅ 需要 | 防遗忘提醒（"保持角色"） |

**精简为 6 层：**

```
1. 系统指令（Main System）    ← "用简洁的中文回答"
2. 用户描述（Persona）        ← "我叫粟粟，喜欢..."
3. 角色描述（Character）      ← "你叫小克，是一只..."
4. [记忆注入]                 ← 自动（已有）
5. 对话示例（Examples）       ← 教 AI 说话风格
6. 对话历史（Chat History）   ← 可调深度
7. 后置提醒（Post-Instructions）← "记住你是小克，不要出戏"
```

### Profile 升级为角色卡

现有 Profile 字段：
```swift
struct Profile {
    var id, name, emoji, description: String
    var userName, assistantName: String
    var systemPrompt: String           // ← 唯一的 prompt 槽
    var preferredModel: String
    var createdAt: Date
}
```

需要扩展为：
```swift
struct Profile {
    // === 基础信息 ===
    var id, name, emoji, description: String
    var userName, assistantName: String
    var preferredModel: String
    var createdAt: Date

    // === Prompt 槽位（Phase 3 新增）===
    var systemPrompt: String           // 系统指令
    var userPersona: String            // 用户自我描述
    var characterDescription: String   // AI 角色描述（外貌+性格+背景）
    var chatExamples: String           // 对话示例
    var postInstructions: String       // 后置提醒
    var scenario: String               // 场景（可选）

    // === 生成参数（Phase 3 新增）===
    var temperature: Double            // 0.0–2.0，默认 1.0
    var topP: Double                   // 0.0–1.0，默认 1.0
    var maxTokens: Int                 // 默认 4096
    var contextDepth: Int              // 对话历史条数，默认 40
    var samplingPreset: String         // "balanced" | "precise" | "creative" | "custom"
}
```

### 采样预设

| 预设 | temperature | topP | 适用场景 |
|------|------------|------|---------|
| 精确 | 0.3 | 0.9 | 技术问题、事实查询 |
| 平衡 | 0.7 | 0.95 | 日常对话（默认） |
| 创意 | 1.2 | 1.0 | 写作、角色扮演 |
| 自定义 | 用户设 | 用户设 | 高级用户 |

### 发给 API 的最终 prompt 组装

```swift
func assemblePrompt(profile: Profile, memories: [Memory], history: [...]) -> (system: String, messages: [...]) {

    // 1. 系统指令
    var systemParts: [String] = []
    if !profile.systemPrompt.isEmpty {
        systemParts.append(profile.systemPrompt)
    }

    // 2. 用户描述
    if !profile.userPersona.isEmpty {
        systemParts.append("[用户信息]\n\(profile.userPersona)")
    }

    // 3. 角色描述
    if !profile.characterDescription.isEmpty {
        systemParts.append("[角色设定]\n\(profile.characterDescription)")
    }

    // 4. 记忆注入（已有）
    let memoryBlock = MemoryInjector.buildInjection(memories: memories)
    if !memoryBlock.isEmpty {
        systemParts.append("[关于用户]\n\(memoryBlock)")
    }

    // 5. 场景（可选）
    if !profile.scenario.isEmpty {
        systemParts.append("[当前场景]\n\(profile.scenario)")
    }

    let systemPrompt = systemParts.joined(separator: "\n\n")

    // 6. 对话示例 → 作为 messages 开头
    var messages: [(role: String, content: String)] = []
    if !profile.chatExamples.isEmpty {
        // 解析示例格式，转为 user/assistant 消息对
        messages += parseChatExamples(profile.chatExamples)
    }

    // 7. 对话历史（可调深度）
    messages += history.suffix(profile.contextDepth)

    // 8. 后置提醒 → 作为最后一条 system 消息或注入到最后
    // （Anthropic 不支持 messages 中间插 system，需要特殊处理）

    return (system: systemPrompt, messages: messages)
}
```

### API 管理 UI 改进

当前问题和解法：

| 问题 | 解法 |
|------|------|
| 6 个 provider 平铺 | 折叠式：有 key 的展开，没 key 的折叠 |
| 无连接测试 | "测试连接"按钮：发一条短请求验证 key 有效 |
| 模型硬编码 | 保留硬编码列表但允许手动添加自定义模型 |
| 参数散落各处 | 参数跟着 Profile（角色卡）走，不跟 provider |
| 无 token 可视化 | system prompt 编辑器旁显示 token 估算 |

### 实现顺序

```
Phase 3a: Profile 扩展 + 参数控制（最小可用）
  - Profile 加 temperature/topP/maxTokens/contextDepth
  - ChatService 发送这些参数
  - 设置页 Profile 编辑器加滑块
  - 采样预设（精确/平衡/创意）
  → 用户立刻能调参数、调深度

Phase 3b: Prompt 组装
  - Profile 加 userPersona/characterDescription/chatExamples/postInstructions
  - PromptAssembler 按 6 层组装
  - Profile 编辑器加多个文本框（分槽编辑）
  - token 估算显示
  → 用户能精细控制 AI 看到什么

Phase 3c: API 管理 UI 重做
  - 折叠式 provider 列表
  - 连接测试按钮
  - 跟 Phase 3a/3b 的参数 UI 整合
  → 整体设置体验提升

Phase 3d: 酒馆兼容（可选/远期）
  - TavernCard V2 导入（PNG 解析 embedded JSON）
  - 对话示例格式兼容 {{user}} / {{char}} 宏
  - 导出角色卡
```

---

## 5. 与现有代码的集成点

| 组件 | 现有 | 改动 |
|------|------|------|
| `Profile` struct | 9 个字段 | → 扩展到 ~18 个字段（新增 prompt 槽位 + 参数） |
| `ChatService.swift` | 不发 temperature/topP | → 从 Profile 读参数，按 provider 类型发送 |
| `ConversationViewModel` | hardcoded maxContextMessages=40 | → 从 Profile.contextDepth 读取 |
| `MemoryInjector` | 直接拼到 system prompt | → 作为 PromptAssembler 的一个槽位 |
| `ProfileEditorSheet` | 1 个 systemPrompt 文本框 | → 多个分槽文本框 + 参数滑块 + 预设按钮 |
| `SettingsView` apiTab | 平铺 provider 列表 | → 折叠式 + 连接测试 |
| `CardFlowView` 输入栏 | 模型选择器 | → 可能需要显示当前参数概要 |

---

## 6. 风险

| 风险 | 缓解 |
|------|------|
| Profile 字段太多，迁移复杂 | Profile 存在 UserDefaults (JSON)，新字段给默认值即可 |
| 参数 UI 太复杂吓跑用户 | 默认用预设，"自定义"才展开滑块 |
| Anthropic 和 OpenAI 参数不完全一致 | 按 provider type 过滤：只发该 provider 支持的参数 |
| chatExamples 格式解析 | 先用简单格式（`用户: ...\nAI: ...`），后续再兼容酒馆宏 |
| 后置提醒在 Anthropic 不好实现 | Anthropic 只有 system + messages，后置提醒可以追加到最后一条 user message 前面 |

# Preset 系统使用指南

> 基于代码阅读，2026-05-27

---

## 1. Preset 的插槽（PromptSlots）

默认预设共 **8 个插槽**，定义在 `MemoryPalace/Models/Preset.swift:74–94`，按 `injectionOrder` 排序：

| # | ID | 名称 | injectionOrder | 是否 Marker | 说明 |
|---|---|---|---|---|---|
| 1 | `main` | ⭐ 系统指令 | 0 | ❌ | 填写 profile.systemPrompt；骨架插槽，不可禁用 |
| 2 | `personaDescription` | 🧑 用户描述 | 10 | ✅ | 填充 profile.userPersona，用 personaFormat 包装 |
| 3 | `charDescription` | 📝 助手设定 | 20 | ✅ | 填充 characterDescription + characterPersonality，用 characterFormat 包装 |
| 4 | `scenario` | 📖 背景设定 | 30 | ✅ | 填充 profile.scenario，用 scenarioFormat 包装 |
| 5 | `memoryInjection` | 🧠 记忆 | 40 | ✅ | 由 MemoryInjector 动态生成，固定前缀 `[关于用户]` |
| 6 | `dialogueExamples` | 💬 对话示例 | 50 | ✅ | 填充 profile.chatExamples，解析为 user/assistant message 对，**不进入 system prompt** |
| 7 | `chatHistory` | 📜 对话历史 | 60 | ✅ | 占位符，永远跳过——对话历史由 assembler 单独处理 |
| 8 | `jailbreak` | 📌 后置提醒 | 70 | ❌ | 默认内容："保持角色设定，用自然的语气回应。" |

**Marker 插槽**：`isMarker: true` 的插槽不用自身 `content` 字段，而是从 Profile 数据或记忆中动态填充。

---

## 2. Preset 怎么被加载到对话中

入口：`PromptAssembler.assemble()` —— `MemoryPalace/Services/PromptAssembler.swift:16–165`

**组装顺序**：

```
[过滤 + 排序]
preset.prompts → 过滤 isEnabled || isSystemPrompt → 按 injectionOrder 升序
        ↓
[逐槽解析]
for slot in activeSlots:
  1. chatHistory → 直接 continue（跳过）
  2. dialogueExamples → 解析为 user/assistant 消息，加入 preHistoryMessages
  3. injectionDepth > 0 → 加入 postHistoryInjections（从对话末尾数第 N 层插入）
  4. role == "system" → 加入 systemParts（带 slot.id tag）
  5. role == "user"/"assistant" → 加入 preHistoryMessages
        ↓
[世界书注入]   （PromptAssembler.swift:80–143）
WorldBookScanner.scan() → 按 position 插入到 systemParts 或 preHistoryMessages：
  beforeCharDef / afterCharDef / beforeExamples / afterExamples / atDepth / authorNoteTop / authorNoteBot
        ↓
[上下文摘要]   （PromptAssembler.swift:149–151）
contextSummary → 追加到 systemParts，tag = "contextSummary"
        ↓
[最终输出]
systemPrompt = systemParts.map(\.content).joined(separator: "\n\n")
messages = preHistoryMessages + trimmedHistory + depth injections（按 depth 降序插入）
```

**Marker 解析规则**（`resolveSlotContent`，第 205–267 行）：
- 非 marker → 用 slot.content 本身（支持 `{{user}}` / `{{char}}` 宏）
- Marker 有内容（如酒馆导入）→ 优先用 slot.content（memoryInjection 除外，始终动态）
- Marker 无内容 → fallback 到 profile 对应字段

---

## 3. 字符限制

**代码里没有任何字符或 token 硬限制**。

软限制来自 `SamplingParams`（`Preset.swift:31–51`）：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `maxTokens` | 4096 | 单次回复最大 token |
| `contextDepth` | 40 | 保留最近 N 条对话历史 |
| `maxContextSize` | 100000 | 整个上下文窗口上限（100k tokens） |

**三万字人设可以塞进去吗？**
可以，没有代码阻止。但实际能不能用取决于：
- 模型的上下文窗口（Claude 3.5 Sonnet 约 200k tokens，约 15 万汉字）
- 人设 + 对话历史加起来不超过 `maxContextSize`（默认 100k tokens ≈ 7.5 万汉字）
- 超出时模型侧会截断，App 侧不会报错

---

## 4. Preset 怎么跟对话关联

**全局绑定到 Profile，不是每条对话单独选。**

- `Profile.presetId: String`（`MemoryPalaceApp.swift`，默认值 `"built-in-balanced"`）
- 每个 Profile 有且只有一个 active preset
- 切换 Preset → `profile.presetId = newId`（`PersonaSettingsTab.swift`）
- 发消息时：`let preset = presetManager?.preset(byId: prof.presetId) ?? Preset.balanced`（`CardFlowView.swift`）

---

## 5. 怎么在 App 里创建/编辑 Preset

UI 入口在 `PersonaSettingsTab.swift`（`MemoryPalace/Views/PersonaSettingsTab.swift`）。

**结构**（简要）：

```
PersonaSettingsTab
├── 预设选择器（Picker，绑定 profile.presetId）
│   └── 列出 presetManager.presets 里所有 Preset
├── 简单模式（personaEditMode == "simple"）
│   └── 5 个可编辑字段：系统指令 / 助手设定 / 用户描述 / 对话示例 / 后置提醒
│       对应插槽 ID：main / charDescription / personaDescription / dialogueExamples / jailbreak
│       （PersonaSettingsTab.swift:47–61）
├── 高级模式（personaEditMode == "advanced"）
│   └── 展开全部 PromptSlot，可折叠，可设置 role/order/depth
├── 原始模式（JSON）
│   └── rawJSONBuffer：直接编辑 SillyTavern 兼容 JSON，粘贴导入
├── 采样参数（samplingExpanded 折叠面板）
│   └── temperature / topP / maxTokens / contextDepth 等
└── 导入按钮（showPresetImporter）
    └── 从文件导入 SillyTavern JSON → Preset.fromSillyTavernJSON()
```

**创建新 Preset**：通过 PresetManager（`MemoryPalaceApp.swift`），复制现有 Preset 或从 JSON 导入。

---

## 6. Preset 跟 API Provider 的关系

**相互独立。**

- API Provider 由 `ProviderManager` 管理，存在 `AppStorage`
- 使用哪个模型由 `profile.preferredModel`（如 `"anthropic/claude-sonnet-4"`）决定
- Preset 控制 system prompt 结构和采样参数，不绑定特定 Provider 或模型
- 同一个 Preset 可以配合任何 Provider/模型使用
- 例外：`SamplingParams.mcpEnabled`（`Preset.swift:50`）控制 Anthropic MCP beta 是否注入，但这只影响请求头，不改变 Provider 选择

**不同模型用不同 Preset？**
目前不支持自动切换——换模型时需要手动切换 Preset 或在 `PersonaSettingsTab` 调整 `maxTokens`/`reasoningEffort` 等参数。

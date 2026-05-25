# Research: Prompt 系统对比 + 酒馆预设导入

> 审计日期: 2026-04-11

## 一、酒馆 Chat Completion Preset 格式

### 文件结构（以 `拾梦-s缝合版.json` 为例，94KB）

```json
{
  // 采样参数
  "temperature": 1,
  "frequency_penalty": 0.3,
  "presence_penalty": 0.2,
  "top_p": 0,
  "top_k": 200,
  "openai_max_context": 100000,
  "openai_max_tokens": 30000,
  "stream_openai": true,
  "seed": -1,
  "reasoning_effort": "auto",

  // 格式模板
  "wi_format": "[Details...{0}]",
  "scenario_format": "[Circumstances: {{scenario}}]",
  "personality_format": "[{{char}}'s personality: {{personality}}]",
  
  // 功能开关
  "squash_system_messages": false,
  "continue_prefill": false,
  "function_calling": false,
  "show_thoughts": true,

  // 核心：43 个 prompt 插槽
  "prompts": [
    {
      "name": "⭐故事开始",
      "role": "system",
      "identifier": "main",
      "content": "...(335字)",
      "system_prompt": true,
      "injection_position": 0,
      "injection_depth": 4,
      "forbid_overrides": false,
      "injection_order": 100,
      "injection_trigger": null  // 条件触发（正则匹配时才插入）
    },
    // ...42 more
  ],

  // 排序（可按角色不同调整顺序）
  "prompt_order": [
    { "character_id": 100001, "order": [...] }
  ],

  // 扩展
  "extensions": { "SPreset": {...}, "regex_scripts": [...] }
}
```

### 酒馆 Prompt 的关键概念

| 字段 | 说明 | 记忆宫殿对应 |
|------|------|------------|
| `identifier` | 唯一 ID（`main`/`chatHistory` 等内置 + UUID 自定义） | `PromptSlot.id` |
| `role` | `system`/`user`/`assistant` | `PromptSlot.role` ✅ |
| `content` | 实际 prompt 文本 | `PromptSlot.content` ✅ |
| `system_prompt` | 是否属于系统级（不可用户编辑） | `PromptSlot.isSystemPrompt` ✅ |
| `injection_position` | 0=顶部，1=底部 | 无，但有 `injectionOrder` |
| `injection_depth` | 从对话末尾第 N 层插入 | `PromptSlot.injectionDepth` ✅ |
| `injection_order` | 排序优先级 | `PromptSlot.injectionOrder` ✅ |
| `forbid_overrides` | 角色卡能否覆盖 | `PromptSlot.forbidOverrides` ✅ |
| `injection_trigger` | 正则匹配条件触发 | **无** |
| `enabled` (in prompt_order) | 是否启用 | `PromptSlot.isEnabled` ✅ |

### 酒馆 43 个 Prompt 分类

**内置占位符（marker）**：main、chatHistory、charDescription、charPersonality、scenario、personaDescription、dialogueExamples、worldInfoBefore/After、enhanceDefinitions、nsfw、jailbreak

**自定义插槽（UUID identifier）**：用户自己创建的，如"第二人称沉浸视角"、"文风：散文"、"记忆强化"、"NSFW指令"、"防重复"、"字数约束"等

**分 role 分布**：
- system: 20 个
- user: 7 个
- assistant: 10 个（用作 prefill，引导 AI 回复方向）

---

## 二、记忆宫殿现状

### 数据模型（`Preset.swift`）

**匹配度很高**：`PromptSlot` 已经有 identifier、role、content、injectionDepth、injectionOrder、forbidOverrides，和酒馆几乎 1:1 对应。

**缺少的**：
1. `injection_trigger` — 条件触发（正则匹配才插入），酒馆高级功能，暂不需要
2. 酒馆的 `prompt_order` 可以按角色卡不同调整顺序 — 我们暂时不需要

### PromptAssembler（`PromptAssembler.swift`）

**已实现**：
- 按 injectionOrder 排序
- marker 用 profile 数据填充
- injectionDepth > 0 插入对话历史指定位置
- 宏替换 `{{user}}` / `{{char}}`
- 对话示例解析
- `preview()` 方法输出最终 prompt 预览

**工作正常**，不需要大改。

### 设置页 Prompt Tab（`SettingsView.swift`）

当前 UI：
- 预设选择 Picker（平衡/精确/创意）
- 模式切换（简单/插槽/原始）
- 采样参数滑块 × 4
- Prompt 插槽列表（可拖拽排序、锁图标、展开编辑）
- 实时预览（折叠）
- "导入酒馆预设" 按钮 ← **已有入口但功能未实现！**

---

## 三、差距分析

### 粟粟说的核心问题

1. **"看见我给 API 到底发了什么"** — `preview()` 方法已有，但 UI 上的"实时预览"藏在折叠里，不够明显
2. **"动态管理提示词"** — 插槽系统已有，但设置页 UI 不直观
3. **"有 `<im_end>` 那种标记吗"** — 目前没有 prompt post-processing（把 messages 转成特定格式标记），酒馆有
4. **"导入酒馆预设"** — 按钮在但功能空

### 真正要做的事

| 任务 | 优先级 | 复杂度 |
|------|--------|--------|
| **导入酒馆 JSON 预设** | P0 | 中 — 字段映射已基本 1:1 |
| **prompt 预览更明显** | P1 | 小 — UI 调整 |
| **设置页 Prompt tab 优化** | P1 | 中 — 参考酒馆布局 |
| Prompt Post-Processing | P2 | 大 — 需要实现模板引擎 |
| `injection_trigger` 条件触发 | P3 | 中 |
| 按角色卡调整 prompt_order | P3 | 中 |

---

## 四、酒馆预设导入映射

### 字段对应

```
酒馆 JSON                    → 记忆宫殿 Preset
─────────────────────────────────────────────
temperature                  → sampling.temperature
frequency_penalty            → sampling.frequencyPenalty
presence_penalty             → sampling.presencePenalty
top_p                        → sampling.topP
top_k                        → sampling.topK
openai_max_tokens            → sampling.maxTokens
openai_max_context / contextDepth → sampling.contextDepth (需换算)

prompts[].identifier         → PromptSlot.id
prompts[].name               → PromptSlot.name
prompts[].role               → PromptSlot.role
prompts[].content            → PromptSlot.content
prompts[].system_prompt      → PromptSlot.isSystemPrompt
prompts[].injection_depth    → PromptSlot.injectionDepth
prompts[].injection_order    → PromptSlot.injectionOrder
prompts[].forbid_overrides   → PromptSlot.forbidOverrides

prompt_order[].order[].enabled → PromptSlot.isEnabled
prompt_order[].order[].identifier → 匹配 PromptSlot.id

scenario_format              → Preset.scenarioFormat
personality_format           → Preset.characterFormat (需转换)
```

### Marker 映射

```
酒馆 identifier      → 记忆宫殿 PromptSlot ID
main                 → main              ✅ 完全一致
chatHistory          → chatHistory       ✅
charDescription      → charDescription   ✅
charPersonality      → charPersonality   ✅
scenario             → scenario          ✅
personaDescription   → personaDescription ✅
dialogueExamples     → dialogueExamples  ✅
jailbreak            → jailbreak         ✅
worldInfoBefore      → (无对应，忽略或创建新 marker)
worldInfoAfter       → (无对应，忽略或创建新 marker)
enhanceDefinitions   → (无对应，忽略)
nsfw                 → (直接作为普通 slot 导入)
```

### 导入逻辑伪代码

```swift
func importSillyTavernPreset(json: [String: Any]) -> Preset {
    var preset = Preset(name: "导入的预设")
    
    // 1. 采样参数
    preset.sampling.temperature = json["temperature"] as? Double ?? 0.7
    preset.sampling.topP = json["top_p"] as? Double ?? 0.95
    preset.sampling.maxTokens = json["openai_max_tokens"] as? Int ?? 4096
    // ...
    
    // 2. Prompts
    let stPrompts = json["prompts"] as? [[String: Any]] ?? []
    let promptOrder = extractPromptOrder(json)  // 获取启用状态
    
    for stPrompt in stPrompts {
        let identifier = stPrompt["identifier"] as? String ?? UUID().uuidString
        let slot = PromptSlot(
            id: identifier,
            name: stPrompt["name"] as? String ?? "",
            role: stPrompt["role"] as? String ?? "system",
            content: stPrompt["content"] as? String ?? "",
            isSystemPrompt: stPrompt["system_prompt"] as? Bool ?? true,
            isEnabled: promptOrder[identifier] ?? true,
            isMarker: builtInMarkers.contains(identifier),
            injectionDepth: stPrompt["injection_depth"] as? Int ?? 0,
            injectionOrder: stPrompt["injection_order"] as? Int ?? 100,
            forbidOverrides: stPrompt["forbid_overrides"] as? Bool ?? false
        )
        preset.prompts.append(slot)
    }
    
    // 3. 格式模板
    preset.scenarioFormat = json["scenario_format"] as? String ?? preset.scenarioFormat
    preset.characterFormat = json["personality_format"] as? String ?? preset.characterFormat
    
    return preset
}
```

---

## 五、验收标准

导入 `拾梦-s缝合版.json` 后：
- [ ] 采样参数正确（temperature=1, freq_penalty=0.3, etc）
- [ ] 43 个 prompt 插槽全部导入，名称/内容/角色正确
- [ ] 启用/禁用状态与 prompt_order 一致
- [ ] injectionDepth 正确（如"故事开始" depth=4）
- [ ] 实时预览能看到完整组装结果
- [ ] 导入后能正常聊天（prompt 正确发送给 API）

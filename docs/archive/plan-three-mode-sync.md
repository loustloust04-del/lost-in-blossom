# Plan: 三模式同步 — JSON↔插槽↔简单

## 核心问题

现在三种模式**数据源不同**，没有同步：

| 模式 | 数据源 | 问题 |
|------|--------|------|
| 简单 | `profile.systemPrompt` 等 5 个字段 + 本地缓存 `editXxx` + 手动"保存"按钮 | 和 preset.prompts 完全脱节 |
| 插槽 | `preset.prompts[]` 里的 PromptSlot | marker 的 content 为空，显示的内容其实来自 profile |
| 原始 | `PromptAssembler.preview()` 只读文本 | 不能编辑，不能粘贴 JSON |

目标：**三种模式操作同一份 `preset.prompts[]`**，改一个其他两个立即反映。

## 数据架构变更

### 核心决策：slot content 是唯一真相

现在 marker slot 的 content 为空，运行时从 profile 字段拉数据。这导致：
- 导入酒馆预设时内容丢失（bug：slot 有 content 但被 marker 逻辑覆盖）
- 简单模式改的是 profile 字段，和 slot 无关
- 三种模式看到的不是同一份数据

**改成**：所有 prompt 内容都存在 `PromptSlot.content` 里。profile 的 systemPrompt/characterDescription 等字段**只作为初始值**，一旦 preset 有自己的 content 就用 preset 的。

### 简单模式数据流

```
之前：
  简单模式字段 → editXxx 本地缓存 → 点保存 → profile.systemPrompt
  插槽/原始模式 ← PromptAssembler ← profile.systemPrompt

之后：
  简单模式字段 ←→ preset.prompts[对应slot].content（直接双向绑定，无缓存）
  插槽模式 ←→ preset.prompts[].content（已有）
  原始模式 ←→ preset.toJSONString() / fromJSONString()（新增）
```

## 具体改动

### 1. 简单模式：去掉本地缓存，直接绑 slot content

**删除**：
- `@State editSystemPrompt`, `editCharDescription`, `editUserPersona`, `editChatExamples`, `editPostInstructions`
- `@State simpleModeDirty`
- `loadSimpleModeBuffers()`
- "保存"按钮（不再需要，改动即时生效）

**改成**：
```swift
private func personaSimpleMode(preset: Preset, psm: PresetManager) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        // 系统指令 → preset.prompts[main].content
        personaSlotTextField("系统指令", preset: preset, slotId: PromptSlot.mainId, 
                            placeholder: "你是一个有帮助的助手...", psm: psm)
        // 角色描述 → preset.prompts[charDescription].content
        personaSlotTextField("角色描述", preset: preset, slotId: PromptSlot.charDescriptionId,
                            placeholder: "角色的外貌、背景...", psm: psm, height: 60)
        // 用户描述 → preset.prompts[personaDescription].content
        personaSlotTextField("用户描述", preset: preset, slotId: PromptSlot.personaDescriptionId,
                            placeholder: "我叫粟粟，喜欢...", psm: psm)
        // 对话示例 → preset.prompts[dialogueExamples].content
        personaSlotTextField("对话示例", preset: preset, slotId: PromptSlot.dialogueExamplesId,
                            placeholder: "{{user}}: 你好\n{{char}}: 汪汪～", psm: psm, height: 50)
        // 后置提醒 → preset.prompts[jailbreak].content
        personaSlotTextField("后置提醒", preset: preset, slotId: PromptSlot.jailbreakId,
                            placeholder: "保持角色设定...", psm: psm)
    }
}

// 绑定 slot content 的 TextField
private func personaSlotTextField(_ label: String, preset: Preset, slotId: String, 
                                   placeholder: String, psm: PresetManager, height: CGFloat = 40) -> some View {
    let binding = Binding<String>(
        get: { preset.prompts.first(where: { $0.id == slotId })?.content ?? "" },
        set: { newValue in
            var p = preset
            if let idx = p.prompts.firstIndex(where: { $0.id == slotId }) {
                p.prompts[idx].content = newValue
                psm.save(p)
            }
        }
    )
    return personaTextField(label, text: binding, placeholder: placeholder, height: height)
}
```

这样简单模式改"系统指令" → 直接改 `preset.prompts[main].content` → 切到插槽模式立刻能看到。

### 2. 原始模式：从只读预览改为 JSON 编辑器

**删除**：
- `personaRawPreview` 的只读 Text 展示

**改成**：
```swift
private func personaRawMode(preset: Preset, psm: PresetManager) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text("JSON 编辑器")
            Spacer()
            Button("格式化") { ... }
            Button("从剪贴板粘贴") { ... }
        }
        
        TextEditor(text: Binding(
            get: { preset.toJSONString() },
            set: { newJSON in
                // 实时解析 JSON → 更新 preset
                if let parsed = try? Preset.fromJSONString(newJSON) {
                    var updated = parsed
                    updated.id = preset.id  // 保持 ID 不变
                    psm.save(updated)
                }
            }
        ))
        
        // 解析状态提示
        Text(jsonParseError ?? "JSON 有效")
    }
}
```

**注意**：实时解析每次按键都触发可能太频繁。用 debounce 或者加"应用"按钮。

**更好的方案**：用一个本地 `@State var rawJSON` 缓冲，失焦或点"应用"时才解析写回 preset。进入原始模式时从 preset 加载 JSON，离开时如果有改动就解析写回。

### 3. 初始化同步：profile → slot content

首次使用（slot content 为空但 profile 有数据）时，自动把 profile 数据填入 slot content：

```swift
// 在 personaTab 加载时检查
func syncProfileToSlots(profile: Profile, preset: inout Preset, psm: PresetManager) {
    var changed = false
    for (slotId, value) in [
        (PromptSlot.mainId, profile.systemPrompt),
        (PromptSlot.charDescriptionId, profile.characterDescription),
        (PromptSlot.personaDescriptionId, profile.userPersona),
        (PromptSlot.dialogueExamplesId, profile.chatExamples),
        (PromptSlot.jailbreakId, profile.postInstructions),
    ] {
        if let idx = preset.prompts.firstIndex(where: { $0.id == slotId }),
           preset.prompts[idx].content.isEmpty && !value.isEmpty {
            preset.prompts[idx].content = value
            changed = true
        }
    }
    if changed { psm.save(preset) }
}
```

这确保老用户不会因为迁移丢数据。

## 文件改动

| 文件 | 改动 |
|------|------|
| `SettingsView.swift` | 简单模式重写（去缓存绑 slot）；原始模式改 JSON 编辑器；删 editXxx 状态变量 |
| `PromptAssembler.swift` | 不需要改（上一个 commit 已经让 marker 优先用自身 content） |
| `Preset.swift` | 不需要改（toJSONString/fromJSONString 已有） |

## 不动的

- `personaSlotsMode` — 插槽模式已经直接操作 preset.prompts，不需要改
- `personaSamplingSection` — 采样参数已经直接操作 preset.sampling，不需要改
- `PromptAssembler` — 上一个 commit 已修复 marker content 优先级

## 执行步骤

- [ ] Step 1: 简单模式重写 — 去缓存，直接绑 slot content
- [ ] Step 2: 加 syncProfileToSlots 迁移逻辑
- [ ] Step 3: 原始模式改为 JSON 编辑器（带缓冲 + 应用按钮）
- [ ] Step 4: 删除不再需要的状态变量和方法
- [ ] Step 5: Build + 验证三模式同步
- [ ] Step 6: commit + push

## 验证标准

- [ ] 简单模式改"系统指令" → 切插槽模式，main slot content 已更新
- [ ] 插槽模式改某 slot content → 切简单模式，对应字段已更新
- [ ] 原始模式粘贴酒馆 JSON → 点应用 → 切插槽模式，所有 slot 更新
- [ ] 原始模式显示当前 preset 的完整 JSON
- [ ] 老用户的 profile 数据自动迁移到 slot content
- [ ] 导入酒馆预设后，简单模式能看到"系统指令"和"后置提醒"的内容

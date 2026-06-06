# Task: 群聊 Preset 楼层绑定

## 目标
群聊创建时，每个 AI 角色（AI A / AI B）可以绑定一个 Preset（人格预设）。Preset 的 prompt slots 在编排器调用 API 时自动注入到 messages 数组里。

## 现状
- `MemoryPalace/Models/Preset.swift`（281行）已有完整的 Preset 系统：PromptSlot 插槽、SamplingParams 采样参数、内置预设
- `CreateChatroomView.swift` 目前只有简单的 "System Prompt" 文本框
- `cc-bridge/chatroom/` 编排器在调用 API 时直接把 system prompt 作为 system message 发送

## 改动清单

### Commit 1: 前端 — Preset 选择器

**文件：`MemoryPalace/Views/CreateChatroomView.swift`**

1. 新增 `@State private var aiAPresetId: String? = nil` 和 `aiBPresetId`
2. 在每个 AI Section 的 "System Prompt" 文本框上方加一个 Preset Picker：
   - `Text("无预设").tag(String?.none)` + `ForEach(presetStore.presets)`
   - pickerStyle(.menu)
3. 如果选了 Preset，"System Prompt" 文本框变成只读预览（显示 main slot 内容）
4. 如果没选 Preset，保持现有的自由文本输入

**依赖：** 搜索 `PresetStore` 或 `PresetManager` 来获取已有 Preset 列表。

### Commit 2: 前端 — 传递 Preset 数据给后端

**文件：`MemoryPalace/Services/ChatroomService.swift`**

1. `startSession()` 新增参数 `aiAPresetSlots: [[String: Any]]?`、`aiBPresetSlots`
2. 用户选了 Preset 时，把 `preset.prompts.filter { $0.isEnabled }` 序列化成 JSON 数组：
   - 每个 slot → `{ role, content, injection_depth, injection_order, is_marker, name }`
3. POST body 新增 `ai_a_preset_slots` / `ai_b_preset_slots`

### Commit 3: 后端 — 编排器注入 Preset

**文件：`cc-bridge/chatroom/` 目录下的编排器代码**

1. `/start` endpoint 接收 `ai_a_preset_slots` / `ai_b_preset_slots`，存到 session
2. 调用 API 时按 `injection_order` 排序后注入 messages 数组：
   - `injection_depth = 0` → messages 开头（system messages）
   - `injection_depth > 0` → 从末尾数第 N 条插入
   - `is_marker = true` → 跳过（占位符）
3. 无 preset_slots 时 fallback 到原有 system prompt 文本

### Commit 4: 前端 — 群聊里显示 Preset 信息

**文件：`MemoryPalace/Views/ChatroomView.swift`**

1. 群聊头部或信息面板显示当前 Preset 名称
2. 可选：加"切换预设"按钮（进阶功能可后做）

## 测试验证
1. 创建群聊选 Preset → API 请求包含 preset_slots ✓
2. 不选 Preset → 使用 system prompt 文本 ✓
3. 两个 AI 选不同 Preset → 编排器分别注入 ✓
4. 编排器日志确认 slots 按 injection_order 排序 ✓

## 注意事项
- **三步走**：Research → Plan → Implement
- **不改 Preset.swift**，只读取数据
- **向后兼容**：没有 preset_slots 的请求正常工作
- 每个 Commit 独立可编译

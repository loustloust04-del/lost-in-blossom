# Plan: Prompt Tab 重设计 — JSON↔GUI↔简单 三层对齐

## 核心架构

```
JSON（原始模式）  ←→  插槽列表（GUI 模式）  ←→  简单字段（大众模式）
        ↕                    ↕                       ↕
   同一份 Preset 数据，三种视图实时双向同步
```

**JSON 是 single source of truth**。用户在任何模式改了数据，其他两个模式立即反映。

## 现状问题

1. **三种模式不同步** — 简单模式有独立的本地缓存（editSystemPrompt 等），和 Preset 的 slots 脱节
2. **采样参数缺失** — 只有 temperature/topP/topK/maxTokens/freqPenalty/presPenalty/contextDepth，缺 seed/reasoningEffort/verbosity/continuePrefill/squashSystemMessages 等
3. **原始模式不是 JSON 编辑器** — 目前只是显示 preview 文本，不能粘贴酒馆 JSON 解析
4. **导入酒馆预设**按钮是空的

## 改动计划

### 第一批：数据层 + 导入（让数据跑通）

- [ ] **1.1 扩充 SamplingParams**
  ```swift
  struct SamplingParams {
      // 已有
      var temperature, topP, topK, maxTokens, frequencyPenalty, presencePenalty, contextDepth
      // 新增
      var seed: Int = -1                    // -1=随机
      var reasoningEffort: String = "auto"  // "low"/"medium"/"high"/"auto"
      var verbosity: String = "auto"        // "auto"/"concise"/"verbose"
      var continuePrefill: Bool = false
      var continuePostfix: String = " "
      var squashSystemMessages: Bool = false
      var streaming: Bool = true
      var maxContextSize: Int = 100000      // 上下文窗口上限
  }
  ```

- [ ] **1.2 Preset JSON 序列化/反序列化** — 让 Preset 能和酒馆 JSON 格式互转
  ```swift
  extension Preset {
      /// 从酒馆 JSON 导入
      static func fromSillyTavernJSON(_ data: Data) throws -> Preset
      /// 导出为酒馆兼容 JSON
      func toSillyTavernJSON() -> Data
      /// 从完整 JSON string 解析（原始模式粘贴用）
      static func fromJSON(_ string: String) throws -> Preset
      /// 序列化为 JSON string（原始模式显示用）
      func toJSON() -> String
  }
  ```

- [ ] **1.3 导入酒馆预设功能**
  - 实现 `Preset.fromSillyTavernJSON()`
  - 映射 prompts[] → PromptSlot[]
  - 映射 prompt_order 的 enabled 状态
  - 映射采样参数
  - "导入酒馆预设"按钮打开文件选择器 → 导入 → 保存

- [ ] **1.4 Build + 验证导入**
  - 导入 `拾梦-s缝合版.json`
  - 43 个插槽正确出现
  - 采样参数正确

### 第二批：三模式同步（让 UI 对齐）

- [ ] **2.1 去掉简单模式的本地缓存** — 简单模式直接读写 Preset.prompts 里的 marker slot：
  - "系统指令" → `prompts[main].content`
  - "角色描述" → profile.characterDescription（不在 preset 里）
  - "用户描述" → profile.userPersona
  - "对话示例" → profile.chatExamples
  - "后置提醒" → `prompts[jailbreak].content`

- [ ] **2.2 原始模式改为 JSON 编辑器**
  - TextEditor 显示 `preset.toJSON()`
  - 用户编辑后实时 parse → 更新 Preset
  - 粘贴酒馆 JSON → 自动解析 → 插槽/简单模式立即更新
  - 解析失败时显示错误提示，不覆盖现有数据

- [ ] **2.3 插槽模式和简单模式读同一份数据**
  - 切换模式时不需要"加载"或"保存"
  - 任何模式的修改立即反映到其他模式

### 第三批：补齐 UI 参数面板

- [ ] **3.1 采样参数面板补全**
  在现有 Temperature/TopP/MaxTokens/ContextDepth 基础上加：
  - Seed 输入框（-1=随机）
  - Reasoning Effort 选择器（auto/low/medium/high）
  - Streaming 开关
  - Squash System Messages 开关
  - Continue Prefill 开关
  - Max Context Size 输入

- [ ] **3.2 Prompt 预览改进**
  - 从折叠改为独立 tab 或更明显的入口
  - 显示完整的 messages 数组（含 role 标签）
  - 显示 token 数估算

## 文件改动

| 文件 | 批次 | 内容 |
|------|------|------|
| `Preset.swift` | 1 | SamplingParams 扩充 + JSON 序列化/反序列化 |
| `PromptAssembler.swift` | 1 | 适配新参数（squash 等） |
| `SettingsView.swift` | 2-3 | 三模式同步 + 参数面板 + JSON 编辑器 |
| `ChatService.swift` | 1 | 传递新参数（streaming/seed 等） |
| `PresetManager` (in App.swift) | 1 | 导入/保存逻辑 |

## 执行顺序

先做第一批（数据层 + 导入），build 验证后再做第二批（UI 同步），最后第三批（参数面板）。

## 验收标准（以 `拾梦-s缝合版.json` 为准）

- [ ] 导入后切到插槽模式：43 个 slot 全在，名称/角色/内容正确
- [ ] 切到原始模式：看到完整 JSON
- [ ] 切到简单模式：看到系统指令和后置提醒
- [ ] 在原始模式粘贴新 JSON → 插槽模式自动更新
- [ ] 在简单模式改系统指令 → 插槽和原始都更新
- [ ] 采样参数全部可调
- [ ] 导入后能正常聊天

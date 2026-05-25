# Research: 采样参数 Gap 分析 — 酒馆 vs 记忆宫殿

> 2026-04-12，对比 SillyTavern 1.7 Chat Completion Preset 面板

## Gap 总表

| 参数 | 已存储 | 有 UI | 发送 API | 需要做 |
|------|--------|-------|----------|--------|
| **已完善** | | | | |
| Temperature | ✅ | ✅ 滑块 | ✅ OpenAI+Anthropic | - |
| Top P | ✅ | ✅ 滑块 | ✅ OpenAI+Anthropic | - |
| Max Tokens | ✅ | ✅ 滑块 | ✅ OpenAI+Anthropic | - |
| 上下文深度 (contextDepth) | ✅ | ✅ 滑块 | ✅ 控制历史条数 | - |
| Squash System Messages | ✅ | ✅ 勾选 | ✅ PostProcessor | - |
| Post-Processing Mode | ✅ | ✅ 选择器 | ✅ PostProcessor | - |
| Continue Prefill | ✅ | ✅ 勾选 | ❌ 未接入发送管线 | 接入管线 |
| **有存储没 UI（本次补全）** | | | | |
| Top K | ✅ `topK: 0` | ❌ | ✅ Anthropic only | **加滑块** |
| Frequency Penalty | ✅ `frequencyPenalty: 0` | ❌ | ✅ OpenAI only | **加滑块** |
| Presence Penalty | ✅ `presencePenalty: 0` | ❌ | ✅ OpenAI only | **加滑块** |
| Streaming | ✅ `streaming: true` | ❌ | ✅ 已发送 | **加开关** |
| Seed | ✅ `seed: -1` | ❌ | ✅ OpenAI (>=0 时发) | **加输入框** |
| Reasoning Effort | ✅ `reasoningEffort: "auto"` | ❌ | ❌ 未发送 | **加下拉 + 接 API** |
| Verbosity | ✅ `verbosity: "auto"` | ❌ | ❌ 未发送 | **加下拉 + 接 API** |
| Continue Postfix | ✅ `continuePostfix: " "` | ❌ | ❌ 未接入 | **加输入框** |
| **酒馆有我们没有（跳过）** | | | | |
| Repetition Penalty | ❌ | ❌ | ❌ | 跳过 — 仅 local 模型 (llama.cpp) |
| Min P | ❌ | ❌ | ❌ | 跳过 — 小众，主流 API 不支持 |
| Top A | ❌ | ❌ | ❌ | 跳过 — 小众，主流 API 不支持 |
| Context Size (tokens) | ✅ `maxContextSize` | ❌ | ❌ | 远期 — token 窗口管理 |
| Enable Web Search | ❌ | ❌ | ❌ | 跳过 — 另开功能 |
| Enable Function Calling | ❌ | ❌ | ❌ | 跳过 — MCP 相关，另开功能 |
| Interleaved Thinking | ❌ | ❌ | ❌ | 跳过 — Anthropic beta 功能 |
| Send Inline Media | ❌ | ❌ | ❌ | 跳过 — 图片支持后再说 |
| Inline Image Quality | ❌ | ❌ | ❌ | 跳过 — 同上 |
| Logit Bias | ❌ | ❌ | ❌ | 跳过 — 极小众 |
| Middle-out Transform | ❌ | ❌ | ❌ | 跳过 — 酒馆特有 prompt 压缩 |
| Character Names Behavior | ❌ | ❌ | ❌ | 跳过 — 复杂度高收益低 |
| Max Prompt Cost | ❌ | ❌ | ❌ | 远期 — 需要 token 精确计数 |

## 各参数说明

### 本次要加 UI 的 8 个

| 参数 | 范围/类型 | 默认值 | 适用 Provider | 说明 |
|------|----------|--------|--------------|------|
| Top K | 0-500, step 1 | 0 (不发) | Anthropic | 从概率最高的 K 个 token 中采样 |
| Frequency Penalty | -2.0~2.0, step 0.05 | 0 | OpenAI | 惩罚已出现 token 的频率 |
| Presence Penalty | -2.0~2.0, step 0.05 | 0 | OpenAI | 惩罚已出现过的 token |
| Streaming | Bool | true | 全部 | 流式输出 |
| Seed | Int, -1=随机 | -1 | OpenAI | 确定性输出 |
| Reasoning Effort | "auto"/"low"/"medium"/"high" | "auto" | OpenAI (o-系列), Anthropic (extended thinking) | 控制推理深度 |
| Verbosity | "auto"/"concise"/"verbose" | "auto" | 部分模型 | 控制输出详细度 |
| Continue Postfix | String | " " | 全部（续写时用） | 续写追加文本 |

### 跳过的理由

- **Repetition Penalty / Min P / Top A**：这些是 llama.cpp / Kobold / Text Generation WebUI 的本地模型参数，OpenAI 和 Anthropic API 都不支持
- **Web Search / Function Calling**：属于独立功能模块，不是采样参数
- **Interleaved Thinking**：Anthropic beta 功能，需要特殊 header，后续单独支持
- **Logit Bias**：需要 token ID 映射，极小众用途
- **Middle-out Transform**：酒馆特有的 prompt 压缩算法，我们的 PostProcessor 已有 squash/merge/strict

## 文件涉及

| 文件 | 改动 |
|------|------|
| `Views/SettingsView.swift` | `personaSamplingSection` 加 8 个控件 |
| `Services/ChatService.swift` | OpenAI/Anthropic provider 发送 reasoning_effort, verbosity |
| `Services/PromptPostProcessor.swift` | `buildRequestPreview` 加 reasoning_effort, verbosity |

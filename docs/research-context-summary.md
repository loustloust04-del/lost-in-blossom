# Research: 上下文总结（最小版）

> 2026-04-18
> 对应 roadmap M7

---

## 一、问题

当前 `contextDepth=40`，超出的消息**直接丢弃**。用户聊到第 41 条时，AI 默默遗忘最早的对话，没有任何提示，也不会保留摘要。

目标：到阈值时自动总结旧消息，把摘要注入 prompt，让 AI 不失忆。

---

## 二、竞品方案对比

### Operit（Android/Kotlin）

**触发条件**（二选一）：
- token 使用量 ≥ `summaryTokenThreshold × maxTokens`（默认 70%）
- 自上次总结后用户消息数 ≥ `summaryMessageCountThreshold`（默认 16 条）

**执行**：
- 调当前模型总结旧消息
- 总结存为特殊消息（`sender == "summary"`）
- 下次请求只发 summary + 新消息

**设置 UI**：
- 上下文长度（K）、最大上下文长度（K）
- 总结开关、token 阈值滑块、消息数阈值
- 图片/媒体历史保留轮数

**优点**：简单直接，用户可调参
**缺点**：总结质量依赖当前模型，没有增量机制

### Kelivo（Flutter）

**两种模式**：
1. **手动压缩**：按钮触发，截取对话文本（≤6000 字符）→ 调 compress model 总结 → 新对话以摘要开头
2. **自动增量总结**：每 N 条消息触发，new_messages + previous_summary → 更新 `Conversation.summary` 字段（≤2000 字符）

**模型配置**：总结模型可单独配（compress model → summary model → title model → assistant model → 全局默认，逐级 fallback）

**优点**：增量总结、可配独立模型
**缺点**：手动压缩会丢失原始消息

### Claude Code（TypeScript）

**多层架构**：
1. **Microcompact**：清理旧 tool result 内容，不动对话文本
2. **Auto-compact**：context 达到 `effectiveWindow - 13K` token 时触发
3. **Session Memory Compact**：实验性，基于结构化记忆模板

**总结 prompt 格式**（9 段式）：
1. Primary Request and Intent
2. Key Technical Concepts
3. Files and Code Sections（含完整代码片段）
4. Errors and Fixes
5. Problem Solving
6. All User Messages（逐条原文）
7. Pending Tasks
8. Current Work
9. Optional Next Step

**特殊设计**：
- `<analysis>` 思考块：让模型先分析再输出，最后剥离分析块只保留摘要
- 用户可在 CLAUDE.md 写 `## Compact Instructions` 自定义总结侧重
- 失败 3 次后熔断，不再重试

**优点**：结构化总结质量极高，保留关键细节
**缺点**：工程复杂度高，面向代码场景设计

---

## 三、我们的现状

### 当前数据流

```
用户发消息
  → ConversationViewModel.sendMessage()
    → buildAPIMessages(maxMessages: contextDepth)  // 硬截取最近 N 条
    → PromptAssembler.assemble()                    // 组装 system + messages
      → chatHistory.suffix(contextDepth)            // 再截一次（冗余）
    → ProviderRouter.sendStreaming()                 // 发给 API
    → onComplete:
      → extractMemoriesIfNeeded()                   // AUDN 记忆提取（已 hook！）
```

### 关键发现

1. **截断发生在两处**：`buildAPIMessages(maxMessages:)` 和 `PromptAssembler.assemble()` 里都有 `.suffix(contextDepth)`，冗余但不冲突
2. **AUDN 记忆提取已经接好了**（`extractMemoriesIfNeeded` 在 `onComplete` 里调用），`cheapModel()` 会自动选便宜模型。**如果记忆没生效，问题可能是**：
   - 没有配置任何 API key（cheapModel fallback 到当前模型）
   - 提取 prompt 返回的 JSON 解析失败
   - memoryEnabled 开关为 false
   - **需要实际测试确认**
3. **Conversation 模型没有 summary 字段** — 需要新增
4. **没有 token 计数** — 目前不知道一条消息占多少 token，只能按消息条数触发

---

## 四、最小版方案

### 设计原则

- **不改 Conversation 模型**（避免 SwiftData migration 风险）
- **按消息条数触发**（不依赖 token 计数，简单可靠）
- **摘要存 UserDefaults**（按 conversationId 存，轻量，不污染数据库）
- **总结用 cheapModel**（已有选便宜模型的逻辑）
- **注入 system prompt**（跟记忆一样，拼在系统消息里）

### 触发逻辑

```
chatHistory 总条数 > contextDepth 时：
  oldMessages = chatHistory[0 ..< (count - contextDepth)]
  recentMessages = chatHistory.suffix(contextDepth)

  如果 oldMessages 不为空，且没有已缓存的摘要（或摘要对应的消息数已变化）：
    → 调 cheapModel 总结 oldMessages
    → 存摘要到 UserDefaults[conversationId]
    → 下次 assemble 时把摘要注入 system prompt
```

### 注入位置

在 `PromptAssembler.assemble()` 里，摘要作为 system prompt 的一部分注入，位置在**记忆注入之后、对话历史之前**：

```
[system prompt 各插槽]
[记忆注入: 关于用户的原子事实]
[上下文摘要: 以下是之前对话的摘要...]   ← 新增
[对话历史: 最近 N 条消息]
```

### 总结 Prompt

参考 Claude Code 的结构化方式，但简化为对话场景：

```
请总结以下对话历史的要点。保留：
1. 用户提出的主要话题和需求
2. AI 给出的关键回答和结论  
3. 做出的决策和达成的共识
4. 未解决的问题

用简洁的段落形式输出，控制在 500 字以内。不要用"用户说""AI回答"这样的叙述，直接陈述事实。
```

### 需要改动的文件

| 文件 | 改动 |
|------|------|
| `ConversationViewModel.swift` | `assemblePrompt()` 里读摘要并传给 PromptAssembler；`sendMessage()` 的 `onComplete` 里检查是否需要总结 |
| `PromptAssembler.swift` | `assemble()` 新增 `contextSummary: String?` 参数，注入 system prompt |
| `Services/` 新建 `ContextSummarizer.swift` | 总结逻辑：判断是否需要总结、构建总结请求、解析结果、存取摘要 |
| `PersonaSettingsTab.swift`（或新设置页） | 总结开关 + 阈值显示（最小版可以先不做 UI，用默认值） |

### 存储方案

```swift
// ContextSummarizer.swift

struct ConversationSummary: Codable {
    let summary: String
    let coveredMessageCount: Int  // 摘要覆盖了多少条旧消息
    let updatedAt: Date
}

// 存取：UserDefaults，key = "ctxSummary_\(conversationId)"
// 导入的旧对话不需要总结（用户只是浏览不是聊天）
// 对话删除时清理对应摘要
```

### 增量更新

不做全量重新总结。当旧消息增长时：

```
已有摘要覆盖了 30 条旧消息
现在旧消息变成 45 条（新增了 15 条）
→ 把"旧摘要 + 新增的 15 条消息"一起发给模型
→ 让模型在旧摘要基础上更新
→ 新摘要覆盖 45 条
```

增量 prompt：
```
以下是之前对话的摘要：
---
{previousSummary}
---

以下是摘要之后新发生的对话：
---
{newMessages}
---

请更新摘要，合并新旧内容。保留所有重要信息，控制在 500 字以内。
```

---

## 五、不做的事情（Phase 3 完整版）

- ❌ 独立总结模型配置 UI — 先用 cheapModel 逻辑
- ❌ 手动触发大总结/小总结按钮 — 先只做自动
- ❌ 右栏上下文管理面板 — 先不可视化
- ❌ 总结提示词自定义 — 先硬编码
- ❌ token 精确计数触发 — 先按消息条数
- ❌ 文件/图片截断策略 — 先不处理多模态
- ❌ `<analysis>` 思考块 — Claude Code 的方案太重，对话场景不需要

---

## 六、关于记忆系统

调查发现 **AUDN 记忆提取已经 hook 好了**（`sendMessage` → `onComplete` → `extractMemoriesIfNeeded`）。粟粟说"记忆是摆设"，可能原因：

1. **cheapModel 找不到可用模型**：如果只配了一个 API，且不是 Haiku/GPT-4o-mini/DeepSeek，会 fallback 到主模型（贵且可能失败）
2. **提取 prompt 返回的 JSON 解析失败**：MemoryExtractor 期望特定 JSON 格式，模型稍有偏差就会 silent fail
3. **提取窗口太小**：`memoryExtractWindow = 5`，只看最近 5 条消息
4. **没有日志**：提取成功/失败完全无感知，用户不知道发生了什么

**建议**：在做上下文总结之前，先花半小时**在设置页的记忆 tab 加一行日志**（"最后一次提取：成功/失败/时间"），确认 AUDN 到底有没有在跑。

---

## 七、实施顺序

1. **确认记忆系统是否在跑**（半小时）— 加日志，自己聊几轮看看
2. **新建 `ContextSummarizer.swift`**（1 天）— 总结逻辑 + 存取 + prompt
3. **改 `PromptAssembler.swift`**（半天）— 接入 contextSummary 参数
4. **改 `ConversationViewModel.swift`**（半天）— assemblePrompt 传摘要 + onComplete 触发总结
5. **测试**（半天）— 聊超过 40 条验证
6. **（可选）设置 UI**（半天）— 总结开关 + 简单状态显示

总预估：**2-3 天**

---

*写完 research，等粟粟确认方向后写 plan。*

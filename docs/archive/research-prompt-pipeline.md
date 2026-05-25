# Research: Prompt Pipeline — 从编辑到 API 请求的五层架构

> 基于粟粟的深度研究报告 + 酒馆源码分析 + 我们的讨论，整理于 2026-04-12
> 更新：四层 → 五层（组装预览和最终请求是两个不同的东西）

## 一、五层模型

```
┌─────────────────────────────────────────────────────────────┐
│ 第1-3层：编辑（三种视图，同一份 preset.prompts[]）              │
│                                                               │
│  Tab 1: 简单    Tab 2: 插槽    Tab 3: JSON                    │
│  [5个字段]      [slot列表]     [{"prompts":[...]}]             │
│      ↕              ↕               ↕                         │
│              preset.prompts[] (唯一数据源)                     │
│                         ✅ 可编辑                              │
└──────────────────────────┬────────────────────────────────────┘
                           ↓ PromptAssembler
┌──────────────────────────┴────────────────────────────────────┐
│ 第4层：组装预览 (Tab 4)                                         │
│                                                               │
│  · 按 injectionOrder 排序后的 messages                         │
│  · 宏已替换：{{user}} → 粟粟, {{char}} → 小雾                  │
│  · 记忆已注入、对话历史已插入                                    │
│  · role 标签可见（可能有多条 system、穿插的 user/assistant）      │
│  · 但还没被后处理动过 — system 没合并、role 没降级、没加 prefill  │
│                         ❌ 只读                                │
└──────────────────────────┬────────────────────────────────────┘
                           ↓ PostProcessor (squash/strict/provider 适配)
┌──────────────────────────┴────────────────────────────────────┐
│ 第5层：最终请求 (Tab 5)                                         │
│                                                               │
│  · 经过 squash 合并连续 system                                  │
│  · 经过 Prompt Post-Processing (Merge/Strict/Single)           │
│  · 经过 Provider 适配：                                        │
│    - OpenAI: system 留在 messages 里                           │
│    - Anthropic: system 抽到顶层 `system` 字段                  │
│  · prefill 已追加（或因模型不支持被改写）                        │
│  · 完整 HTTP request body JSON + token 计数                    │
│                         ❌ 只读                                │
└───────────────────────────────────────────────────────────────┘
```

**为什么要分两个只读 Tab**：
- 用户踩坑（"我的 system 怎么跑到 user 里了"/"tool 消息怎么没了"）发生在 4→5 这步
- 看 Tab 4 能确认"我的 prompt 编辑内容都到齐了"
- 看 Tab 5 能确认"发给 AI 的真实 request 长什么样"
- 酒馆经验：post-processing 前后的 messages[] 都能切换查看

### 五个 Tab 总览

| Tab | 名称 | 看到什么 | 可编辑 |
|-----|------|---------|--------|
| 1 | 简单 | 5 个字段 | ✅ 改了同步到插槽/JSON |
| 2 | 插槽 | slot 列表 + 采样参数 + 后处理设置 | ✅ |
| 3 | JSON | preset 完整 JSON | ✅ 粘贴酒馆 JSON |
| 4 | 组装 | PromptAssembler 输出，宏替换 + 记忆注入后，后处理前 | ❌ 只读 |
| 5 | 请求 | 最终 request body JSON，经过全部后处理 + provider 适配 | ❌ 只读 |

### 当前状态

| 层 | 状态 | 说明 |
|----|------|------|
| Tab 1-3 编辑 | ✅ 完成 | 三模式同步，简单/插槽/JSON 操作同一份 preset.prompts[] |
| Tab 4 组装预览 | ⚠️ 半成品 | 有个折叠预览面板（PromptAssembler.preview），需要提升为独立 Tab |
| Tab 5 最终请求 | ❌ 缺失 | 后处理管线不存在，provider 适配也没有，request body 预览没有 |
| PostProcessor | ❌ 缺失 | SamplingParams 里存了 squash/prefill 参数但没接入管线 |

## 二、OpenAI vs Anthropic Request Body 差异

### OpenAI Chat Completions (`/v1/chat/completions`)

```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "system", "content": "系统指令..."},
    {"role": "user", "content": "角色描述..."},
    {"role": "assistant", "content": "..."},
    {"role": "user", "content": "最新消息"}
  ],
  "temperature": 1.0,
  "top_p": 0.95,
  "max_tokens": 4096,
  "frequency_penalty": 0.3,
  "presence_penalty": 0.2,
  "stream": true,
  "seed": 42,
  "stop": ["<END>"]
}
```

**关键特征**：
- 没有顶层 `system` 字段
- system prompt 作为 `messages[]` 里 `role: "system"` 的消息
- 可以有多条 system 消息，可以在对话中间插入
- 新模型推荐用 `role: "developer"` 替代 `role: "system"`
- tool 相关用 `role: "tool"` + `tool_call_id`

### Anthropic Messages (`/v1/messages`)

```json
{
  "model": "claude-sonnet-4-5",
  "system": [
    {"type": "text", "text": "系统指令..."},
    {"type": "text", "text": "角色描述..."}
  ],
  "messages": [
    {"role": "user", "content": [{"type": "text", "text": "你好"}]},
    {"role": "assistant", "content": [{"type": "text", "text": "你好！"}]},
    {"role": "user", "content": [{"type": "text", "text": "最新消息"}]}
  ],
  "max_tokens": 4096,
  "temperature": 1.0,
  "top_p": 0.95,
  "top_k": 200,
  "stream": true,
  "stop_sequences": ["<END>"]
}
```

**关键特征**：
- `system` 是独立顶层字段（string 或 content blocks 数组）
- `messages[]` 里**不允许** `role: "system"`
- messages 只有 `user` / `assistant` 两种 role
- content 用 blocks 形式 `[{type: "text", text: "..."}]`
- tool 语义通过 content blocks 表达 (`tool_use` / `tool_result`)，不是独立 role
- **Opus 4.6 和 Mythos Preview 不支持 assistant prefill**（末尾 assistant 会 400）

### 差异总结

| 方面 | OpenAI | Anthropic |
|------|--------|-----------|
| system prompt 位置 | `messages[]` 里的 `role: "system"` | 顶层 `system` 字段 |
| system 消息数量 | 可多条，可穿插对话中 | 顶层 system 可多块，messages 里不允许 |
| messages role 种类 | system/developer/user/assistant/tool | user/assistant（仅两种） |
| content 格式 | string 或 content parts | content blocks 数组 |
| tool 消息 | `role: "tool"` + `tool_call_id` | user message 里的 `tool_result` block |
| prefill | 无限制 | 某些模型禁止 |
| 采样独有参数 | `frequency_penalty`, `presence_penalty`, `seed` | `top_k` |
| stop 参数名 | `stop` | `stop_sequences` |

## 三、酒馆 (SillyTavern) 的后处理管线

酒馆的后处理是我们第3层最需要参考的。核心流程：

### 3.1 Prompt Post-Processing 模式

酒馆提供多种规整策略，通过 `mergeMessages(messages, strict, placeholders, tools, single)` 实现：

| 模式 | 行为 |
|------|------|
| **None** | 不处理，messages 原样发送 |
| **Merge** | 合并连续同 role 消息（用 `\n\n` 连接） |
| **Merge + Tools** | 同上，保留 tool_calls/tool role |
| **Semi-strict** | 合并 + 中途 system 降级为 user |
| **Semi-strict + Tools** | 同上，保留 tools |
| **Strict** | 合并 + 强制 user first + 中途 system 降级 + 插 placeholder |
| **Strict + Tools** | 同上，保留 tools |
| **Single** | 所有消息合并成一条 user message（极端降维） |

**mergeMessages 关键步骤**：
1. 多模态 flatten：image/video URL 替换为 token 占位，合并后还原
2. name 前缀化：`message.name` 变成 `"{name}: "` 拼到 content，删 name 字段
3. tools=false 时：删除 `tool_calls` / `tool_call_id`，`role: "tool"` 改为 `role: "user"`
4. strict=true 时：i>0 的 system role 强制改为 user
5. single=true 时：所有 role 改为 user
6. 合并：相邻同 role 的 messages 用 `\n\n` 连接 content
7. strict + placeholders：如果 messages[0] 不是 user，插入占位 user message

### 3.2 squashSystemMessages（已 deprecated）

合并**连续的** system messages 为一条（不含 Example Dialogue）。现在推荐用 Prompt Post-Processing 的 Merge/Strict 模式替代。

### 3.3 convertClaudeMessages（Anthropic 适配）

酒馆的 `convertClaudeMessages(messages, prefillString, useSysPrompt, useTools, names)` 是 OpenAI ChatML → Anthropic Messages 的核心转换：

1. **抽取系统消息**：从 messages 开头收集连续 `role: "system"`，转为 `systemPrompt: [{type:"text", text:...}]`，从 messages 中移除
2. **空消息处理**：如果移除 system 后 messages 为空，插入 user 占位
3. **中途 system 降级**：后续出现的 `role: "system"` 改为 `role: "user"`
4. **tool 转换**：`tool_calls` → `tool_use` blocks；`role: "tool"` → `role: "user"` + `tool_result` block
5. **content 统一**：string → `[{type:"text", text:"..."}]`；image_url → Anthropic image block
6. **空文本处理**：空字符串替换为零宽字符
7. **prefill 追加**：如果有 prefillString，末尾追加 `role: "assistant"` 消息
8. **相邻同 role 合并**：content blocks 直接 push 到同一条（Anthropic 要求 user/assistant 交替）
9. **返回**：`{ messages, systemPrompt }`

### 3.4 Prefill 兼容性

| 情况 | 行为 |
|------|------|
| 支持 prefill 的模型 | messages 末尾追加 assistant message，模型从该前缀续写 |
| 不支持 prefill 的模型 (Opus 4.6, Mythos) | 末尾 assistant 强制改为 user，避免 400 |
| thinking/adaptive thinking 模式 | `fixThinkingPrefill` 特殊处理 |

### 3.5 Continue Prefill

与 assistant prefill 不同：
- 默认 continue：末尾加 `role: "system"` 指令（"继续上一条输出"）
- continue prefill 开启：改为 `role: "assistant"` message（模型像补全一样续写）
- 受 provider prefill 兼容性限制

## 四、我们需要实现什么

### UI 呈现：五个 Tab

| Tab | 名称 | 看到什么 | 可编辑 |
|-----|------|---------|--------|
| 1 | 简单 | 5 个字段（系统指令、角色描述、用户描述、对话示例、后置提醒） | ✅ 改了同步到其他模式 |
| 2 | 插槽 | slot 列表 + 采样参数 + 后处理设置 | ✅ |
| 3 | JSON | preset 完整 JSON | ✅ 粘贴酒馆 JSON |
| 4 | 组装 | PromptAssembler 输出：宏替换 + 记忆注入后，后处理前的 messages | ❌ 只读 |
| 5 | 请求 | 最终 HTTP request body JSON，经过全部后处理 + provider 适配 | ❌ 只读 |

**Tab 4 vs Tab 5 的区别**：
- Tab 4（组装）：多条 system 还在、role 没被改写、没加 prefill → 确认"我的编辑内容都到齐了"
- Tab 5（请求）：squash 合并后、strict 降级后、provider 适配后的真实 JSON → 确认"发给 AI 的东西是对的"
- 用户踩坑（system 跑到 user 里 / tool 消息消失）发生在 4→5 这步，两个都能看才好排查

### PostProcessor 实现清单

需要新建 `PromptPostProcessor.swift`，在 PromptAssembler 输出后、发送前执行：

1. **Prompt Post-Processing（角色/顺序规整）**：
   - 实现 `mergeMessages` 逻辑（至少支持 None / Merge / Strict 三种模式）
   - None：不处理
   - Merge：合并连续同 role 消息（`\n\n` 连接）
   - Strict：合并 + 强制 user first + 中途 system 降级为 user + 插占位 placeholder

2. **Provider 适配**：
   - OpenAI：system 留在 messages[] 里（可多条）
   - Anthropic：开头连续 system 抽到顶层 `system` 字段，中途 system 降级为 user
   - Anthropic content → blocks 化 `[{type:"text", text:"..."}]`
   - Anthropic 相邻同 role 合并（user/assistant 必须交替）

3. **Prefill 处理**：
   - assistant prefill（用户配置的前缀）→ 末尾追加 assistant message
   - continue prefill（续写模式）→ system 指令改为 assistant message
   - 模型兼容性检查：Opus 4.6 / Mythos Preview 禁止 prefill → 末尾 assistant 强制改 user

4. **squash system messages**：
   - 合并连续 system 消息为一条
   - 可作为 Post-Processing Merge 模式的一部分

### Tab 4（组装预览）实现清单

把现有的折叠预览面板提升为独立 Tab：

1. **Messages 列表视图**：每条消息显示 role 标签（彩色）+ content
2. **来源标注**：每条消息标注来自哪个 slot（Main Prompt / Character Description / Memory / Chat History 等）
3. **Token 计数**：system prompt + messages 各自的 token 数

### Tab 5（最终请求）实现清单

1. **Raw JSON 视图**：严格等于实际发出的 request body（API key 脱敏）
2. **Provider 感知**：根据当前选择的 API provider 类型（OpenAI/Anthropic）显示对应格式
3. **Token 计数**：总 token 数
4. **差异高亮**（可选，后续迭代）：和 Tab 4 对比，标注哪些 role 被改写、哪些消息被合并

### SamplingParams 已有但未接入的参数

这些参数在 `Preset.swift` 的 SamplingParams 里已经定义，但还没有 UI 控件，也没有接入后处理管线：

| 参数 | 用途 | 接入位置 |
|------|------|---------|
| `squashSystemMessages` | 合并连续 system | PostProcessor |
| `continuePrefill` | 续写用 assistant role | PostProcessor |
| `continuePostfix` | 续写追加文本 | PostProcessor |
| `seed` | 随机种子 | API request body |
| `reasoningEffort` | 推理深度 | API request body |
| `verbosity` | 输出详细度 | 待定 |
| `streaming` | 流式输出 | ChatService（已支持？） |

## 五、参考来源

- 粟粟的研究报告：`/Users/susu/Downloads/deep-research-report.md`
- SillyTavern 源码：`src/endpoints/backends/chat-completions.js`（convertClaudeMessages, sendClaudeRequest）
- SillyTavern 前端：`public/scripts/openai.js`（postProcessPrompt, mergeMessages）
- OpenAI Chat Completions API 文档
- Anthropic Messages API 文档 + Errors 文档（prefill 限制）
- 我们的 PromptAssembler.swift、Preset.swift、ChatService.swift

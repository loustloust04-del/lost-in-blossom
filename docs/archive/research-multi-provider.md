# Research: 多 API 提供商支持

> CC 深读现有代码 + SillyTavern 源码，2026-03-24

---

## 1. 现有架构

### ChatService（Services/ChatService.swift）

单一类，硬编码 OpenRouter：

- **endpoint**: 硬编码 `https://openrouter.ai/api/v1/chat/completions`
- **API key**: 从 UserDefaults 读 `"openrouter-api-key"`
- **认证**: `Bearer {key}`，附带 `HTTP-Referer` 和 `X-Title` header（OpenRouter 特有）
- **请求格式**: OpenAI Chat Completions 格式 `{ model, messages: [{role, content}], stream: true }`
- **响应解析**: SSE，解析 `data: {"choices":[{"delta":{"content":"..."}}]}` 和 `data: [DONE]`
- **状态管理**: `@Observable`，`isStreaming` / `streamingContent` / `error`
- **网络层**: URLSessionDataDelegate，自己做 SSE 逐行解析

### 模型（ChatModel）

硬编码 8 个，用 OpenRouter 格式的 model ID（`anthropic/claude-sonnet-4`）。没有提供商概念。

### 调用链

```
CardFlowView.ChatInputBar
  → 拼 model string（从 AppStorage "selectedChatModel" 或 profile.preferredModel）
  → viewModel.sendMessage(text, model:, systemPrompt:, context:)
    → chatService.sendStreaming(messages:, model:, systemPrompt:, ...)
      → URLRequest → openrouter.ai
```

model string 在 3 个地方传入 sendStreaming：sendMessage、regenerate、editAndResend。都是一样的调用方式。

### 影响范围

| 文件 | 依赖 ChatService 的方式 |
|------|------------------------|
| ConversationViewModel | `var chatService = ChatService()` 直接持有；调 `chatService.sendStreaming()` 和 `.cancel()`；读 `.isStreaming` |
| CardFlowView | 读 `viewModel.chatService.isStreaming`；ChatInputBar 拼 model string |
| CardFlowView (BubbleView) | `onRegenerate` / `onEdit` 闭包里拼 model string |
| SettingsView | API key 输入/保存（UserDefaults "openrouter-api-key"） |
| Profile | `preferredModel: String`（存 OpenRouter model ID） |

---

## 2. 目标 API 对比

### OpenAI Chat Completions（OpenAI / OpenRouter / DeepSeek / Groq / xAI 共用）

```
POST https://api.openai.com/v1/chat/completions
Authorization: Bearer {key}
Content-Type: application/json

{
  "model": "gpt-4o",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "stream": true
}

SSE: data: {"choices":[{"delta":{"content":"token"}}]}
SSE: data: [DONE]
```

OpenRouter、DeepSeek、Groq、xAI 都兼容这个格式，只是 baseURL 和 header 不同。

### Anthropic Messages API（Claude 原生）

```
POST https://api.anthropic.com/v1/messages
x-api-key: {key}
anthropic-version: 2023-06-01
Content-Type: application/json

{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 4096,
  "system": "...",           ← system 是顶级字段！不在 messages 里
  "messages": [
    {"role": "user", "content": "..."}
  ],
  "stream": true
}

SSE 事件格式完全不同：
event: message_start
event: content_block_start
event: content_block_delta    ← {"type":"content_block_delta","delta":{"type":"text_delta","text":"token"}}
event: content_block_stop
event: message_delta
event: message_stop
```

关键差异：
1. **认证**：`x-api-key` header，不是 `Bearer`
2. **必须字段**：`max_tokens` 是必填的（OpenAI 格式可选）
3. **system prompt**：顶级字段，不在 messages 数组里
4. **SSE 事件**：有 event type，delta 在 `delta.text` 不在 `delta.content`
5. **model ID**：`claude-sonnet-4-20250514` 而不是 `anthropic/claude-sonnet-4`
6. **thinking**：支持 extended thinking（`thinking` content block type）

### Google Gemini（后续）

完全不同的格式，后续再研究。当前不在 P0 范围。

---

## 3. 需要改什么

### 核心重构：ChatService → Protocol + 多实现

```swift
protocol ChatProvider {
    var isStreaming: Bool { get }
    var streamingContent: String { get }
    var error: String? { get }

    func sendStreaming(
        messages: [(role: String, content: String)],
        model: String,
        systemPrompt: String?,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    )
    func cancel()
}
```

实现：
- `OpenAIProvider`：处理 OpenAI / OpenRouter / DeepSeek / Groq / xAI（只是 baseURL / headers / apiKey 不同）
- `AnthropicProvider`：处理 Claude 原生 API（完全不同的请求格式和 SSE 解析）

### 提供商数据模型

```swift
enum ProviderType: String, Codable {
    case openaiCompatible  // OpenAI / OpenRouter / DeepSeek / Groq / xAI / Custom
    case anthropic         // Claude 原生
    // case google         // 后续
}

struct APIProvider: Identifiable, Codable {
    let id: String         // "openrouter", "anthropic", "openai", ...
    let name: String       // "OpenRouter", "Anthropic (Claude)", ...
    let type: ProviderType
    let baseURL: String    // 默认 endpoint
    var apiKey: String     // 存 UserDefaults per provider
    var isEnabled: Bool
    var models: [ChatModel]  // 可用模型列表
}
```

### 内置提供商列表

| id | name | type | baseURL | 模型来源 |
|----|------|------|---------|---------|
| openrouter | OpenRouter | openaiCompatible | openrouter.ai/api/v1 | 动态 /models |
| anthropic | Anthropic | anthropic | api.anthropic.com/v1 | 硬编码 |
| openai | OpenAI | openaiCompatible | api.openai.com/v1 | 动态 /models |
| deepseek | DeepSeek | openaiCompatible | api.deepseek.com/v1 | 硬编码 |
| groq | Groq | openaiCompatible | api.groq.com/openai/v1 | 动态 /models |
| xai | xAI (Grok) | openaiCompatible | api.x.ai/v1 | 硬编码 |

### 模型列表

按提供商分组，友好名称：

```
── Anthropic ──
  Claude Opus 4.6        (claude-opus-4-6)
  Claude Sonnet 4.5       (claude-sonnet-4-5)
  Claude Haiku 4.5        (claude-haiku-4-5)
── OpenAI ──
  GPT-4o                  (gpt-4o)
  GPT-4o Mini             (gpt-4o-mini)
  o3                      (o3)
── OpenRouter ──
  (动态加载)
...
```

---

## 4. 风险点

1. **Anthropic SSE 格式完全不同** — 不能复用现有的 `processSSEData`，需要独立的解析器处理 event types 和 content blocks
2. **model ID 格式不同** — OpenRouter 用 `anthropic/claude-sonnet-4`，Anthropic 原生用 `claude-sonnet-4-20250514`。Profile 里存的 preferredModel 格式需要跟提供商匹配
3. **迁移** — 现有用户的 `openrouter-api-key` 和 `selectedChatModel`（AppStorage）需要平滑迁移
4. **Settings UI 膨胀** — 6+ 个提供商的 API key 管理，不能把设置页撑爆
5. **哪个 key 发哪个请求** — 用户选了 `claude-sonnet-4-5` 模型，系统需要知道用 Anthropic key 还是 OpenRouter key。模型到提供商的映射关系需要明确

---

## 5. 酒馆怎么解决 #5（模型到提供商映射）

酒馆的做法：**用户先选提供商（API），再在该提供商下选模型**。不是一个大列表混在一起。

```
[API 选择器: Chat Completion ▾]
[Chat Completion Source: Claude ▾]  ← 选提供商
[Model: claude-sonnet-4-5 ▾]       ← 在该提供商下选模型
[API Key: ●●●●●●]
```

这解决了歧义：同一个模型名（如 claude-sonnet-4）可以通过 OpenRouter 调也可以直连 Anthropic 调，取决于用户选的 source。

### 我们的方案

简化版：模型选择器按提供商分组，选模型时自动确定用哪个提供商。如果模型在多个提供商都存在（如 Claude 在 OpenRouter 和 Anthropic 都有），优先用有官 key 的直连提供商。

```
模型选择器:
── Anthropic (直连) ──    ← 有 key 才显示
  Claude Sonnet 4.5
── OpenAI (直连) ──       ← 有 key 才显示
  GPT-4o
── OpenRouter ──          ← 有 key 才显示
  (所有模型)
```

选模型时，提供商信息跟着走。不存在歧义。

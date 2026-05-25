---
name: chat-feature-first-principles
description: First-principles analysis of what the Memory Palace chat feature needs - gaps, design decisions, and priorities
type: project
---

## Phase 1 Chat Feature - First Principles Analysis (2026-03-24)

### What is the chat doing?
Memory Palace started as a conversation VIEWER (imported ChatGPT/Claude history). Phase 1 adds the ability to CHAT directly. This creates a fundamental tension: the app has both read-only historical conversations AND live interactive ones.

### Phase 1 Implementation Status (2026-03-24):

- [x] OpenRouter API (ChatService + SSE streaming)
- [x] 聊天输入栏 + 新建对话
- [x] 模型切换（Picker in input bar，AppStorage 持久化）
- [x] Thinking 块折叠（[thinking]...[/thinking] -> DisclosureGroup）
- [x] Enter=换行, Cmd+Enter=发送
- [x] 重新生成（assistant 气泡，创建树分支）
- [x] 消息编辑（user 气泡，创建新分支 + 自动发送）
- [x] 自动命名（首条 user 消息前40字符）
- [x] 上下文限制（最近40条消息）
- [x] ContentCleaner cache key 修复（content 变化时失效）
- [x] 动态楼层系统（Profile CRUD + UserDefaults）

---

## Phase 1.5 需求列表 — 多提供商 + 模型管理（从酒馆学到的）

### 酒馆架构核心洞察：

1. **每个提供商是独立的**：不同的 endpoint URL、认证方式、请求格式、模型列表。不能指望一个 OpenRouter 统一一切——用户有官方 key 就应该直连。
2. **模型列表应该动态获取**：OpenRouter/OpenAI/Groq 等都有 `/models` 端点。Claude 没有（硬编码）。DeepSeek 没有（硬编码）。
3. **酒馆有后端代理**，我们没有。我们是纯客户端，API key 存本地，直连各家 API。这意味着：
   - 不能做服务端 secret 管理
   - 需要处理各家不同的 CORS 策略（macOS app 没有 CORS 问题，这是优势）
   - 直连 Anthropic Messages API 的格式跟 OpenAI 不同

### 需求清单：

#### A. 多提供商支持（核心）

| 提供商 | API 格式 | Endpoint | 模型列表 | 优先级 |
|--------|---------|----------|---------|--------|
| OpenRouter | OpenAI 兼容 | openrouter.ai/api/v1 | 动态 /models | 已完成 |
| Anthropic (官key) | Messages API（不同格式！） | api.anthropic.com/v1 | 硬编码 | P0 |
| OpenAI (官key) | OpenAI Chat Completion | api.openai.com/v1 | 动态 /models | P0 |
| Google (Gemini) | Gemini API（不同格式） | generativelanguage.googleapis.com | 硬编码 | P1 |
| DeepSeek | OpenAI 兼容 | api.deepseek.com | 硬编码 | P1 |
| Groq | OpenAI 兼容 | api.groq.com/openai/v1 | 动态 /models | P2 |
| xAI (Grok) | OpenAI 兼容 | api.x.ai/v1 | 硬编码 | P2 |
| Custom (自定义) | OpenAI 兼容 | 用户填 URL | 动态 /models | P2 |

#### B. Provider 数据模型

```
Provider {
    id: String          // "openrouter", "anthropic", "openai", ...
    name: String        // "OpenRouter", "Anthropic (Claude)", ...
    type: enum          // .openaiCompatible, .anthropicMessages, .googleGemini
    baseURL: String     // 默认 endpoint，可自定义
    apiKey: String      // 存 UserDefaults
    models: [Model]     // 可用模型列表
    isEnabled: Bool     // 用户是否启用
}
```

#### C. 模型管理

- OpenAI 兼容提供商：调 `/models` 端点动态拉取
- Anthropic：硬编码完整列表（claude-opus-4-6, claude-sonnet-4-5, claude-haiku-4-5, 等）
- 用户可以手动输入模型 ID（兜底）
- 模型显示友好名称（"Claude Sonnet 4.5" 而不是 "claude-sonnet-4-5"）
- 按提供商分组显示

#### D. Anthropic Messages API 适配

酒馆用 `sendClaudeRequest()` 专门处理 Claude，因为格式完全不同：
- 请求体：`{ model, messages, system, max_tokens, stream }` （system 是顶级字段不在 messages 里）
- messages 格式：`{ role, content: [{ type: "text", text: "..." }] }`（content 是数组不是字符串）
- 响应体：`{ content: [{ type: "text", text: "..." }] }` + thinking blocks
- SSE 事件格式不同：`content_block_delta` 而不是 `choices[0].delta.content`
- 需要 `anthropic-version` header
- 支持 extended thinking（`claude-opus-4-6` 等）

#### E. 设置页 API 管理

- 每个提供商一行：名称 + API key 输入框 + 启用/禁用开关
- 已填 key 的提供商自动启用
- "测试连接" 按钮（可选）
- 模型选择器按提供商分组

#### F. UI 改进

- 模型选择器改为自定义样式（不用系统 Picker，太丑）
- 按提供商分组：`Anthropic > Claude Sonnet 4.5, Claude Haiku 4.5...`
- 显示友好名称而不是 API ID
- 搜索/过滤模型（模型多了以后需要）

### 实现优先级：

**第一步（最小可用）**：
1. 定义 Provider 和 ProviderType 数据模型
2. ChatService 重构为 protocol，OpenAI 兼容实现 + Anthropic 实现
3. 设置页多 API key 管理
4. 模型选择器按提供商分组 + 友好名称

**第二步（扩展）**：
5. 动态模型列表（/models 端点）
6. Google Gemini 适配
7. 自定义提供商（用户填 URL）
8. 模型搜索/过滤

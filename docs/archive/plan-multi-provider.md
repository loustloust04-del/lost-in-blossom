# Plan: 多 API 提供商支持

> 基于 research-multi-provider.md，CC 制定，粟粟批注

---

## 目标

从"只能用 OpenRouter"变成"支持多家 API 直连 + 模型按提供商分组选择"。

## 文件变更总览

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | Models/APIProvider.swift | Provider + ProviderType 数据模型 |
| 重写 | Services/ChatService.swift | 拆成 protocol + OpenAIProvider + AnthropicProvider |
| 修改 | ViewModels/ConversationViewModel.swift | ChatService → 动态 provider 选择 |
| 修改 | Views/CardFlowView.swift | 模型选择器按提供商分组 |
| 修改 | Views/SettingsView.swift | 多 API key 管理 |
| 修改 | MemoryPalaceApp.swift | Profile.preferredModel 迁移 |

---

## Checklist

### Step 1: 数据模型（APIProvider.swift）

- [x] 1.1 定义 `ProviderType` enum（openaiCompatible, anthropic）
- [x] 1.2 定义 `APIProvider` struct（id, name, type, baseURL, models, headers 模板）
- [x] 1.3 定义 `ProviderModel` struct（id, name, providerId）替代现有 ChatModel
- [x] 1.4 内置提供商列表（6 家）+ 每家的硬编码模型列表
- [x] 1.5 `ProviderManager` 管理 API key 存取（UserDefaults per provider）、启用状态、当前可用模型列表
- [x] 1.6 Build 验证

### Step 2: ChatService 重构

- [x] 2.1 定义 `BaseChatProvider` 基类（sendStreaming / cancel / isStreaming / streamingContent / error）
- [x] 2.2 `OpenAICompatibleProvider` — 从现有 ChatService 提取，参数化 baseURL / apiKey / headers
- [x] 2.3 `AnthropicProvider` — Anthropic Messages API 格式，独立 SSE 解析（event type + content_block_delta）
- [x] 2.4 `ProviderRouter` — 根据选中模型的 providerId 路由到正确的 provider 实例
- [x] 2.5 删除旧 ChatModel（被 ProviderModel 替代）
- [x] 2.6 Build 验证

### Step 3: ViewModel 适配

- [x] 3.1 ConversationViewModel: `chatService` 改为 `ProviderRouter` 类型
- [x] 3.2 sendMessage / regenerate / editAndResend: model 参数改为 `ProviderModel`（带 providerId）
- [x] 3.3 Build 验证

### Step 4: 模型选择器 UI

- [x] 4.1 CardFlowView ChatInputBar: 模型 Picker 改为按提供商分组（只显示有 key 的提供商）
- [x] 4.2 模型显示友好名称
- [x] 4.3 选中模型存储改为 `providerId/modelId` 组合
- [x] 4.4 BubbleView 的 onRegenerate / onEdit 传 ProviderModel 而不是 model string
- [x] 4.5 Build 验证

### Step 5: 设置页 API 管理

- [x] 5.1 SettingsView: 替换单一 OpenRouter key 输入为多提供商列表
- [x] 5.2 每个提供商一行：状态点 + 名称 + SecureField + 保存按钮
- [x] 5.3 有 key 的提供商显示绿点，无 key 的灰色
- [x] 5.4 Build 验证

### Step 6: 迁移 + 清理

- [x] 6.1 迁移现有 `openrouter-api-key`（UserDefaults）到新的 per-provider 存储（在 SettingsView onAppear）
- [x] 6.2 删除旧的 KeychainHelper.swift（不再使用）
- [x] 6.3 Final build 通过
- [x] 6.4 Commit `b6357ec` + push to feature/multi-provider

---

## 设计决策

### 模型到提供商的映射

不做歧义解析。每个模型都带 `providerId`，选模型就选定了提供商。模型选择器按提供商分组显示，只显示有 API key 的提供商的模型。

### Anthropic SSE 解析

独立实现，不复用 OpenAI 的 parseChunk。Anthropic SSE 有 event type 行（`event: content_block_delta`），delta 格式是 `{"type":"text_delta","text":"..."}` 而不是 `{"choices":[{"delta":{"content":"..."}}]}`。

### max_tokens

Anthropic 必填 `max_tokens`。默认 4096，后续可配置。OpenAI 兼容的不填（让 API 自己决定）。

### Provider 配置不存 Profile

API key 是全局的（同一个 Anthropic key 用于所有楼层），不跟 Profile 走。Profile 只存 preferredModel（默认模型选择）。

---

## 不做的事

- ❌ 动态 /models 拉取（P1，不在本轮）
- ❌ Google Gemini 适配（格式太不同，单独做）
- ❌ 自定义提供商 URL（P2）
- ❌ 模型搜索/过滤（模型不多时不需要）
- ❌ 测试连接按钮（做完核心再说）

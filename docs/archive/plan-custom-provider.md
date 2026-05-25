# Plan: 自定义 API 提供商

## 目标

让用户可以**增删改提供商**和**自定义模型列表**，告别硬编码 6 家的限制。
支持任意 OpenAI 兼容端点（中转站、ollama、SiliconFlow 等）。

## 现状分析

### 当前架构
```
APIProvider (struct, 硬编码)
  ├── .builtIn: [APIProvider] = [anthropic, openai, openrouter, deepseek, groq, xai]
  ├── id, name, type, baseURL, extraHeaders, models[]
  └── 完全不可变

ProviderManager (@Observable)
  ├── let providers = APIProvider.builtIn  ← 铁板
  ├── apiKey(for:) / setApiKey()  ← UserDefaults
  └── availableModels / enabledProviders

ProviderRouter
  ├── switch provider.type { .openaiCompatible → OpenAI; .anthropic → Anthropic }
  └── sendStreaming() / sendNonStreaming()
```

### 影响范围
- `APIProvider.swift` — 模型定义 + ProviderManager
- `ChatService.swift` — ProviderRouter 路由
- `SettingsView.swift` — API tab UI
- `CardFlowView.swift` — 模型选择 picker（`ModelPickerPopover`）
- `ConversationViewModel.swift:655` — sendMessage 调用

### 不动的部分
- `BaseChatProvider` / `OpenAICompatibleProvider` / `AnthropicProvider` — 协议实现不需要改
- `ProviderRouter.sendStreaming()` — switch 逻辑已经足够，只要 type 对就行
- Preset / Prompt 系统 — 不受影响

---

## 设计方案

### 核心思路：把 `APIProvider` 从静态改成动态

不引入新模型类，直接让 `APIProvider` 和 `ProviderModel` 支持持久化 + 动态增删。

### 数据持久化

用 UserDefaults JSON（和 apiKey 存储方式一致，不引入新依赖）：

```swift
// UserDefaults key: "customProviders"
// Value: JSON array of APIProvider
[
  {
    "id": "my-ollama",
    "name": "本地 Ollama",
    "type": "openaiCompatible",
    "baseURL": "http://localhost:11434/v1",
    "extraHeaders": {},
    "models": [
      {"providerId": "my-ollama", "modelId": "llama3.2", "name": "Llama 3.2"}
    ]
  }
]
```

### 改动清单

#### 1. `APIProvider.swift` — 让 Provider 可序列化 + 动态管理

- [ ] `APIProvider` 加 `Codable` conformance
- [ ] `ProviderModel` 加 `Codable` conformance
- [ ] `ProviderType` 已经是 `Codable`，不用改
- [ ] 新增 `isBuiltIn: Bool` 字段区分内置 vs 自定义
- [ ] 新增 `isEnabled: Bool` 字段（替代"有 key = 启用"的隐式逻辑）

#### 2. `ProviderManager` — 从 `let` 改成动态

- [ ] `providers` 从 `let` 改成 `private(set) var`
- [ ] 初始化时：加载内置 + 从 UserDefaults 读取自定义提供商，合并
- [ ] `addProvider(_ provider: APIProvider)` — 追加 + 持久化
- [ ] `updateProvider(_ provider: APIProvider)` — 更新 + 持久化
- [ ] `removeProvider(id: String)` — 只允许删自定义的
- [ ] `addModel(to providerId: String, model: ProviderModel)` — 给提供商加模型
- [ ] `removeModel(from providerId: String, modelId: String)` — 删模型
- [ ] 内置提供商的**模型列表**也允许用户追加自定义模型（overlay 机制）
- [ ] 私有方法 `persistCustomProviders()` — JSON → UserDefaults

#### 3. `SettingsView.swift` API tab — 加"添加提供商" UI

- [ ] API tab 底部加"+ 添加自定义提供商"按钮
- [ ] 点击弹 sheet：`AddProviderSheet`
  - 名称（必填）
  - 类型 Picker（OpenAI 兼容 / Anthropic Messages）
  - Base URL（必填，placeholder 示例）
  - API Key
  - 额外 Header（可选，key-value 对）
- [ ] 已有提供商卡片加"编辑"按钮（自定义的可改名/改 URL；内置的只能改 key）
- [ ] 自定义提供商卡片加"删除"按钮（内置不可删）
- [ ] 每个提供商的模型列表加"+ 添加模型"按钮
  - 输入 model ID + 显示名称
- [ ] 加"测试连接"按钮（发一个 minimal 请求验证 key + endpoint）

#### 4. `CardFlowView.swift` ModelPickerPopover — 适配动态列表

- [ ] 目前已经从 `providerManager.availableModels` 读，动态后自动兼容
- [ ] 检查 `@AppStorage("selectedChatModel")` 在删除模型后的 fallback 逻辑

#### 5. 连接测试功能

- [ ] `ProviderManager` 加 `testConnection(providerId:) async -> Result<String, Error>`
- [ ] OpenAI 兼容：`GET /models` 或 `POST /chat/completions` with minimal body
- [ ] Anthropic：`POST /messages` with minimal body
- [ ] UI 上显示绿勾/红叉 + 错误信息

---

## 不做的事（控制范围）

- **不做**多 key 轮转（kelivo 有但我们暂不需要）
- **不做**每提供商独立代理（等后续需求）
- **不做** Google Gemini 原生协议（走 OpenRouter 或中转站即可）
- **不做**模型自动发现（`/models` endpoint 拉列表），后续可加
- **不做** Keychain 迁移（继续用 UserDefaults，等安全需求再改）

---

## 文件改动汇总

| 文件 | 改动量 | 内容 |
|------|--------|------|
| `APIProvider.swift` | 中 | Codable + isBuiltIn + isEnabled |
| `ProviderManager` (同文件) | 大 | 动态 providers + CRUD + 持久化 |
| `SettingsView.swift` | 大 | AddProviderSheet + 编辑/删除 + 添加模型 + 测试连接 |
| `CardFlowView.swift` | 小 | 检查 fallback 逻辑 |
| `ChatService.swift` | 无 | ProviderRouter 不需要改（switch type 已覆盖） |
| `ConversationViewModel.swift` | 无 | 不需要改 |

---

## 执行顺序

1. **Step 1**: APIProvider + ProviderManager 改造（数据层）
2. **Step 2**: Build 验证编译通过 + 现有功能不回归
3. **Step 3**: SettingsView API tab UI（添加/编辑/删除提供商）
4. **Step 4**: Build + MobAI 验证设置页
5. **Step 5**: 添加模型 UI + 连接测试
6. **Step 6**: Build + 端到端测试（添加自定义提供商 → 选模型 → 发消息）
7. **Step 7**: commit + push

---

## 验证标准

- [ ] 内置 6 家提供商功能不变
- [ ] 能添加新提供商（名称 + 类型 + baseURL + key）
- [ ] 新提供商出现在设置页和模型选择器里
- [ ] 能给提供商手动添加模型
- [ ] 能删除自定义提供商
- [ ] 连接测试能跑通（至少对有 key 的提供商）
- [ ] App 重启后自定义提供商还在
- [ ] macOS + iOS 都能用

# Plan: API Tab 重设计（酒馆风格）

## 目标

把 API tab 从"一堆 Provider 卡片堆叠"改成酒馆式"**单页顺序流**"：

选提供商 → 填 Key → 自动拉模型 → 选模型 → 测试连接

## 对比

| | 酒馆 | 记忆宫殿现状 | 目标 |
|--|------|------------|------|
| 提供商选择 | 下拉菜单，一次看一个 | 6+ 张卡片全部展示 | 下拉菜单 |
| API Key | 只显示当前 source 的 | 每张卡片都有 | 只显示当前的 |
| 模型列表 | 下拉选择，自动拉取 | 折叠面板，手动拉取 | 下拉选择，自动拉取 |
| 测试 | "Test Message" 按钮 | 藏在卡片里 | 明显按钮 |
| 自定义 | "Custom" source + reverse proxy | 添加提供商 sheet | 下拉选"自定义"+ URL 输入框 |

## UI 布局（从上到下）

```
┌─────────────────────────────────────┐
│  API 提供商   [▼ OpenRouter      ]  │  ← Picker 下拉
├─────────────────────────────────────┤
│  API Key      [sk-or-...........] [保存] │
├─────────────────────────────────────┤
│  ⚡ 连接成功   [测试连接]           │  ← 状态 + 按钮
├─────────────────────────────────────┤
│  模型         [▼ claude-sonnet-4 ]  │  ← 自动拉取填充
├─────────────────────────────────────┤
│  ▸ 高级选项（展开后显示）            │
│    Base URL   [https://openrout...]  │  ← 预填，可改
│    额外 Header                       │
│    + 添加自定义提供商                 │
│    + 手动添加模型                     │
└─────────────────────────────────────┘
```

## 提供商列表

下拉菜单内容（内置 + 用户添加的自定义）：

**内置**：
- Anthropic (Messages API)
- OpenAI
- OpenRouter
- DeepSeek
- Groq
- xAI
- SiliconFlow
- 通义千问 (DashScope)
- 智谱 (GLM)
- 豆包 (Volcengine)
- Google Gemini
- Moonshot / Kimi
- Ollama (本地)

**分隔线**

- 用户添加的自定义提供商...
- ＋ 添加自定义提供商

## 数据变化

### 不需要改的
- `APIProvider` struct / `ProviderManager` — 已经支持动态 CRUD
- `ProviderRouter` / `ChatService` — 不受影响
- `CardFlowView` 模型选择器 — 从 `providerManager.availableModels` 读

### 需要改的

**1. `APIProvider.swift`**：
- 扩充 `builtIn` 列表，加入 SiliconFlow、通义千问、智谱、豆包、Gemini、Moonshot、Ollama
- 每个内置提供商的 `baseURL` 和 `models` 都预填好
- 去掉 `ProviderTemplate`（不再需要，提供商本身就是模板）

**2. `SettingsView.swift` — API tab 重写**：
- 去掉 `ForEach(providers)` 卡片列表
- 改成单页流：
  - `@State var selectedProviderId: String` — 当前选中的提供商
  - 一个 Picker 选提供商
  - 一个 SecureField 填 Key
  - 一个状态行（连接状态 + 测试按钮）
  - 一个 Picker 选模型（从拉取的列表填充）
  - 一个折叠"高级选项"（Base URL、Header、手动加模型）
- `@AppStorage("selectedChatModel")` 绑定模型选择

**3. 去掉 `AddProviderSheet` 的大网格预设**：
- 改成：高级选项里一个"添加自定义提供商"按钮
- 或者直接在 Picker 底部加"+ 自定义"选项

## 模型拉取逻辑

1. 用户选提供商 → 检查是否有 Key
2. 有 Key → 自动调 `fetchModels()` → 模型下拉框填充
3. 无 Key → 显示"请先输入 API Key"
4. Key 变更保存后 → 重新拉取模型
5. 拉取失败 → 显示错误，允许手动输入模型 ID

### 关键：全量拉取，不过滤

OpenRouter 等中转站有**几百个模型**，必须全部显示。
现在的 `fetchModels()` 过滤掉了 embed/tts/whisper 等，这个过滤保留（非聊天模型确实没用），但**不能过滤任何聊天模型**。

### 模型选择器设计（参考酒馆 1.7）

因为模型可能很多（OpenRouter 300+），普通 Picker 装不下。需要：

- **搜索框**：输入关键词实时过滤（如输入 "claude" 只显示 Claude 相关）
- **按 vendor 分组**：OpenRouter 模型 ID 格式是 `vendor/model`（如 `anthropic/claude-sonnet-4`），按 `/` 前的 vendor 名分组显示
- **排序**：按名称字母排序
- **可滚动列表**：ScrollView 里的列表，不是系统 Picker
- **选中高亮**：当前选中的模型有明显标记

UI 大致：
```
模型  [🔍 搜索模型...]
┌─────────────────────────┐
│ ▸ anthropic              │
│   Claude Sonnet 4.5      │  ✓
│   Claude Sonnet 4        │
│   Claude Haiku 4.5       │
│ ▸ openai                 │
│   GPT-4o                 │
│   GPT-4.1                │
│ ▸ google                 │
│   Gemini 2.5 Pro         │
│   ...                    │
└─────────────────────────┘
```

对于非中转站（如直连 Anthropic），模型少，分组没必要，直接平铺。

## 执行步骤

- [ ] Step 1: 扩充内置提供商列表（加 SiliconFlow 等 7 家）
- [ ] Step 2: 重写 API tab UI（单页流）
- [ ] Step 3: 模型 Picker + 自动拉取绑定
- [ ] Step 4: 高级选项折叠面板（Base URL 编辑、手动加模型、添加自定义提供商）
- [ ] Step 5: Build + 验证
- [ ] Step 6: commit + push

## 验证标准

- [ ] 选提供商 → 自动显示对应 Key 输入框
- [ ] 填 Key 保存 → 自动拉取模型列表
- [ ] 模型下拉能选择 → 选了之后聊天页能用
- [ ] 内置 13 家提供商都有正确的 baseURL
- [ ] 自定义提供商能添加和使用
- [ ] 测试连接能显示结果
- [ ] macOS + iOS 都能用

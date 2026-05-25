# Research: API 系统差距分析 + 设置页 iOS 审计

> 审计日期: 2026-04-10

## 一、API 系统对比

### 记忆宫殿现状

**架构**：`APIProvider.swift` 硬编码 6 家提供商，不可扩展。

```
APIProvider.builtIn = [anthropic, openai, openrouter, deepseek, groq, xai]
```

- `ProviderManager.providers` 是 `let`（不可变数组）
- 无"添加自定义提供商"功能
- 模型列表硬编码在代码里，不可动态刷新
- API Key 存 UserDefaults（明文）
- 无 baseURL 自定义、无代理、无多 key 轮转

**关键短板**：
1. 不能添加新提供商（比如 SiliconFlow、OneAPI、本地 ollama）
2. 不能自定义 baseURL（比如用中转站）
3. 模型列表静态，新模型要改代码重编译
4. 没有连接测试 / 验证功能
5. 没有 Google Gemini 原生支持（只能走 OpenRouter）

---

### kelivo 的做法（Flutter）

**文件**: `kelivo/lib/core/providers/settings_provider.dart`

- `ProviderConfig` 完整配置类（~50 个字段）：
  - `id`, `name`, `apiKey`, `baseUrl`, `providerType`（openai/google/claude）
  - `chatPath` — 可自定义 API 路径（如 `/chat/completions`）
  - `modelOverrides` — 每模型独立配置（apiModelId、type、abilities）
  - `proxyEnabled/Host/Port` — 每提供商独立代理
  - `multiKeyEnabled` + `apiKeys[]` — 多 key 轮转
  - `avatarType/Value` — 自定义提供商图标
- 提供商是**用户可增删**的（`ensureProviderConfig`、`removeProviderConfig`）
- 默认 seed 4 家（KelivoIN、Tensdaq、SiliconFlow、AIhubmix），用户可加任意多
- 3 种 Provider Kind：`openai` / `google` / `claude`
  - OpenAI 类用 `/chat/completions`（支持自定义 chatPath）
  - Google 类支持 Gemini API + Vertex AI（service account JSON）
  - Claude 类用 Messages API
- 实际 API 请求走 `Dio`（HTTP client），支持流式 SSE

**对记忆宫殿的启发**：
- 提供商应该是**动态可配置的**，不是编译时硬编码
- 核心字段：`id`, `name`, `type`, `baseURL`, `apiKey`, `models[]`
- 至少支持 "OpenAI 兼容" + "Anthropic Messages" 两种协议
- 用户能自定义 baseURL = 支持任何中转站 / 本地 ollama
- 模型列表应可手动输入或远程拉取

---

### TavernHeadless 的做法（TypeScript / Vercel AI SDK）

**文件**: `packages/core/src/llm/`

- `ProviderRegistry` — 注册制：
  ```ts
  register(config: ProviderConfig): void  // 注册
  unregister(providerId: string): void    // 移除
  getModel(providerId, modelId): LanguageModel
  registerFactory(type, factory): void     // 自定义类型扩展
  ```
- 6 种内置 type：`openai`, `anthropic`, `google`, `deepseek`, `xai`, `openai-compatible`
- OpenAI / DeepSeek / xAI / openai-compatible 全复用同一个 `createOpenAIFactory`
- `ProviderConfig` 简洁：`id`, `type`, `apiKey?`, `baseURL?`, `options?`
- 流式用 Vercel AI SDK 的 `stream()` + callbacks（`onChunk`, `onFinish`, `onError`）
- 多实例架构：`narrator` / `memory` / `director` / `verifier` 可各自绑不同模型

**对记忆宫殿的启发**：
- "OpenAI 兼容" 是万能桶 — 大部分中转站都是这个协议
- 注册制比硬编码灵活得多
- 可考虑类似的 `ProviderFactory` 模式

---

## 二、设置页 iOS 审计（MobAI 截图）

### 通用 tab
- **楼层选择器**：正常工作
- **气泡标签**："确认"按钮关闭整个设置 sheet — 应改为只保存不关闭
- **字体选择**：5 个预设字体（系统默认、苹方、宋体、楷体、仿宋）
  - 功能正常（可选中），但预览文字视觉差异不明显
  - iOS 上 "宋体"、"楷体"、"仿宋" 字体名可能不对（macOS 用 `STSong`、`STKaiti`、`STFangsong`，iOS 可能需要 `Songti SC`、`Kaiti SC`、`STFangsong`）
  - **需验证**: 切换字体后聊天界面是否真的变了
- **聊天字号滑块**：显示 100%，滑块可拖，A+ / A- 按钮可点
- **导入字体按钮**：iOS 上被 `#if os(macOS)` 隐藏（正确，iOS 暂不支持自定义字体导入）

### Prompt tab
- **预设选择器**：Picker `.menu` 样式，弹出系统菜单，正常
- **模式切换**：简单/插槽/原始 segmented control，`width: 180`
  - iPhone 上稍挤但可用
- **采样参数**：4 个滑块（Temperature、上下文深度、Top P、Max Tokens）
  - 滑块可拖动，标签清晰
  - 预设快捷键（平衡/精确/创意）正常
- **Prompt 插槽列表**：
  - 9 个插槽可见，带拖拽图标和锁图标
  - chevron.right 展开（3x6pt，极小，但这是信息展开不是高频操作）
  - "添加"和"导入酒馆预设"按钮可见
  - **待测**: 酒馆预设导入是否真能工作

### API tab
- 6 家提供商卡片，各有 API Key 输入框 + 保存按钮 + 可用模型折叠列表
- **问题 1**：API Key 是 SecureTextField — 好
- **问题 2**：无"添加自定义提供商"入口
- **问题 3**：无 baseURL 可编辑 — 不能用中转站
- **问题 4**：无连接测试按钮
- **问题 5**：无模型手动输入（只能用硬编码列表）

### 记忆 tab
- 需进一步测试（MobAI rate limit）

### 导入导出 tab
- 需进一步测试（MobAI rate limit）

---

## 三、改进优先级

### P0：自定义提供商（核心功能缺失）

把 `APIProvider.builtIn` 从 `let` 改成可增删：

1. 新建 `CustomProvider` 持久化模型（JSON in UserDefaults 或 SwiftData）
2. 设置页 API tab 加"+ 添加提供商"按钮
3. 新提供商配置：名称、类型（OpenAI 兼容 / Anthropic）、Base URL、API Key
4. 模型列表：手动输入 model ID，不依赖硬编码
5. 保留 6 家内置作为默认模板，用户可修改 / 禁用

### P1：酒馆预设导入

需要研究 SillyTavern preset 格式（JSON），解析字段映射到 PromptSlot 系统。

### P2：设置页 UI 优化

- 气泡标签"确认"不应 dismiss 整个 sheet
- 字体名 iOS 适配验证
- API tab 加连接测试

---

## 四、kelivo 关键参考文件

| 文件 | 说明 |
|------|------|
| `lib/core/providers/settings_provider.dart:3574` | ProviderConfig 完整类定义 |
| `lib/core/providers/settings_provider.dart:3833` | defaultsFor() 内置模板 |
| `lib/core/providers/settings_provider.dart:1016` | 首次启动 seed 提供商 |
| `lib/core/services/api/chat_api_service.dart` | API 请求路由（按 ProviderKind 分发） |
| `lib/core/services/api/providers/` | 7 个 provider 实现 |
| `lib/core/services/api_key_manager.dart` | 多 key 轮转管理 |
| `lib/core/services/network/dio_http_client.dart` | HTTP 层（Dio） |

## 五、TavernHeadless 关键参考文件

| 文件 | 说明 |
|------|------|
| `packages/core/src/llm/types.ts` | ProviderConfig / ModelConfig / GenerationParams 类型 |
| `packages/core/src/llm/provider-registry.ts` | 注册制 ProviderRegistry |
| `packages/core/src/llm/llm-service.ts` | LLM 调用服务 |
| `packages/core/src/tools/preset-provider.ts` | 预设系统 |
| `packages/core/src/memory/` | 记忆系统（可参考） |

---

## 复盘（2026-04-11）

### 完成的改动

| Commit | 改动 | 效果 |
|--------|------|------|
| `f08482e` | APIProvider/ProviderModel 加 Codable；ProviderManager 动态 CRUD；AddProviderSheet + 连接测试 | 提供商可增删改，不再硬编码 |
| `811cda1` | 预设模板网格 + fetchModels() + ProviderCard「从 API 拉取」按钮 | 能自动拉模型列表 |
| `a63f0e3` | **API tab 重设计**：卡片堆叠 → 酒馆式单页流；内置提供商 6→13 家；可搜索模型列表按 vendor 分组 | 选提供商→填 Key→自动拉模型→搜索选模型 |
| `15b8c63` | 自定义提供商内联到 Picker；选"自定义"动态展示 名称+Base URL+手动输入模型 ID | 不再需要单独的 AddProviderSheet |
| `8a06644` | Picker 里 Divider → 文字分隔符 | 修复 iOS 白屏 |
| `9015f7c` | iOS ATS 豁免（NSAllowsArbitraryLoads） | 允许 HTTP 连接本地/内网服务 |
| `371ce10` | fetchModels/testConnection 自动补 /v1 路径 | 用户填 `https://example.com` 不带 /v1 也能正常工作 |

### 验证结果

- **OpenRouter**：模型拉取成功，几百个模型按 vendor 分组显示，搜索可用 ✅
- **自定义中转站**（dk.claudecode.love）：连接成功，模型拉取成功（5 个 Claude 模型）✅
- **聊天**：请求正确发出并收到响应（中转站返回 502/accounts exhausted 是上游问题，非 app 问题）✅
- **macOS + iOS** 编译通过 ✅
- **iOS 白屏** 已修复 ✅

### 迭代过程中的教训

1. **先 research 再动手**：第一轮直接写代码搞了个大网格预设，被粟粟否了。回头研究酒馆/kelivo 后才找到正确方向（酒馆式单页流）
2. **Picker 里不能放 Divider**：iOS 的 Picker 不支持 Divider 子元素，会导致整个页面白屏
3. **用户会忘记 /v1**：Base URL 自动补全 /v1 是必要的容错
4. **ATS 拦 HTTP**：iOS 默认禁止 HTTP，连本地 Ollama 都需要 ATS 豁免
5. **agent 被权限卡**：subagent 探索外部代码库会被权限限制，不如自己直接读

### 未完成 / 待后续

| 问题 | 优先级 | 备注 |
|------|--------|------|
| **酒馆预设导入** | P1 | SillyTavern JSON preset 解析 → PromptSlot 映射 |
| **模型选择器优化** | P2 | 当前搜索 OK 但可以加排序（按价格/上下文长度，参考酒馆 openRouterSortBy） |
| **ATS 精细化** | P2 | 上 App Store 前改成只豁免 localhost/局域网，不全开 |
| **聊天时切模型** | P2 | 当前 API tab 选模型后全局生效，可考虑每对话独立模型 |
| **API Key 安全** | P3 | 从 UserDefaults 迁移到 Keychain |
| **多 key 轮转** | P3 | kelivo 有此功能，我们暂不需要 |

### 设计决策

- **提供商下拉是唯一入口**：不需要单独的"添加提供商"流程，"自定义"就是下拉里的一个选项
- **选不同提供商，表单动态变化**：内置的只需 Key，自定义的多出 Base URL
- **保存自定义后变成固定选项**：保存后它就出现在下拉列表里，下次直接选
- **模型全量拉取不过滤聊天模型**：只过滤 embed/tts/whisper 等明确非聊天的
- **13 家内置提供商**：Anthropic、OpenAI、OpenRouter、DeepSeek、Groq、xAI、SiliconFlow、通义千问、智谱、豆包、Gemini、Moonshot、Ollama

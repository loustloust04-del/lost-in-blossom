# Research: API 管理方式对比（酒馆 vs kelivo vs 记忆宫殿）

> 审计日期: 2026-04-11

## 一、SillyTavern（酒馆）的做法

### 核心概念

酒馆有两层分离：**API Source（源）** 和 **反向代理（Reverse Proxy）**。

- **API Source**：固定枚举 23 种（`chat_completion_sources`），包括 OpenAI、Claude、OpenRouter、Groq、DeepSeek、SiliconFlow、自定义等
- **Reverse Proxy**：任何 source 都可以填一个 `reverse_proxy` URL，请求走用户指定的中转站
- **Custom**：专门有一个 `CUSTOM` source 类型，用户填 `custom_url`，万能兜底

### 模型列表

**自动拉取**：切换 API Source 后自动调 `getStatusOpen()` → 后端 `/api/backends/chat-completions/status` → 返回 `data[]` → `saveModelList()` 填入下拉框。

关键：**前端不直接调 OpenAI，一切走 ST 后端代理**。后端根据 source 类型决定请求哪个 `/models` 端点：
- OpenAI 系：`GET {baseUrl}/models`，解析 `data[].id`
- Anthropic：后端有 `/models` 端点（`x-api-key` header）
- 部分 source（Claude、AI21、VertexAI）**不自动拉模型**，只验证 key 有效

### API Key 存储

所有 key 存后端 `secrets.json`，前端用 `writeSecret()`/`readSecret()` 通过 HTTP API 读写。这是 C/S 架构。

### 我们的区别

记忆宫殿是**纯客户端 App**（没有后端服务器），所以：
- 不能走后端代理，必须前端直连 API
- Key 存本地 UserDefaults（目前明文，后续可迁 Keychain）
- 模型拉取也必须前端直接调 `/models`

---

## 二、kelivo 的做法（Flutter 客户端）

### Provider 管理

**文件**: `lib/core/providers/settings_provider.dart`

- `ProviderConfig` 是完整配置类（id, name, apiKey, baseUrl, providerType, models, modelOverrides...）
- 提供商是**用户可增删的**：`ensureProviderConfig(key)` / `setProviderConfig()` / `removeProviderConfig()`
- 三种 ProviderKind：`openai` / `google` / `claude`
- `_defaultBase(key)` 根据**名称关键词**自动推断 baseUrl（如名称含 "silicon" → `api.siliconflow.cn/v1`）

### 模型拉取

**文件**: `lib/core/providers/model_provider.dart`

```dart
class OpenAIProvider extends BaseProvider {
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final uri = Uri.parse('${cfg.baseUrl}/models');
    headers['Authorization'] = 'Bearer $key';
    // GET /models → data[].id
  }
}

class ClaudeProvider extends BaseProvider {
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final uri = Uri.parse('${cfg.baseUrl}/models');
    headers['x-api-key'] = key;
    headers['anthropic-version'] = '2023-06-01';
    // GET /models → data[].id + display_name
  }
}
```

- 用 `ModelRegistry.infer()` 自动推断模型能力（vision、tool、reasoning）
- 拉取后的模型列表和用户手动添加的模型**合并显示**
- 用户可以在 modelOverrides 里给模型配自定义参数

### UI 流程（推断）

1. 用户点"添加提供商"
2. 输入名称 → kelivo 根据名称自动推断 baseUrl（`_defaultBase`）
3. 输入 API Key
4. 保存后自动调 `listModels()` 拉取可用模型
5. 模型出现在模型选择器里

**关键差异**：kelivo 是**根据名称关键词自动推断 URL**，不需要用户手动填！

---

## 三、记忆宫殿现状的问题

粟粟指出的两个核心问题：

### 1. Base URL 需要自己填
现在添加提供商需要手动填完整 URL。虽然加了预设模板，但模板列表占了一大片空间。

**应该像 kelivo 那样**：用户只需选/输入提供商名称，URL 自动填好。预设不需要是显眼的大网格。

### 2. 模型不会自动拉取
"从 API 拉取"按钮藏在模型列表的折叠面板里，用户根本看不到。

**应该像酒馆那样**：保存 API Key 后**自动拉取模型列表**，不需要手动点。

---

## 四、改进方案

### 方案 A：名称驱动自动填 URL（学 kelivo）

添加提供商时：
1. 用户只需输入**名称**
2. 根据名称关键词匹配自动填入 baseUrl + type
3. 输入 API Key → 保存
4. 保存时自动调 `/models` 拉取模型
5. 预设模板改成下拉 Picker 或小标签，不要大网格

名称关键词映射（参考 kelivo `_defaultBase`）：
```
silicon/硅基 → https://api.siliconflow.cn/v1
openrouter → https://openrouter.ai/api/v1  
deepseek → https://api.deepseek.com/v1
ollama → http://localhost:11434/v1
qwen/通义/dashscope → https://dashscope.aliyuncs.com/compatible-mode/v1
zhipu/智谱/glm → https://open.bigmodel.cn/api/paas/v4
doubao/豆包/volces → https://ark.cn-beijing.volces.com/api/v3
aihubmix → https://aihubmix.com/v1
gemini/google → https://generativelanguage.googleapis.com/v1beta/openai
claude/anthropic → https://api.anthropic.com/v1 (type=anthropic)
moonshot/kimi → https://api.moonshot.cn/v1
xai/grok → https://api.x.ai/v1
groq → https://api.groq.com/openai/v1
```

### 方案 B：简化 UI

现在的 AddProviderSheet 预设网格太大了。改成：
- 顶部一个 Picker/Menu 选预设（一行搞定）
- 或者干脆不要预设选择器，靠名称自动推断
- 名称、URL、Key 三个字段就够了
- 额外 Header 默认折叠

### 模型拉取触发时机

1. **保存 Key 时自动拉取**（已实现但不明显）
2. **添加提供商保存时自动拉取**（已实现）
3. ProviderCard 上方加明显的"刷新模型"按钮（不要藏在折叠里）

---

## 五、参考文件索引

### SillyTavern
| 文件 | 说明 |
|------|------|
| `public/scripts/openai.js:174` | `chat_completion_sources` 枚举（23 种 API source） |
| `public/scripts/openai.js:331` | `custom_url` 设置绑定 |
| `public/scripts/openai.js:350` | `reverse_proxy` 设置绑定 |
| `public/scripts/openai.js:1930` | `saveModelList()` — 模型列表存储 |
| `public/scripts/openai.js:4211` | `getStatusOpen()` — 验证连接 + 拉取模型 |
| `src/endpoints/secrets.js:9` | `SECRET_KEYS` — 30+ 个提供商的 key |
| `src/endpoints/openai.js` | 后端 API 代理（各 source 的 key 获取逻辑） |
| `src/endpoints/backends/chat-completions.js` | 聊天完成后端路由 |

### kelivo
| 文件 | 说明 |
|------|------|
| `lib/core/providers/model_provider.dart:128` | `OpenAIProvider.listModels()` — GET /models |
| `lib/core/providers/model_provider.dart:158` | `ClaudeProvider.listModels()` — GET /models |
| `lib/core/providers/settings_provider.dart:3804` | `_defaultBase()` — 名称→URL 自动推断 |
| `lib/core/providers/settings_provider.dart:3574` | `ProviderConfig` 完整类 |

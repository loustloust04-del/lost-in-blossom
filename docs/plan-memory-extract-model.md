# 记忆提取模型：独立配置 + 智能 fallback

## 背景

当前 `ConversationViewModel.cheapModel`（`.swift:797`）按硬编码列表
`["anthropic/claude-haiku-4-5", "openai/gpt-4o-mini", "deepseek/deepseek-chat"]`
通过 `providerManager.model(byId:)` 查找 —— **不 check 有没有 key / 有没有拨款**，
于是记忆提取经常落到一个没 key 没拨款的 provider，被 `budgetGate` 拦住抛
"没被拨款"。粟粟的期望：记忆模型单独一套 API（自己的 baseURL + key +
model），没配就用主 provider 的 cheap model，再没有就用主对话模型本身。

## 决策（最终版 — 经两轮 push back 后定稿 2026-04-23）

- **不做**独立 API 配置：复用现有 provider 列表（Keychain 保护、预算、倍率等
  基础设施都统一）。想用"完全不同的中转站"请先在 API 设置加一个 custom
  provider，再标成副 🌛
- 切换入口：**只在 API 设置的 model list 里**，每行两个 emoji 按钮
  🌞（主对话）/ 🌛（副记忆）。点一下 toggle；🌞 和整行 tap 等价
- fallback 链：手动 🌛 选了 → 用它；没选 → 主 provider 的 cheap map
  （hardcode 5 个）→ 都没 fallback 主对话模型本身
- 预算：**共用一个** — 记忆提取的 gate 和 spent 都算到**主对话 provider**
  头上，不管副模型在哪（粟粟批注：分词器粗算，预算是保险不是精细账本）

## 数据模型

`MemoryPalace/Models/MemoryModelConfig.swift`（新）

```swift
struct MemoryModelConfig: Codable {
    var enabled: Bool          // false = 走 fallback 链；true = 用独立配置
    var providerType: String   // "openai-compatible" / "anthropic"
    var baseURL: String
    var modelId: String
    // apiKey 不在这里，走 Keychain，account = "__memory_extract__"
}
```

- UserDefaults key: `memoryModelConfig`
- Keychain account: `__memory_extract__`

## Fallback 链（`cheapModel` 重写）

```
1. MemoryModelConfig.enabled && apiKey 非空
     → 用独立配置
2. 否则，主对话 provider 的 id 在 cheapModelIdByProvider map 里
     → 用该 provider 下的 cheap modelId
     cheapModelIdByProvider = [
         "anthropic":  "claude-haiku-4-5",
         "openai":     "gpt-4o-mini",
         "deepseek":   "deepseek-chat",
         "gemini":     "gemini-2.5-flash",
         "groq":       "llama-3.3-70b-versatile"
     ]
     （只在主 provider 有 key 时生效；modelId 不存在就跳过）
3. 都不命中 → 用主对话 model 本身（fallback 参数）
```

## ProviderRouter 改造

- `sendNonStreaming` 当前从 `providerManager` 查 provider+key。
- **新增 overload**：`sendNonStreaming(messages:..., configuration:
  MemoryRouteConfig)` 接受显式 `{baseURL, apiKey, modelId, type,
  extraHeaders}`，绕过 providerManager lookup。独立配置路径用这个。
- Fallback 路径（cheap / mainModel）仍走原 `sendNonStreaming`，因为
  cheap 和 mainModel 都在 providerManager 里。

## Budget 行为（关键：共用一个预算）

修改点在 `extractMemoriesIfNeeded`：

- `backendAgentBlockedByBudget` 的 gate 查 **主对话 provider**（传入
  `model: mainChatModel`），不查记忆模型所在 provider
- `commitSpend` 也写到 **主对话 provider** 的 spentUSD
- 换言之：`extractMemoriesIfNeeded` 的 signature 里新增 `mainChatModel:
  ProviderModel` 参数，budget 相关操作都用它；实际调用仍用
  extractModel（独立 or cheap or main）

## UI 改造

### MemorySettingsTab.swift（macOS） + IOSMemoryPage（iOS）

把现有"提取模型" Picker 换成一块区块：

```
┌ 提取模型 ────────────────────────────────────────────
│ ○ 自动（按 fallback 链）
│   • 主 provider 有 cheap 映射 → 用 cheap model
│   • 否则用主对话模型本身
│
│ ● 独立配置
│     API 类型:  [OpenAI 兼容 ▾]
│     Base URL:  ___________________________
│     API Key:   ••••••••  [测试连接]
│     Model ID:  ___________________________
└───────────────────────────────────────────────────
```

独立配置写入时即 save（和现有 ProviderManager.setApiKey 风格一致）。

## 触及文件

- [新] `MemoryPalace/Models/MemoryModelConfig.swift` — struct + load/save helpers
- [改] `MemoryPalace/Services/ChatService.swift` — `ProviderRouter`
  新增 `sendNonStreaming(configuration:)` overload
- [改] `MemoryPalace/ViewModels/ConversationViewModel.swift` —
  `cheapModel` 重写、`extractMemoriesIfNeeded` 改 budget 主体
- [改] `MemoryPalace/Views/MemorySettingsTab.swift` — 两处 UI 重构
  （MemorySettingsTab + IOSMemoryPage）

## Checklist

- [ ] 1. `MemoryModelConfig.swift` 新建 — struct + UserDefaults
      load/save + Keychain 读写 helpers + 全局单例 `MemoryModelStore`
- [ ] 2. `ChatService.ProviderRouter.sendNonStreaming(configuration:)`
      overload — 显式 baseURL/apiKey/modelId/type
- [ ] 3. `ConversationViewModel.cheapModel` 重写 fallback 链（独立 →
      cheap map → main fallback）— 返回类型改成 `MemoryExtractRoute`
      enum 区分"走 providerManager 的 ProviderModel" 还是"走独立 config"
- [ ] 4. `extractMemoriesIfNeeded` 接入新 route — budget gate 和
      commitSpend 都改用主对话 provider 对应的 model（新增参数
      `mainChatModel`，从上游 sendMessage 传入）
- [ ] 5. `MemorySettingsTab.swift` macOS UI — 「自动 / 独立配置」radio
      区块 + 独立配置 3 个输入框 + 类型选择器
- [ ] 6. `IOSMemoryPage` iOS UI — 同样结构，iOS 原生 Form/Section
      风格，独立配置 key 走 SecureField
- [ ] 7. iOS + macOS build ✅
- [ ] 8. 实际测试：
      - [ ] 不配独立 → 主 provider 是 Anthropic → 自动走 haiku
      - [ ] 不配独立 → 主 provider 是 custom（没 cheap 映射）→ 走主对话模型本身
      - [ ] 配独立（OpenAI 兼容）→ 使用独立 key/baseURL 提取记忆
      - [ ] 不论哪条路径，记忆提取的 spent 都累加到**主对话 provider**
- [ ] 9. commit + push

## 不做 / 以后再说

- 独立记忆模型的**独立预算**（粟粟要求共用一个预算，后期如果想分开
  再加一个独立 budget 字段）
- 自定义 cheap model 名单（粟粟说"也可以自选没关系"，暂硬编码，未来
  再做配置 UI）
- 测试连接按钮（nice-to-have，非阻塞）— 放到 checklist-9 之后做

# Plan — API 额度上限（保险闸）

> 2026-04-18。基于 research-api-budget.md，粟粟批注 AAAAAA。

## 目标

给每个 API 加一道保险闸：发送前粗估成本，超预算就拦住；发送后拿真实 `usage` 回填花费。主要防 app bug（死循环/重试风暴/遗留 streaming）把 key 烧干。

## 粟粟已定

| 项 | 决策 |
|----|------|
| 范围 | 每 API 独立预算（C14/C15 全局/轮询 → 以后做）|
| 周期 | 手动拨款 + 开关可关（默认开）（C16 自动清零 → 以后做）|
| 价格表 | 硬编码官方 provider；中转站走倍率 |
| 倍率粒度 | per-provider（不 per-model）|
| 掐停 | 100% 硬停 + 80% 警告 |
| UI | API 设置页底部新 section，跟 picker 切 |
| Tokenizer | 这轮只 HeuristicEstimator（tiktoken → 留 roadmap C18）|
| 按次计费 | 不做，留 C19 |

---

## 数据模型变化

### 1. `APIProvider` 新增 7 个字段（都 Codable fallback 兼容老数据）

```swift
var budgetEnabled: Bool       // 开关，默认 true
var budgetUSD: Double         // 上限，默认 0（= 没拨款 = 拦一切）
var spentUSD: Double          // 累计花费，系统更新
var modelRatio: Double        // 默认 1.0（官方 provider）
var completionRatio: Double   // 默认 1.0
var groupRatio: Double        // 默认 1.0
var currencyRate: Double      // 默认 1.0（USD 原价）
```

### 2. `ModelPricing` + `defaultPricingTable`

`Models/ModelPricing.swift`（新建）：

```swift
struct ModelPricing {
    let inputUSDPerMTok: Double
    let outputUSDPerMTok: Double
}

enum PricingCatalog {
    /// 前缀模糊匹配，支持中转站的 "anthropic/claude-sonnet-4" 或本尊 "claude-sonnet-4"
    static func price(for modelId: String) -> ModelPricing { ... }

    private static let table: [String: ModelPricing] = [
        // Anthropic
        "claude-opus-4-6":        ModelPricing(15, 75),
        "claude-sonnet-4-5":      ModelPricing(3, 15),
        "claude-haiku-4-5":       ModelPricing(0.8, 4),
        // OpenAI
        "gpt-4o":                 ModelPricing(2.5, 10),
        "gpt-4o-mini":            ModelPricing(0.15, 0.6),
        "gpt-4.1":                ModelPricing(2, 8),
        "o3":                     ModelPricing(2, 8),
        // DeepSeek
        "deepseek-chat":          ModelPricing(0.27, 1.1),
        "deepseek-reasoner":      ModelPricing(0.55, 2.19),
        // Google
        "gemini-2.5-pro":         ModelPricing(1.25, 5),
        "gemini-2.5-flash":       ModelPricing(0.075, 0.3),
        // Groq / xAI / 国产家族用保守默认
    ]

    static let fallback = ModelPricing(3, 15)
}
```

### 3. `TokenEstimator` + `HeuristicEstimator`

`Utils/TokenEstimator.swift`（新建）：

```swift
protocol TokenEstimator {
    func estimate(_ text: String) -> Int
}

struct HeuristicEstimator: TokenEstimator {
    func estimate(_ text: String) -> Int {
        // CJK 字符 × 1.0；非 CJK × (1/3.5)
        var cjk = 0
        var other = 0
        for s in text.unicodeScalars {
            if isCJK(s) { cjk += 1 } else { other += 1 }
        }
        return cjk + Int(ceil(Double(other) / 3.5))
    }
    // 范围：U+3000..U+9FFF + U+FF00..U+FFEF + U+4E00..U+9FFF + 常用
}
```

### 4. `BudgetCalculator`

`Utils/BudgetCalculator.swift`（新建）：

```swift
enum BudgetCalculator {
    /// Pre-send 估算（保守偏贵，用 max_tokens 估 output）
    static func estimateCost(
        provider: APIProvider,
        model: ProviderModel,
        messages: [(role: String, content: String)],
        systemPrompt: String?,
        maxOutputTokens: Int,
        estimator: TokenEstimator
    ) -> Double {
        let inputText = (systemPrompt ?? "") + messages.map { $0.content }.joined(separator: "\n")
        let inputTok = estimator.estimate(inputText)
        return applyRatios(
            provider: provider,
            modelId: model.modelId,
            inputTokens: Double(inputTok),
            outputTokens: Double(maxOutputTokens)
        )
    }

    /// Post-send 真实花费
    static func actualCost(
        provider: APIProvider,
        modelId: String,
        usage: TokenUsage
    ) -> Double {
        applyRatios(
            provider: provider,
            modelId: modelId,
            inputTokens: Double(usage.inputTokens),
            outputTokens: Double(usage.outputTokens)
        )
    }

    private static func applyRatios(
        provider: APIProvider,
        modelId: String,
        inputTokens: Double,
        outputTokens: Double
    ) -> Double {
        let pricing = PricingCatalog.price(for: modelId)
        let inputUSD  = inputTokens  / 1_000_000 * pricing.inputUSDPerMTok
        let outputUSD = outputTokens / 1_000_000 * pricing.outputUSDPerMTok * provider.completionRatio
        return (inputUSD + outputUSD) * provider.modelRatio * provider.groupRatio * provider.currencyRate
    }
}

struct TokenUsage {
    let inputTokens: Int
    let outputTokens: Int
}
```

### 5. `ProviderManager` 方法

```swift
/// Pre-check：预算是否够 estimatedCost
/// 返回 .ok / .warning(percent) / .blocked(spent, budget)
func budgetCheck(providerId: String, estimatedCost: Double) -> BudgetGate

/// Post-send：扣费
func commitSpend(providerId: String, amount: Double)

/// 重置已用
func resetSpent(providerId: String)
```

---

## ChatService 的 usage 回传

**现状**：`onComplete: (String) -> Void` 只传 content，没 usage。

**改法**：
- 新增 `TokenUsage` 类型（在 APIProvider.swift 或 ChatService.swift）
- 改签名：`onComplete: (String, TokenUsage?) -> Void`
- **OpenAI 流式**：请求里加 `"stream_options": { "include_usage": true }`，响应最后一个 chunk 带 `usage: { prompt_tokens, completion_tokens }`
- **OpenAI 非流式**：响应根对象就有 `usage`
- **Anthropic 流式**：`message_delta` event 带 `usage: { output_tokens }`，`message_start` 带 `usage: { input_tokens }`，两个合并
- **Anthropic 非流式**：根对象 `usage: { input_tokens, output_tokens }`

**影响的 callers**：
- `ProviderRouter.sendStreaming` / `sendNonStreaming` — 要把 usage 向上传
- `ConversationViewModel.sendMessage` / `regenerate` — 拿到 usage 调 `commitSpend`
- 所有其他 onComplete closure：加 `, _` 忽略 usage 或 `_ = usage`

---

## UI — BudgetSection

**位置**：APISettingsTab 里，跟随 `apiSelectedProviderId` 显示那条 provider 的预算。放在"模型"section 下方、"iCloud Keychain 同步"上方。

**布局**：

```
预算（保险闸）                                  [开关]
─────────────────────────────────────
预算额度（USD）        [ 10.00 ]
已使用                  $ 3.42
进度                    ▓▓▓▓░░ 34%

▶ 中转站倍率  (折叠)
    模型倍率     [ 1.00 ]
    补全倍率    [ 1.00 ]
    分组倍率    [ 1.00 ]
    充值汇率    [ 1.00 ]

                        [重置已用]
```

- 进度条：80% 前绿色，80-99% 黄色，100% 红色
- 开关关掉时整个 section 下面字段置灰 + pre-send 直接放行
- 倍率区默认折叠；官方 provider（isBuiltIn）隐藏（反正是 1.0）；custom provider 展开可编辑
- 重置弹 confirm：「清空 $3.42 的已用记录？预算上限不变」

---

## 实施步骤 & Checklist

### Phase A：数据 + 价格表 + Estimator

- [ ] **A1** 新建 `Models/ModelPricing.swift`：`ModelPricing` + `PricingCatalog`（前缀模糊匹配）
- [ ] **A2** 新建 `Utils/TokenEstimator.swift`：`TokenEstimator` 协议 + `HeuristicEstimator`（CJK 1x + 非 CJK 1/3.5）
- [ ] **A3** 新建 `Utils/BudgetCalculator.swift`：`TokenUsage` + `estimateCost` + `actualCost` + `applyRatios`
- [ ] **A4** `APIProvider` 加 7 字段 + `init(from:)` fallback + `init(...)` 默认参数
- [ ] **A5** `ProviderManager` 加 `budgetCheck / commitSpend / resetSpent`，内部写盘（复用 custom provider 持久化）
- [ ] **A6** macOS + iOS build 通过

### Phase B：ChatService usage 回传

- [ ] **B1** 把 `TokenUsage` 放到公共模块（APIProvider.swift 或 BudgetCalculator.swift）
- [ ] **B2** `BaseChatProvider.onComplete` 签名改 `(String, TokenUsage?) -> Void`
- [ ] **B3** `OpenAICompatibleProvider`：
  - 流式请求加 `"stream_options": { "include_usage": true }`
  - 流式解析：从最后 chunk 的 `data: {...}` 里拿 `usage: { prompt_tokens, completion_tokens }`
  - 非流式：根对象 `usage`
- [ ] **B4** `AnthropicProvider`：
  - 流式：收集 `message_start` 的 `usage.input_tokens` + `message_delta` 的 `usage.output_tokens`
  - 非流式：根对象 `usage`
- [ ] **B5** `ProviderRouter.sendStreaming / sendNonStreaming` 签名同步，把 usage 向上传
- [ ] **B6** 所有 call site 补 `, _` 或 `, usage in`（ConversationViewModel / memory agents / 测试连接等）
- [ ] **B7** Build 通过

### Phase C：Pre-send 拦截 + Post-send 回填

- [ ] **C1** `ConversationViewModel.sendMessage` 前：
  - 构造 messages / systemPrompt（复用现有组装）
  - 调 `BudgetCalculator.estimateCost` + `providerManager.budgetCheck`
  - `.blocked` → 弹 alert 提示并 return
  - `.warning(pct)` → 可选弹 alert 问"继续？"（本轮用 print + 不拦，减少打扰；用户要严格就提升阈值）
  - `.ok` → 正常发
- [ ] **C2** `regenerate` 同理
- [ ] **C3** `onComplete (content, usage)`：
  - `usage == nil` → 用 pre-send 的 estimate 做 commitSpend
  - `usage != nil` → 用 `BudgetCalculator.actualCost` 精算 commitSpend
- [ ] **C4** 中断（onError / 用户取消 streaming）：
  - 已流过的部分不好算；简化做法：按 pre-send 的 estimate 扣一次（保守）
  - 或者按已流回来的 content 长度估算；本轮按 pre-send estimate 扣，留 roadmap 优化
- [ ] **C5** UI：alert 文案 "预算已用完（$X / $Y）。去 API 设置拨款或关闭预算限额"

### Phase D：BudgetSection UI

- [ ] **D1** 在 APISettingsTab 加 `budgetContent` computed view
- [ ] **D2** Toggle `budgetEnabled` → 绑定到 `selectedProvider` 的对应字段（通过 providerManager 路由）
- [ ] **D3** 预算额度 TextField（decimal keypad on iOS）
- [ ] **D4** 进度条：`ProgressView(value: spent, total: budget).tint(...)` 按百分比变色
- [ ] **D5** 倍率折叠：DisclosureGroup，built-in provider 隐藏
- [ ] **D6** "重置已用" confirm → `resetSpent`
- [ ] **D7** 集成到 macOSBody / iOSBody
- [ ] **D8** Build

### Phase E：收尾

- [ ] **E1** 通读 diff
- [ ] **E2** 手动跑：
  - [ ] 官方 provider (openrouter/anthropic) 配预算 → 发一条 → 看 spent 是否上涨
  - [ ] 手动把 budget 设很小 → 发消息 → 看是否被拦
  - [ ] 关预算开关 → 看发送是否畅通
  - [ ] 重置按钮 → spent 归零
  - [ ] custom provider 配倍率 → 看计算是否按倍率
- [ ] **E3** git commit（按 Phase 拆或合并，按习惯）：
  1. `feat: API 预算基建 — 价格表 + HeuristicEstimator + BudgetCalculator`
  2. `feat: ChatService 回传 usage (input/output tokens)`
  3. `feat: API 预算保险闸 pre-check + post-commit`
  4. `feat: API 设置页 BudgetSection UI`
  5. `docs: research + plan for API 预算`
- [ ] **E4** git push

---

## 风险速查

| 风险 | 缓解 |
|------|------|
| 老数据 Codable 兼容 | 7 字段全 decodeIfPresent + 默认值 |
| ChatService 改签名影响所有调用 | 先改协议 + Router，一次性补所有 call site |
| OpenAI stream 不默认返回 usage | 请求加 `stream_options.include_usage` |
| Anthropic stream usage 拆在两个 event | 合并 input_tokens（message_start）+ output_tokens（message_delta）|
| Pre-send estimate 粗 → 超预算很多 | Post-send 精算会自愈；保险闸容忍一次"过冲" |
| 预算为 0 默认拦一切 | budgetEnabled 默认 true 但 budgetUSD 默认 0 —— 新用户首次启动会被拦；**改成 budgetEnabled 默认 false**（老用户升级不炸）或 budgetUSD 默认 0 但 budgetEnabled 默认 false |
| 流中断扣费不准 | 按 pre-send estimate 兜底；roadmap 优化 |

**默认值最终决策**：`budgetEnabled = false`（默认关，符合老用户升级无缝）。要粟粟再确认一下：她说"默认打开"，那就 `budgetEnabled = true` + `budgetUSD = 0`，新用户首次发消息会被拦，弹提示让他们去配置。是粟粟想要的保险闸逻辑。OK，默认 true。

---

## 不做清单

- C14 分组/轮询
- C15 全局总预算
- C16 自动清零周期
- C18 Claude BPE 精算（等 tokenizer）
- C19 按次计费
- tiktoken Swift Package 依赖（这轮纯 heuristic）

---

*批「OK 执行」我就进 Phase A。*

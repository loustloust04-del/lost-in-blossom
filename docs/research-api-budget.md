# Research — API 额度上限（保险闸）

> 2026-04-18。对应 roadmap 新加的 C13（本轮做）+ C14-19（未来）。
>
> 粟粟定性：**这个功能核心是"保险闸"**，防止 app 自己的 bug（比如死循环、重试风暴、遗留 streaming）把用户 key 烧干。不是精算工具。

---

## 一、粟粟已定的四点

| # | 决策 |
|---|------|
| Q1 范围 | **每个 API 独立一份预算**；API 分组 / 全局总预算 → roadmap C14/C15 |
| Q2 周期 | **手动拨款**；功能**有开关、默认打开**；自动清零 → roadmap C16 |
| Q3 价格/倍率 | 粟粟给了详细背景（one-api 三层倍率）；需要上网调研细化 → 见 §三、§四 |
| Q4 精度 | 不能"粗估到没意义"；上网调研精度方案 → 见 §三 |

---

## 二、调研结论（2026-04-18）

### 2.1 Tokenizer 现状

| 模型家族 | 本地 tokenizer | 状态 |
|----------|---------------|------|
| OpenAI (GPT-4 / GPT-4o / o1 / o3 / o4) | **tiktoken**（Rust 内核）| ✅ 有成熟 Swift 包装（TiktokenSwift / aespinilla Tiktoken）|
| Anthropic (Claude 3/4) | ❌ Anthropic 不公开 | Claude 3.x+ 没有官方 tokenizer；官方建议 heuristic **1 token ≈ 3.5 英文字符** |
| DeepSeek / Moonshot / GLM / 通义 / Groq / xAI 等 | 通常兼容 GPT tokenizer | 用 tiktoken `cl100k_base` 粗估，误差 ±10-20% |
| Google Gemini | 有官方 tokenize API，本地无 | 用 heuristic |

**给我们**：
- **input token 估算**：对 OpenAI-compat 用 tiktoken 精算；对 Anthropic 用字符 heuristic（中 1.0x + 英 1/3.5）
- **output token 估算**：用户发送前不知道 output 多长，**按 `max_tokens` 上限保守估**
- **事后回填**：所有主流 API 响应都带 `usage: {input_tokens, output_tokens}` 字段，发送完直接用真实值更正

结论：**不需要 C4 tokenizer 精算也能做到 ±10-20% 精度的保险闸**。够用了。

### 2.2 中转站计费公式（粟粟上一轮给的知识）

```
费用(USD) = (input_tokens + output_tokens × completionRatio) × modelRatio × groupRatio
人民币花费 = 费用(USD) × 充值汇率
```

- **modelRatio**：该模型相对基准（davinci-002 = 1x）的倍数
- **completionRatio**：output 相对 input 的倍数
- **groupRatio**：站长给用户组的折扣/加价
- **充值汇率**：人民币充值 → 等值美元额度的换算率（很多站故意调这个数误导）

对官方 provider（Anthropic/OpenAI/DeepSeek 官网）：所有 ratio 都是 1，汇率按实时美元。

对中转站（custom）：四个都得用户自己填。

### 2.3 外部参考

- [TiktokenSwift](https://github.com/narner/TiktokenSwift) — Swift wrapper，Rust 内核，iOS 13+
- [aespinilla/Tiktoken](https://swiftpackageregistry.com/aespinilla/Tiktoken) — 纯 Swift 实现
- [Anthropic token counting heuristic](https://platform.claude.com/docs/en/build-with-claude/token-counting)（"1 token ≈ 3.5 英文字符"）
- [one-api ratio 配置](https://github.com/songquanpeng/one-api) — 所有中转站的祖宗

---

## 三、"保险闸"做到什么程度

### 3.1 拦截时机

| 时机 | 做什么 |
|------|--------|
| 发送前 | 估算本次消息成本 → 看 provider 剩余预算够不够 → 不够就**拦住发送** + 弹提示 |
| 发送中（streaming）| 不动（如果已开了流又中断，token 已扣）|
| 发送完成后 | 从响应 `usage` 字段读真实 token → 按单价 + 倍率回填 `spent` |
| 冷启动 | 如果上次崩溃中断，不恢复任何状态（预算状态只在每次发送前/后修改）|

### 3.2 估算算法

```swift
// Pre-send 估算（保守偏贵）
let inputTokens = estimator.countInput(messages, for: model)
let outputTokens = maxTokensSetting   // 按 max_tokens 上限估
let estimatedCost =
    (Double(inputTokens) + Double(outputTokens) * model.completionRatio)
    * model.modelRatio * provider.groupRatio * pricePerToken(model)
    * provider.currencyRate

// 如果 provider.spent + estimatedCost > provider.budget → 拦
```

```swift
// Post-send 回填（真实）
let actualCost =
    (Double(response.usage.input_tokens) + Double(response.usage.output_tokens) * model.completionRatio)
    * model.modelRatio * provider.groupRatio * pricePerToken(model)
    * provider.currencyRate

provider.spent += actualCost
```

### 3.3 单价（pricePerToken）哪来

**三选一**：
- **A. 硬编码官方价格表**（我维护）
  - 覆盖 Anthropic / OpenAI / DeepSeek / Groq / xAI / Gemini / 国产几家的官方模型
  - 缺点：模型更新我得改代码；custom 中转站无效
- **B. 让用户自己填每个模型的 input/output 单价**
  - 全用户责任；缺点：门槛高
- **C. 混合**：内置 provider 用硬编码表；custom 中转站默认认为"和官方同价"，让用户通过**倍率**（model/completion ratio）修正
  - 推荐

用 C 的话，data flow：
- 内置 provider（Anthropic/OpenAI 等）的 model 查官方价格表 → 得 input/output 单价
- custom provider 的 model：从**关联到某个官方 provider 家族**（比如中转站跑 claude-sonnet-4 → 按 Anthropic 官方价），再 × 用户配置的倍率 × 汇率

### 3.4 估算 UI 粒度

- **最小必要**：每个 provider 一个"预算 (USD) + 已用 (USD)"，剩多少一眼看见
- **增量**：每条消息发送后在气泡上显示 "≈ $0.003"？不做，烟尘
- **更增量**：Token 可视化条（roadmap C5）—— 不做

本轮只做最小必要 + **达到 80% 时黄色提醒、100% 掐停**。

---

## 四、数据模型

### 4.1 给 APIProvider 加字段

```swift
struct APIProvider {
    // 既有字段...
    var budgetEnabled: Bool      // 开关，默认 true
    var budgetUSD: Double        // 上限，默认 0（表示没拨款，等于被拦一切）
    var spentUSD: Double         // 累计花费，由系统更新，不给用户直接改
    // 中转站倍率 —— 官方 provider 全部 1.0
    var modelRatio: Double       // 模型倍率（per-provider 简化，不 per-model，够用了）
    var completionRatio: Double  // 补全倍率
    var groupRatio: Double       // 分组倍率
    var currencyRate: Double     // 充值汇率（人民币→美元系数，默认 1.0 = 等于按美元）
}
```

**简化决策**：`modelRatio` 在**provider 级**而非 per-model。真实中转站每个模型可能不同倍率——不在这轮做，留 roadmap。

### 4.2 新增 `ModelPricing` 硬编码表

```swift
struct ModelPricing {
    let inputUSDPerMTok: Double   // per 1M input tokens
    let outputUSDPerMTok: Double
}

let defaultPricingTable: [String: ModelPricing] = [
    "claude-opus-4-6": ModelPricing(inputUSDPerMTok: 15, outputUSDPerMTok: 75),
    "claude-sonnet-4-5": ModelPricing(inputUSDPerMTok: 3, outputUSDPerMTok: 15),
    "gpt-4o": ModelPricing(inputUSDPerMTok: 2.5, outputUSDPerMTok: 10),
    // ... 10-20 条热门模型
]
```

查找逻辑：按 modelId 前缀模糊匹配（因为中转站可能 `custom/claude-opus-4-6`）。查不到 → fallback 一个保守默认价 `(3, 15)`。

### 4.3 Tokenizer 抽象

```swift
protocol TokenEstimator {
    func estimate(_ text: String) -> Int
}

struct HeuristicEstimator: TokenEstimator {
    func estimate(_ text: String) -> Int {
        // 中文字符 × 1.0，英文按 3.5 字符/token
        // 简单实现：统计 CJK + 非 CJK 分别算
    }
}

// 未来：TiktokenEstimator 包装 Swift Package
```

**这轮只做 HeuristicEstimator**。够用。tiktoken 依赖留下轮（C4 或 C18）。

---

## 五、UI 设计

### 5.1 在 SavedAPIRow 卡片下方加预算区

但单行 row 不够装，需要展开交互。或者：

**方案 A：独立的"预算"sheet / sub-page**
- 在 SavedAPIRow 的 context menu 里加「预算设置」
- 点开进入一个小 sheet：开关 + 预算额度 + 已花费 + 倍率 + 重置

**方案 B：API 设置页底部新增「当前 API 的预算」section**
- 根据 `apiSelectedProviderId` 显示那个 provider 的预算
- 跟"API Key"section 平级

**方案 C：在卡片右侧用小进度条表示 (75% / $15)**
- 不能改字段，只能看

我**推荐 B**：和其他字段一样在同一页编辑，不用跳页。点击 saved API 列表切换 provider 后，预算 section 也跟着切。和 "API Key"、"模型" 平行。

### 5.2 字段排布（方案 B）

```
┌─ 预算（保险闸） ─────────────────────┐
│                                      │
│  [开关]  启用预算限额         [●]   │
│                                      │
│  预算额度（USD）      [ 10.00 ]      │
│  已使用               $ 3.42         │
│  进度                 ▓▓▓▓░░░  34%  │
│                                      │
│  ▼ 中转站倍率（官方 provider 留空）  │
│  模型倍率    [ 1.00 ]                │
│  补全倍率    [ 1.00 ]                │
│  分组倍率    [ 1.00 ]                │
│  充值汇率    [ 1.00 ]                │
│                                      │
│         [重置已用]                    │
│                                      │
└──────────────────────────────────────┘
```

倍率 section 可折叠（官方 provider 默认折叠）。

### 5.3 掐停交互

- Pre-send check 失败 → `ChatInputBar.send()` 不走网络，弹 alert "预算已用完（已花费 $X / 预算 $Y），请在 API 设置里拨款或关闭预算限额"
- 80% → alert 警告但允许继续

### 5.4 重置

- "重置已用"按钮 → confirm → `spentUSD = 0`
- 不清 budget 额度本身

---

## 六、粟粟要决定的点

### 6.1 价格表 — 三选一
- **A. 只硬编码官方 provider（openai/anthropic/deepseek/groq/gemini/xai 等）；中转站让用户通过倍率调**（推荐）
- B. 连价格也让用户填（更灵活但门槛高）
- C. 不内置价格表，发送前不估，只做事后回填（不够"保险闸"，失去拦截功能）

### 6.2 倍率是 per-provider 还是 per-model
- **A. per-provider 简化**（粟粟给一个中转站填 4 个数就完）（推荐）
- B. per-model（最真实，但要每个模型都配置，门槛高）
- C. 先 per-provider，后续迭代到 per-model

### 6.3 掐停阈值
- **A. 100% 硬掐停 + 80% 警告**（推荐）
- B. 只掐停无警告
- C. 多个阈值（50%/80%/95%/100%）

### 6.4 预算 UI 位置
- **A. API 设置页底部新 section，跟着 picker 切（推荐）**
- B. SavedAPIRow context menu → sheet
- C. 独立 tab「预算」

### 6.5 Tokenizer 精度
- **A. 这轮只用 HeuristicEstimator，够 80-90% 精度；tiktoken 依赖留 roadmap（推荐，轻量）**
- B. 这轮就加 TiktokenSwift 依赖（OpenAI 系精算；Claude 仍 heuristic）
- C. 直接调 Anthropic / OpenAI 的 tokenize 端点（精准但要网络 + rate limit，破坏"离线估算"的前提）

### 6.6 "按次计费"
比如 Copilot 类的 API 是按请求次数扣固定钱。**这轮做不做？**
- **A. 不做，留 C19**（推荐）
- B. 做：加个 `billingMode: .byToken | .perRequest` + `perRequestUSD`

---

*粟粟批完我写 plan。*

**Sources**:
- [narner/TiktokenSwift](https://github.com/narner/TiktokenSwift)
- [aespinilla/Tiktoken (Swift)](https://swiftpackageregistry.com/aespinilla/Tiktoken)
- [Anthropic token counting docs](https://platform.claude.com/docs/en/build-with-claude/token-counting)
- [songquanpeng/one-api (倍率系统)](https://github.com/songquanpeng/one-api)
- [Counting Claude Tokens Without a Tokenizer](https://blog.gopenai.com/counting-claude-tokens-without-a-tokenizer-e767f2b6e632)

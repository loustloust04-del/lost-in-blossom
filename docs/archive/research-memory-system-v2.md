# Research: Phase 2 v2 — 记忆系统重做

> 基于两份 deep research + 现有代码深读，2026-03-26
> 参考：`Persistent memory systems for AI chat applications.md`（工程向）
> 参考：`Making AI memory feel alive, not filed.md`（认知科学向）

---

## 1. 现有实现分析

### 当前架构

```
sendMessage()
    → buildSystemPrompt(): 从 SwiftData 取 MemoryNote，拼到 system prompt 末尾
    → providerRouter.sendStreaming()
    → onComplete: checkAndTriggerSummary()
        → 每 15 轮，取最近 30 条消息
        → 用便宜模型生成结构化总结
        → replaceAutoNote(): 删掉旧的 auto note，写入新的一条
```

### 现有模型

```swift
@Model class MemoryNote {
    var id: UUID
    var content: String      // 一整坨总结文本
    var profileId: String
    var createdAt: Date
    var updatedAt: Date
    var source: String       // "auto" | "manual"
    var isActive: Bool
}
```

### 问题

| # | 问题 | 严重程度 |
|---|------|---------|
| 1 | **一坨式存储** — 每个 profile 只有 1 条 auto note，整体替换。无法单独修正一个错误事实 | 致命 |
| 2 | **丢失式更新** — 新总结覆盖旧总结，历史记忆全丢。调研指出 summarization 是"lossy compression"，一次坏总结就毁全盘 | 致命 |
| 3 | **无 CRUD 粒度** — LLM 无法做"更新这条、删除那条"的精细操作，只能重写整份 | 严重 |
| 4 | **无生命周期** — 没有衰减、没有访问计数、没有时效性。记忆是平的，没有轻重缓急 | 严重 |
| 5 | **全量注入** — 当前上限 750 字符硬截断。记忆多了会截断丢失 | 中等 |
| 6 | **无管理 UI** — 用户看不见 AI 记住了什么，无法修正和信任 | 中等 |
| 7 | **总结质量不稳定** — 便宜模型生成的结构化总结质量波动大 | 中等 |

核心诊断：**当前系统是"日记本"（定期重写一页），需要变成"卡片盒"（每条事实独立生存、独立演化）。**

---

## 2. 调研核心发现

### 2.1 工程向：业界怎么做

**AUDN 模式是行业共识。** LibreChat、Mem0、Open WebUI 插件都用同一个模式：
- 每次对话后，调用一个独立的 memory agent（不是对话模型本身）
- Agent 通过 tool call 执行 Add / Update / Delete / Noop
- Agent 能看到已有记忆，自己判断冲突和重复
- Mem0 在 LOCOMO benchmark 上比 OpenAI 方案高 26%

**ChatGPT 的方案意外地简单：** 全量注入（~100 条 bio entries），无向量检索，无 RAG。证明了：简单方案在中等规模下完全够用。

**分层架构是共识：**

| Tier | 检索方式 | 依赖 | 适用规模 |
|------|---------|------|---------|
| 1 | 全量注入 + token 预算 | 零 | ≤50 条记忆 |
| 2 | BM25 关键词 + recency 打分 | SQLite FTS5（系统自带） | ≤200 条 |
| 3 | 向量相似度（NLContextualEmbedding + sqlite-vec） | sqlite-vec xcframework | ≤100K 条 |

**推荐的 Memory schema**（调研综合 7 个开源项目后的结论）：

```swift
@Model class Memory {
    @Attribute(.unique) var id: UUID
    var content: String              // 原子事实
    var category: MemoryCategory     // preference/fact/relationship/goal/context
    var keywords: [String]           // 预提取关键词
    var tokenCount: Int              // token 预算管理
    var embeddingData: Data?         // 可选：向量嵌入
    var accessCount: Int             // 访问次数（强化信号）
    var lastAccessedAt: Date         // recency 打分
    var decayWeight: Double          // 0.0–1.0 衰减权重
    var validUntil: Date?            // 时效性（"最近在做 X 项目"）
    var sourceConversationId: UUID?  // 来源对话
    var extractedBy: String          // 提取模型
    var isUserExplicit: Bool         // 用户手动 vs 自动提取
    var parentId: UUID?              // 记忆层级（摘要的摘要）
    var profileId: String            // 楼层隔离
    var createdAt: Date
    var updatedAt: Date
}
```

### 2.2 认知科学向：怎么让记忆有"生命感"

**五个组件模型：**

1. **分类存储** — episodic（时间戳+情境标签的对话片段）、semantic（抽象事实/偏好/价值观）、procedural（交互模式偏好）
2. **巩固守护进程** — 不是溢出时才处理，而是定时主动巩固。三个时机：inline（实时标记高显著性事实）、会话结束（生成摘要+交叉引用）、每日深度（跨会话模式提取、矛盾解决、过期清理）
3. **遗忘引擎** — 幂律衰减 `RS = RS₀ × (t+1)^(-d)`，访问时强化。三温区：hot（自动注入）、warm（可搜索不自动加载）、cold（归档）
4. **显著性评分** — 多维向量：情绪强度、自我关联深度、新颖度、用户显式标记、行为信号
5. **重构式检索** — 不说"根据我的记录"，而是把记忆自然融入回答

**核心洞察：记忆是循环，不是管道。** 编码 → 巩固 → 检索 → 再巩固 → 再编码。每个阶段都在改变记忆本身。

**遗忘是最被低估的功能。** MemoryBank 发现只保留 10% 的记忆反而提升了性能。Bjork 的"新废弃理论"区分了 storage strength（只增不减）和 retrieval strength（动态波动）——"遗忘"不是丢失，是降低可及性。

**情感标记的陷阱：** 情绪强度提高记忆鲜明度但不提高准确度。需要主动对抗负面偏差（负面高唤醒事件编码更详细），避免 AI 构建一个不成比例的负面用户画像。

---

## 3. 对记忆宫殿的决策

### 3.1 本轮做什么（Phase 2 v2 scope）

**Tier 1 完整实现 + 巩固周期 + 管理 UI。** 理由：

- AUDN 提取是最大杠杆点（"no memory" → "basic AUDN" 的提升 >> "AUDN" → "向量检索"的提升）
- ChatGPT 至今仍用全量注入，证明 Tier 1 对用户体验的覆盖面足够
- 向量检索需要额外依赖（sqlite-vec xcframework），可以后面加，schema 已预留 embeddingData

具体包含：
1. **Memory 数据模型** — 替换 MemoryNote，原子事实粒度
2. **AUDN 提取** — 每轮对话后用 tool call 模式提取/更新/删除记忆
3. **全量注入 + token 预算** — 注入所有 hot 记忆，不超过 2000 token
4. **衰减引擎** — 访问强化 + 时间衰减 + 三温区
5. **会话结束巩固** — 会话关闭或切换时触发一次交叉检查
6. **管理 UI** — 设置页记忆 tab，逐条查看/编辑/删除/手动添加
7. **迁移** — 旧 MemoryNote 数据迁移到新 Memory 模型

### 3.2 本轮不做什么

| 不做 | 原因 | 留到 |
|------|------|------|
| 向量嵌入 + sqlite-vec | 额外依赖，Tier 1 够用 | Phase 2.5 |
| BM25 关键词检索 | 记忆 ≤50 条时全量注入即可 | 记忆超 50 条时 |
| 每日深度巩固（"睡眠周期"） | 需要后台任务调度，复杂度高 | Phase 2.5 |
| 情感显著性评分 | 需要额外 LLM 调用，ROI 不确定 | Phase 3 或更晚 |
| 重构式检索 | 这更多是 prompt engineering 而非存储层的事 | 人格系统时一起做 |
| 跨楼层记忆共享 | 当前需求是楼层隔离 | 需要时 |
| procedural memory | 交互模式偏好是最模糊的类型 | 远期 |

### 3.3 关键架构决策

**Q1: 提取时机？每轮还是每 N 轮？**

每轮。理由：
- LibreChat 每轮提取，是验证过的方案
- 原子事实提取比总结便宜（输入少、输出短）
- 用便宜模型（Haiku/GPT-4o-mini）单次成本极低
- 每 N 轮提取会丢失中间的重要信息

但增加一个"该不该提取"的前置判断：不是每轮都调 memory agent，而是先快速判断这轮对话有没有值得存的新信息（闲聊/简短回答可以跳过）。这可以用一个简单的启发式规则：用户消息长度 > 20 字符 且 不是纯问句。或者让 memory agent 自己判断（工具调用如果判断无需操作就不调任何工具，成本也很低）。

选择后者：**每轮都调 memory agent，agent 自己决定是否操作**。这样不会漏掉短消息中的重要信息（"我换工作了" 只有 5 个字但极其重要）。

**Q2: Memory agent 用对话模型还是独立模型？**

独立模型。理由：
- 对话模型的 token 窗口用于对话本身，不应该塞记忆管理指令
- 用便宜模型（Haiku/GPT-4o-mini/DeepSeek）降低成本
- 异步执行，不阻塞对话响应
- LibreChat 的做法：独立 LLM 调用，独立 model 配置

**Q3: Tool call 还是结构化 JSON 输出？**

结构化 JSON 输出。理由：
- 当前 ChatService（BaseChatProvider）是纯文本流式接口，不支持 tool call 解析
- 要加 tool call 支持需要大改 ChatService（每个 provider 的 tool call 格式不同）
- JSON 输出对便宜模型足够可靠
- 输出格式：

```json
{
  "actions": [
    {"type": "add", "content": "用户是数据科学家", "category": "fact", "keywords": ["工作", "数据科学"]},
    {"type": "update", "id": "xxx", "content": "用户最近从 Python 转向 Rust", "keywords": ["编程", "Rust"]},
    {"type": "delete", "id": "yyy"},
    {"type": "noop"}
  ]
}
```

**Q4: 全量注入的 token 预算？**

2000 token（约 3000 中文字符）。理由：
- LibreChat 默认 2000-3000 token
- ChatGPT 约 1200-1400 词（英文）
- 记忆宫殿是中文为主，2000 token 约能容纳 40-60 条简短记忆
- 当前的 750 字符上限太小

注入时按 `decayWeight × accessCount_log` 降序排列，取前 N 条直到达到 token 预算。用户显式标记的记忆始终注入（不受预算限制也不受衰减影响）。

**Q5: 衰减参数？**

```swift
// 访问时强化
memory.decayWeight = min(1.0, memory.decayWeight + 0.2)
memory.lastAccessedAt = Date()
memory.accessCount += 1

// 时间衰减（每日执行或惰性计算）
let daysSinceAccess = Date().timeIntervalSince(memory.lastAccessedAt) / 86400
let currentWeight = memory.decayWeight * exp(-0.1 * daysSinceAccess)

// 三温区
// hot:  currentWeight ≥ 0.3 → 自动注入
// warm: 0.05 ≤ currentWeight < 0.3 → 可搜索，不自动注入
// cold: currentWeight < 0.05 且非 userExplicit → 归档候选
```

半衰期约 7 天（exp(-0.1 × 7) ≈ 0.50）。一条被访问 3 次的记忆衰减到 cold 需要约 30 天不被访问。用户手动创建的记忆（isUserExplicit=true）不参与自动衰减。

**Q6: 会话结束巩固做什么？**

时机：用户切换对话或关闭 app 时触发（不需要后台调度）。

操作：
1. 回顾本次会话所有新增/更新的记忆
2. 与已有记忆交叉检查：有没有矛盾？有没有可以合并的？
3. 如果有矛盾，标记旧记忆为待更新，让下次 AUDN 提取时处理

这个巩固比"每日睡眠周期"轻量得多，但覆盖了最关键的矛盾检测场景。

**Q7: 旧 MemoryNote 怎么迁移？**

- 如果有 manual note：逐条迁移为新 Memory（source→isUserExplicit, isActive→decayWeight）
- 如果有 auto note：丢弃（反正下次对话会重新提取）
- 迁移在 app 启动时一次性执行，完成后删除旧 MemoryNote 表

---

## 4. 提取 Prompt

基于调研综合 Mem0 + LibreChat + LangMem 的最佳实践：

```
你是记忆管理助手。分析最近的对话，决定是否需要更新用户的记忆库。

## 当前记忆
{{existing_memories_json}}

## 规则
1. 提取原子事实 — 每条记忆是一个独立的陈述（"喜欢暖色调"而不是"有各种审美偏好"）
2. 分类：preference（偏好）、fact（事实）、relationship（人际关系）、goal（目标/项目）、context（当前情境，有时效性）
3. 对每条新信息做出一个判断：
   - add: 全新信息，现有记忆未覆盖
   - update: 已有记忆需要修正或补充 — 提供要更新的记忆 ID
   - delete: 已有记忆被明确否定或过时 — 提供要删除的记忆 ID
   - 不操作: 已充分覆盖，或不值得存储
4. 只存用户明确说出或强烈暗示的信息。不要推断敏感信息。
5. 用简洁的第三人称：「用户喜欢...」而不是「你喜欢...」
6. 需要时加时间限定词：「用户目前在做...」
7. 新旧矛盾时，delete 旧记忆 + add 新版本。
8. 不存：日常闲聊、一次性问题、用户在问（而非陈述）的信息。

## 输出格式
只输出 JSON，不要解释：
{"actions": [{"type": "add"|"update"|"delete", "id": "仅 update/delete 时填", "content": "记忆内容", "category": "分类", "keywords": ["关键词"]}]}
如果没有需要操作的，输出：{"actions": []}
```

---

## 5. 注入格式

发给对话 API 的 system prompt 末尾追加：

```
[关于用户]
- 喜欢暖奶白配色，不喜欢蓝色和黄色 [偏好]
- 正在开发记忆宫殿 macOS app [目标]
- 名字叫粟粟，AI 叫小雾 [事实]
- 对 UI 变动敏感，偏好小步迭代 [偏好]
- 最近在研究 AI 记忆系统设计 [情境]
```

格式要点：
- 每条一行，`-` 开头，末尾 `[分类]` 标签
- 按 category 分组不如按权重排序（最重要的在前，LLM 对开头内容关注度更高）
- 不出现"根据我的记录"这类措辞 — 记忆应该自然地影响回答，不需要被引用

---

## 6. 与现有代码的集成点

| 组件 | 现有 | 改动 |
|------|------|------|
| `MemoryNote.swift` | 旧模型 | → 替换为 `Memory.swift`，新 schema |
| `MemoryService.swift` | MemoryStore protocol + SwiftDataMemoryStore + MemorySummarizer | → 重写：MemoryStore 适配新模型，新增 MemoryExtractor（AUDN），新增 MemoryInjector（格式化+token预算），删除 MemorySummarizer |
| `ConversationViewModel.swift` | `checkAndTriggerSummary()` 每 15 轮 | → 替换为 `extractMemories()` 每轮异步调用；`buildSystemPrompt()` 改用 MemoryInjector |
| `MemoryPalaceApp.swift` | Schema 含 MemoryNote | → Schema 改为 Memory，加迁移逻辑 |
| `SettingsView.swift` | 无记忆 tab | → 新增记忆管理 tab |
| `ChatService.swift` | 纯文本流式 | → 新增 `sendNonStreaming()` 方法用于 memory agent 调用（不需要流式） |

### ProviderRouter 改动

Memory agent 需要调用 LLM 但不需要流式。当前 `BaseChatProvider` 只有 `sendStreaming()`。需要加一个非流式方法：

```swift
func sendSimple(
    messages: [(role: String, content: String)],
    model: String,
    systemPrompt: String?,
    apiKey: String,
    baseURL: String,
    extraHeaders: [String: String]
) async throws -> String
```

这个方法复用现有的 HTTP 请求逻辑，但不做 SSE 解析，直接等完整响应。Memory agent 用这个方法调用便宜模型。

---

## 7. 成本估算

以 Haiku 3.5 为例（$0.80/M input, $4/M output）：

| 操作 | Input tokens | Output tokens | 成本/次 |
|------|-------------|---------------|---------|
| AUDN 提取 | ~800（prompt + 现有记忆 + 最近 5 条消息） | ~100（JSON actions） | ~$0.001 |
| 会话结束巩固 | ~1500（prompt + 全部记忆 + 本次新增） | ~200 | ~$0.002 |

每天聊 50 轮：约 $0.05 + 每次会话结束 $0.002。
每月成本：~$1.5。可以忽略。

用 GPT-4o-mini 更便宜（$0.15/M input）。用 DeepSeek 几乎免费。

---

## 8. 风险

| 风险 | 缓解 |
|------|------|
| 便宜模型 JSON 输出格式不稳定 | 加 JSON 解析容错 + 正则提取 fallback |
| AUDN 提取产生冗余记忆 | 注入时去重（相同 keywords 的记忆只保留最新）+ 会话巩固时检查 |
| 衰减参数需要调优 | 先用论文推荐值，后续根据实际数据调整 |
| Memory 表膨胀 | token 预算限制注入量；cold 记忆定期归档 |
| 迁移失败 | 旧 MemoryNote 不立刻删除，迁移后标记 migrated，验证无误再清理 |

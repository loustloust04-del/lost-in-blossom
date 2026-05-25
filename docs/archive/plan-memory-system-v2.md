# Plan: Phase 2 v2 — 记忆系统重做

> 基于 research-memory-system-v2.md，CC 制定，粟粟批注
> 替代旧的 plan-memory-system.md

---

## 目标

从"每 15 轮生成一坨总结"变成"原子事实卡片盒 + AUDN 提取 + 衰减引擎 + 管理 UI"。让 AI 真正记住粟粟，而且粟粟看得见、改得了它记住了什么。

## 文件变更总览

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | Models/Memory.swift | 新记忆模型 + MemoryCategory enum |
| 重写 | Services/MemoryService.swift | MemoryStore 适配新模型 + MemoryExtractor（AUDN）+ MemoryInjector + DecayEngine |
| 修改 | Services/ChatService.swift | 新增 `sendNonStreaming()` 给 memory agent 用 |
| 修改 | ViewModels/ConversationViewModel.swift | 每轮提取 + 注入改造 + 会话巩固 |
| 修改 | MemoryPalaceApp.swift | Schema 注册 Memory + 迁移逻辑 |
| 修改 | Views/SettingsView.swift | 记忆管理 tab |
| 删除 | Models/MemoryNote.swift | 迁移完成后废弃 |

---

## Checklist

### Step 1: Memory 数据模型

- [x] 1.1 新建 `Models/Memory.swift`

```swift
@Model
final class Memory {
    @Attribute(.unique) var id: UUID = UUID()
    var content: String              // 原子事实："用户喜欢暖奶白配色"
    var category: String             // "preference" | "fact" | "relationship" | "goal" | "context"
    var keywords: [String]           // ["配色", "暖奶白"] — 预提取，用于未来 BM25 检索
    var tokenCount: Int              // 该条记忆的 token 数（粗算：中文字数 × 1.5）

    var accessCount: Int = 0         // 被注入/检索次数
    var lastAccessedAt: Date         // 上次被注入的时间
    var decayWeight: Double = 1.0    // 0.0–1.0，衰减权重
    var validUntil: Date?            // 可选：时效性（"目前在做 X 项目"到期自动降权）

    var sourceConversationId: String? // 来源对话 ID
    var extractedBy: String = ""     // 提取模型名
    var isUserExplicit: Bool = false // 用户手动创建 vs 自动提取

    var profileId: String            // 楼层隔离
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // 预留，本轮不用
    var embeddingData: Data?         // 向量嵌入（Tier 2/3）
    var parentId: UUID?              // 记忆层级（摘要的摘要）
}
```

- [x] 1.2 `MemoryPalaceApp.swift` Schema 注册 Memory（同时保留 MemoryNote 用于迁移）
- [x] 1.3 Build 验证

### Step 2: ChatService 非流式方法

- [x] 2.1 `BaseChatProvider` 新增 `sendNonStreaming()` 方法

```swift
/// 非流式调用，用于 memory agent 等后台任务
/// 复用现有 HTTP 请求逻辑，但不做 SSE 解析，等完整响应
func sendNonStreaming(
    messages: [(role: String, content: String)],
    model: String,
    systemPrompt: String?,
    apiKey: String,
    baseURL: String,
    extraHeaders: [String: String]
) async throws -> String
```

- [x] 2.2 `OpenAICompatibleProvider` 实现（设 `stream: false`，解析 `choices[0].message.content`）
- [x] 2.3 `AnthropicProvider` 实现（不发 `stream: true`，解析 `content[0].text`）
- [x] 2.4 `ProviderRouter` 暴露 `sendNonStreaming()`
- [x] 2.5 Build 验证

### Step 3: MemoryExtractor（AUDN 提取引擎）

- [x] 3.1 `MemoryExtractor` struct，核心方法：

```swift
struct MemoryExtractor {
    /// 分析最近对话，返回记忆操作列表
    func extract(
        recentMessages: [(role: String, content: String)],  // 最近 5 条
        existingMemories: [Memory],                          // 当前 profile 全部 hot+warm 记忆
        router: ProviderRouter,
        providerManager: ProviderManager,
        model: ProviderModel                                 // 便宜模型
    ) async throws -> [MemoryAction]

    /// 解析 LLM 返回的 JSON 为操作列表
    func parseActions(_ jsonString: String) -> [MemoryAction]
}

enum MemoryAction {
    case add(content: String, category: String, keywords: [String])
    case update(id: UUID, content: String, keywords: [String])
    case delete(id: UUID)
}
```

- [x] 3.2 提取 prompt 模板（research 中已定义）
- [x] 3.3 JSON 解析 + 容错处理（正则 fallback 提取 JSON 块）
- [x] 3.4 Build 验证

### Step 4: MemoryStore 重写

- [x] 4.1 `MemoryStore` protocol 适配新 Memory 模型：

```swift
protocol MemoryStore {
    // CRUD
    func add(content: String, category: String, keywords: [String],
             profileId: String, source: String, extractedBy: String,
             sourceConversationId: String?, context: ModelContext) throws -> Memory
    func update(id: UUID, content: String, keywords: [String], context: ModelContext) throws
    func delete(id: UUID, context: ModelContext) throws

    // 查询
    func listHot(profileId: String, context: ModelContext) -> [Memory]      // decayWeight ≥ 0.3
    func listHotAndWarm(profileId: String, context: ModelContext) -> [Memory] // decayWeight ≥ 0.05
    func listAll(profileId: String, context: ModelContext) -> [Memory]

    // 生命周期
    func recordAccess(id: UUID, context: ModelContext) throws   // accessCount++ & decayWeight 强化
    func applyDecay(profileId: String, context: ModelContext) throws  // 全部记忆时间衰减
}
```

- [x] 4.2 `SwiftDataMemoryStore` 实现
- [x] 4.3 Build 验证

### Step 5: MemoryInjector（注入格式化）

- [x] 5.1 `MemoryInjector` struct：

```swift
struct MemoryInjector {
    static let tokenBudget = 2000  // ~3000 中文字符

    /// 从 hot 记忆中选择注入内容，按权重排序，不超过 token 预算
    static func buildInjection(
        memories: [Memory],
        budget: Int = tokenBudget
    ) -> String

    /// 拼接到 system prompt
    static func inject(systemPrompt: String?, memories: [Memory]) -> String?
}
```

- [x] 5.2 注入格式：每条一行 `- 内容 [分类]`，按 `score = decayWeight × log(1 + accessCount)` 降序
- [x] 5.3 `isUserExplicit = true` 的记忆始终注入，不受预算限制
- [x] 5.4 token 粗算：`content.count × 1.5`（中文），达到预算时截断
- [x] 5.5 Build 验证

### Step 6: ConversationViewModel 集成

- [x] 6.1 替换 `buildSystemPrompt()`：改用 `MemoryInjector.inject()`

```swift
func buildSystemPrompt(base: String?, profileId: String, context: ModelContext) -> String? {
    let memories = memoryStore.listHot(profileId: profileId, context: context)
    return MemoryInjector.inject(systemPrompt: base, memories: memories)
}
```

- [x] 6.2 替换 `checkAndTriggerSummary()` → `extractMemoriesIfNeeded()`

每轮对话完成后异步调用：

```swift
func extractMemoriesIfNeeded(
    profileId: String,
    conversationId: String,
    model: ProviderModel,      // 便宜模型
    providerManager: ProviderManager,
    context: ModelContext
) {
    Task.detached { [weak self] in
        // 1. 取最近 5 条消息
        // 2. 取现有 hot+warm 记忆
        // 3. 调 MemoryExtractor.extract()
        // 4. 按返回的 actions 执行 add/update/delete
        // 5. 对注入过的记忆 recordAccess()
    }
}
```

- [x] 6.3 `sendMessage()` 中：`onComplete` 回调改为调 `extractMemoriesIfNeeded()`
- [x] 6.4 记忆注入时调 `memoryStore.recordAccess()` 更新访问计数和衰减权重
- [x] 6.5 选择便宜模型的逻辑：优先 Haiku → GPT-4o-mini → DeepSeek → 当前模型 fallback
- [x] 6.6 Build 验证

### Step 7: 衰减引擎

- [x] 7.1 `DecayEngine` struct：

```swift
struct DecayEngine {
    /// 计算记忆当前的有效权重（惰性计算，不写入）
    static func effectiveWeight(_ memory: Memory) -> Double {
        guard !memory.isUserExplicit else { return 1.0 }  // 用户手动的不衰减
        let days = Date().timeIntervalSince(memory.lastAccessedAt) / 86400
        return memory.decayWeight * exp(-0.1 * days)
    }

    /// 访问时强化
    static func reinforce(_ memory: Memory) {
        memory.decayWeight = min(1.0, memory.decayWeight + 0.2)
        memory.lastAccessedAt = Date()
        memory.accessCount += 1
    }

    /// 批量衰减：将 effectiveWeight 写回 decayWeight（app 启动时或会话切换时调用）
    static func applyDecay(memories: [Memory]) {
        for memory in memories {
            guard !memory.isUserExplicit else { continue }
            memory.decayWeight = effectiveWeight(memory)
            memory.lastAccessedAt = Date()  // 重置衰减起点
            // 检查 validUntil
            if let until = memory.validUntil, Date() > until {
                memory.decayWeight = min(memory.decayWeight, 0.05) // 过期→降到 cold
            }
        }
    }

    /// 温区分类
    static func tier(_ memory: Memory) -> MemoryTier {
        let w = effectiveWeight(memory)
        if memory.isUserExplicit || w >= 0.3 { return .hot }
        if w >= 0.05 { return .warm }
        return .cold
    }
}

enum MemoryTier { case hot, warm, cold }
```

- [x] 7.2 app 启动时调用 `applyDecay()` 刷新所有记忆权重
- [x] 7.3 Build 验证

### Step 8: 会话结束巩固

- [x] 8.1 `ConversationViewModel` 中，切换对话时触发巩固：

```swift
func consolidateSessionMemories(profileId: String, context: ModelContext) {
    // 1. applyDecay — 刷新衰减权重
    // 2. 检查是否有 validUntil 过期的记忆，标记为 cold
    // 3. （可选，后续扩展）调 LLM 检查矛盾
}
```

- [x] 8.2 `loadConversation()` 开头调用（切换对话 = 上一次会话结束）
- [x] 8.3 Build 验证

### Step 9: 记忆管理 UI

- [x] 9.1 SettingsView 新增记忆 tab（第 4 个 tab）

- [x] 9.2 记忆列表视图：
  - 按温区分组显示（hot / warm / cold）
  - 每条显示：内容、分类标签、来源（自动/手动）、创建时间、衰减权重指示
  - 温区用颜色区分：hot 绿点、warm 黄点、cold 灰点

- [x] 9.3 每条记忆的操作：
  - 编辑内容（inline 或弹窗）
  - 删除
  - 切换 isUserExplicit（"钉住"：设为手动 = 永不衰减）

- [x] 9.4 "新建记忆"按钮 — 手动添加（isUserExplicit = true）

- [x] 9.5 顶部统计：总记忆数、hot/warm/cold 各多少、token 使用量 / 预算

- [x] 9.6 Build 验证

### Step 10: 迁移 + 清理

- [x] 10.1 迁移逻辑（app 启动时，一次性）：
  - 查询所有 MemoryNote
  - manual note → 新 Memory（isUserExplicit=true, decayWeight=1.0, category="fact"）
  - auto note → 丢弃（下次对话会重新提取）
  - 迁移完成后在 UserDefaults 标记 `memoryMigrationV2Done = true`

- [x] 10.2 确认迁移无误后，从 Schema 中移除 MemoryNote（可以在下一个 commit）
- [x] 10.3 删除旧的 `Models/MemoryNote.swift`
- [x] 10.4 Final build 通过
- [x] 10.5 Commit + push

---

## 设计决策摘要

| 决策 | 选择 | 理由 |
|------|------|------|
| 提取时机 | 每轮异步 | 不漏信息，agent 自己判断要不要操作 |
| 提取模型 | 独立便宜模型 | 不占对话 token 窗口，成本极低 |
| 输出格式 | 结构化 JSON | 避免大改 ChatService 支持 tool call |
| 注入策略 | 全量注入 hot 记忆 | Tier 1 够用，≤50 条 |
| Token 预算 | 2000 | LibreChat 默认值，~40-60 条中文记忆 |
| 衰减函数 | 指数衰减 exp(-0.1t) | MemoryBank 论文验证，半衰期 ~7 天 |
| 温区阈值 | hot≥0.3, warm≥0.05, cold<0.05 | 参考 Generative Agents 三层设计 |
| 用户手动记忆 | 不衰减，始终注入 | 用户说"记住这个"就是最强信号 |
| 会话巩固 | 切换对话时 | 轻量，不需要后台调度 |
| 迁移策略 | manual→迁移，auto→丢弃 | auto note 质量不可靠，重新提取更好 |

---

## 不做的事

- ❌ 向量嵌入 / sqlite-vec（Tier 2/3，schema 预留了字段）
- ❌ BM25 关键词检索（记忆 ≤50 条时全量注入即可）
- ❌ 每日深度巩固 / "睡眠周期"（需要后台调度）
- ❌ 情感显著性评分（需要额外 LLM 调用）
- ❌ 重构式检索（属于 prompt engineering，人格系统时做）
- ❌ 世界书 / lorebook（关键词触发检索在 Tier 2 时自然实现）
- ❌ 宏/变量替换（属于 Phase 3 人格系统）
- ❌ 跨楼层记忆共享
- ❌ LLM 矛盾检测（会话巩固暂时只做衰减刷新，LLM 检查作为后续扩展）

---

## 执行顺序说明

Step 1-5 是基础设施，互相有依赖：1（模型）→ 2（非流式调用）→ 3（提取器）→ 4（存储层）→ 5（注入器）

Step 6 是集成层，把 1-5 串起来。

Step 7-8 是生命周期，依赖 4（存储层）。

Step 9 是 UI，依赖 4（存储层）+ 7（衰减引擎提供温区信息）。

Step 10 是收尾。

可以并行的：Step 7 和 Step 5 可以同时做（都只依赖 Step 4）。Step 9 可以在 Step 6 之后独立做。

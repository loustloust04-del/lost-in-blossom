# Plan: 上下文总结（最小版）

> 2026-04-18 | 基于 research-context-summary.md
> 对应 roadmap M7 / Phase 1.5

---

## 目标

聊超过 contextDepth 条时，旧消息不再直接丢弃，而是自动总结为摘要注入 prompt。

**不做**：独立总结模型配置、手动总结按钮、右栏管理面板、token 计数触发、总结提示词自定义。

---

## Task Checklist

### Task 0：确认记忆系统是否在跑（0.5h）

- [ ] 在 `extractMemoriesIfNeeded` 的 `catch` 块加 `print("⚠️ 记忆提取失败: \(error)")`
- [ ] 在 `parseActions` 返回空数组时加 `print("⚠️ 记忆提取: 模型返回无法解析")`
- [ ] 在 `executeActions` 每个 case 加 `print("✅ 记忆: add/update/delete ...")`
- [ ] 自己聊 5 轮，看 Xcode console 有没有日志
- [ ] 确认 cheapModel 选到了什么模型（print 出来）
- [ ] **如果记忆没跑通**：记录原因，作为单独 bug 修，不阻塞后续 task

> 改动文件：`ConversationViewModel.swift`（5 行 print），`MemoryService.swift`（2 行 print）
> build 验证

---

### Task 1：新建 `ContextSummarizer.swift`（1 天）

- [ ] 在 `MemoryPalace/Services/` 下新建文件

#### 1.1 数据结构

```swift
struct ContextSummary: Codable {
    let summary: String
    let coveredCount: Int      // 摘要覆盖的旧消息条数
    let updatedAt: Date
}
```

#### 1.2 存取方法

```swift
struct ContextSummarizer {
    // key = "ctxSummary_{conversationId}"
    static func load(conversationId: String) -> ContextSummary?
    static func save(_ summary: ContextSummary, conversationId: String)
    static func clear(conversationId: String)
}
```

存 UserDefaults，JSON 编解码。简单可靠，不动 SwiftData schema。

#### 1.3 判断是否需要总结

```swift
/// 返回需要总结的旧消息（如果不需要总结返回 nil）
static func messagesToSummarize(
    allMessages: [(role: String, content: String)],
    contextDepth: Int,
    conversationId: String
) -> (oldMessages: [(role: String, content: String)], existingSummary: ContextSummary?)?
```

逻辑：
- `allMessages.count <= contextDepth` → 不需要（还没超）
- 旧消息 = `allMessages[0 ..< (count - contextDepth)]`
- 已有摘要且 `coveredCount == 旧消息数` → 不需要（没有新增）
- 否则返回旧消息 + 已有摘要

#### 1.4 构建总结请求

```swift
static func buildSummaryRequest(
    oldMessages: [(role: String, content: String)],
    existingSummary: ContextSummary?
) -> (systemPrompt: String, messages: [(role: String, content: String)])
```

**两种情况**：

**首次总结**（无已有摘要）：
```
system: 你是一个对话摘要助手。请总结以下对话历史的要点。

保留：
1. 用户提出的主要话题和需求
2. AI 给出的关键回答和结论
3. 做出的决策和达成的共识
4. 未解决的问题
5. 重要的名字、数字、日期等具体细节

用简洁的段落形式输出，控制在 800 字以内。
直接输出摘要，不要加标题或格式标记。

user: [格式化的旧消息]
```

**增量更新**（有已有摘要）：
```
system: 你是一个对话摘要助手。请在已有摘要的基础上，合并新发生的对话内容，输出更新后的摘要。

保留所有重要信息，控制在 800 字以内。
直接输出摘要，不要加标题或格式标记。

user:
已有摘要：
---
{existingSummary.summary}
---

新增对话：
---
{格式化的新增消息（仅 coveredCount 之后的部分）}
---

请输出合并后的完整摘要。
```

#### 1.5 执行总结

```swift
static func summarize(
    allMessages: [(role: String, content: String)],
    contextDepth: Int,
    conversationId: String,
    model: ProviderModel,
    providerManager: ProviderManager
) async throws
```

逻辑：
1. 调 `messagesToSummarize` 判断是否需要
2. 调 `buildSummaryRequest` 构建请求
3. 调 `ProviderRouter().sendNonStreaming` 执行
4. 把响应文本存为 `ContextSummary`
5. fire-and-forget，失败静默（跟记忆提取一样）

> build 验证

---

### Task 2：改 `PromptAssembler.swift`（0.5 天）

- [ ] `assemble()` 新增参数 `contextSummary: String? = nil`
- [ ] 在 system prompt 组装时，如果 contextSummary 不为空，在记忆注入（memoryInjectionId）之后追加一个 system part：

```swift
if let summary = contextSummary, !summary.isEmpty {
    systemParts.append((tag: "contextSummary", content: "[对话历史摘要]\n\(summary)"))
}
```

位置逻辑：找到 memoryInjectionId 的 index，在其后面插入。如果没有 memoryInjection，直接 append。

- [ ] `preview()` 也传入 contextSummary，让组装预览能看到摘要

> 只改这一个文件，不动其他逻辑
> build 验证

---

### Task 3：改 `ConversationViewModel.swift`（0.5 天）

#### 3.1 assemblePrompt 读取摘要

- [ ] 在 `assemblePrompt()` 里，读取当前对话的摘要：

```swift
let conversationId = selectedConversation?.id ?? ""
let contextSummary = ContextSummarizer.load(conversationId: conversationId)?.summary
```

- [ ] 传给 `PromptAssembler.assemble(..., contextSummary: contextSummary)`

#### 3.2 sendMessage 的 onComplete 触发总结

- [ ] 在 `sendMessage()` 的 `onComplete` 闭包里，**记忆提取之后**，加总结触发：

```swift
// 上下文总结（异步，不阻塞）
let allMsgs = self.buildAPIMessages()  // 不限制条数，拿全部
let depth = preset.sampling.contextDepth
let cid = conversation.id
let sumModel = self.cheapModel(providerManager: providerManager, fallback: model)
Task.detached {
    try? await ContextSummarizer.summarize(
        allMessages: allMsgs,
        contextDepth: depth,
        conversationId: cid,
        model: sumModel,
        providerManager: providerManager
    )
}
```

#### 3.3 buildAPIMessages 支持不限条数

- [ ] 当前 `buildAPIMessages(excluding:maxMessages:)` 的 maxMessages 默认 40。总结触发时需要传 `maxMessages: Int.max` 拿到全部历史（用于判断旧消息数量）
- [ ] 或者新增一个无截断的重载：`buildAllAPIMessages()` → 调用 `buildAPIMessages(maxMessages: Int.max)`

#### 3.4 regenerate / editAndResend 也接入

- [ ] `regenerate()` 和 `editAndResend()` 的 `assemblePrompt` 调用也需要传摘要（同 3.1 的方式，改动一样）
- [ ] 这两个的 onComplete 也触发总结（同 3.2）

> build 验证
> 运行 app，聊 50+ 条消息，观察：
> - console 是否有总结触发日志
> - 组装预览（Prompt tab → 最终请求预览）里是否出现摘要
> - AI 是否能引用摘要中的旧信息

---

### Task 4：清理（0.5 天）

- [ ] 对话删除时清理摘要：在删除对话的逻辑里加 `ContextSummarizer.clear(conversationId:)`
- [ ] Task 0 加的 debug print 改为 `#if DEBUG` 包裹或删除
- [ ] 确认导入的旧对话（ChatGPT/Claude 导入）不会误触发总结（只有 API 对话才触发）
- [ ] build 通过
- [ ] git commit + push

---

## 文件改动汇总

| 文件 | 改动类型 | 行数估计 |
|------|----------|----------|
| `Services/ContextSummarizer.swift` | **新建** | ~150 行 |
| `Services/PromptAssembler.swift` | 改 | +10 行（新参数 + 注入逻辑） |
| `ViewModels/ConversationViewModel.swift` | 改 | +30 行（读摘要 + 触发总结） |
| `Services/MemoryService.swift` | 改 | +5 行（debug 日志） |

**总计：~200 行新代码**，不改 SwiftData 模型，不改 UI。

---

## 风险

| 风险 | 缓解 |
|------|------|
| cheapModel 不可用 | 跟记忆一样 fallback 到当前模型，最差情况是费一点 |
| 总结质量差 | 先用着，后续可换 prompt 或换模型 |
| 摘要太长撑爆 context | prompt 里限制 800 字，约 400 token，远小于 context 预算 |
| UserDefaults 存太多摘要 | 每个对话一条，1000 个对话也才 ~800KB，可接受 |
| 并发问题（总结还没完成又发了新消息） | fire-and-forget + 条数检查，最多重复总结一次，无副作用 |

---

## 验证标准

1. 聊 50 条消息，AI 能引用第 1-10 条里提到的关键信息 ✅
2. 组装预览里能看到 `[对话历史摘要]` 段 ✅
3. 摘要在对话间持久化（退出重进还在）✅
4. 导入的旧对话不触发总结 ✅
5. build 零 warning ✅

---

*等粟粟确认后开工。按 Task 0 → 1 → 2 → 3 → 4 顺序执行，每完成一个 build 验证。*

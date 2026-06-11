# P0 修复：对照粟粟的实现，在我们的代码上重写

> 日期：2026-06-11
> 参考：粟粟的代码在 /root/projects/SusuPalace/
> 原则：不搬代码，对照思路在我们的代码基础上写。

---

## P0-2: 角色卡问候对话补 profileId（最简单，先做）

**问题**：CharacterCard 创建问候对话时没传 profileId，对话进了"无主桶"，任何楼层都查不到。

**文件**：`MemoryPalace/Models/CharacterCard.swift`

**改法**：找到 `importCardContent` 函数里创建 Conversation 和 MessageNode 的地方（约139-148行）。

当前代码：
```swift
let conversation = Conversation(
    id: convId, title: greeting.title,
    createTime: now, updateTime: now,
    currentNodeId: nodeId, provider: "sillytavern"
)
```

加上 `profileId: profile.id`：
```swift
let conversation = Conversation(
    id: convId, title: greeting.title,
    createTime: now, updateTime: now,
    currentNodeId: nodeId, provider: "sillytavern",
    profileId: profile.id
)
```

MessageNode 同样加 `profileId: profile.id`：
```swift
let node = MessageNode(
    id: nodeId, role: "assistant",
    content: Self.normalizeNewlines(greeting.content),
    contentType: "text", createTime: now,
    parentId: nil, childrenIds: [], conversationId: convId,
    profileId: profile.id
)
```

**参考**：粟粟 commit 1c6eeee，CharacterCard.swift diff

**commit**：`fix(import): P0-2 角色卡问候对话补 profileId`

---

## P0-4: 世界书删除加确认弹窗（简单）

**问题**：点世界书旁的 ✕ 直接删除整本书，没有确认。用户以为是"解绑"。

**文件**：`MemoryPalace/Views/GeneralSettingsTab.swift`

**注意**：这个文件有两处 `unbindWorldBook`（可能 macOS 和 iOS 各一处），都要改。

**改法**：

1. 加一个状态变量：
```swift
@State private var wbPendingDelete: WorldBook? = nil
```

2. 把 `unbindWorldBook(book)` 的调用改成 `wbPendingDelete = book`

3. 在 section 末尾加确认弹窗：
```swift
.confirmationDialog("删除世界书",
    isPresented: Binding(
        get: { wbPendingDelete != nil },
        set: { if !$0 { wbPendingDelete = nil } }
    ),
    titleVisibility: .visible
) {
    Button("删除", role: .destructive) {
        if let book = wbPendingDelete { deleteWorldBook(book) }
        wbPendingDelete = nil
    }
    Button("取消", role: .cancel) { wbPendingDelete = nil }
} message: {
    if let book = wbPendingDelete {
        Text("确定要删除「\(book.name)」吗？包含 \(book.entries.count) 个条目，不可恢复。")
    }
}
```

4. 把 `unbindWorldBook` 函数改名为 `deleteWorldBook`，加 do-catch：
```swift
private func deleteWorldBook(_ book: WorldBook) {
    modelContext.delete(book)
    if var profile = profileManager?.currentProfile {
        profile.linkedWorldBookIDs.removeAll { $0 == book.id.uuidString }
        profileManager?.updateProfile(profile)
    }
    do { try modelContext.save() } catch {
        print("[worldbook] 删除保存失败: \(error)")
    }
}
```

**参考**：粟粟 commit 83c1488，GeneralSettingsTab.swift diff

**commit**：`fix(worldbook): P0-4 世界书删除加确认弹窗`

---

## P0-1: 跨楼层 upsert 防护（最大，最后做）

**问题**：SwiftData 的 @Attribute(.unique) 在 insert 撞 id 时做 upsert，会把别的楼层的对话静默"抢"过来。

**文件**：`MemoryPalace/Services/ImportSupport.swift`（加新函数）+ `ConversationImporter.swift` + `ClaudeImporter.swift`

**改法**：

### 步骤1：在 ImportSupport.swift 末尾加跨楼层查重函数

```swift
// MARK: - P0-1 跨楼层冲突防护

private let crossProfileQueryBatchSize = 500

/// 返回 candidateIds 中已被其它楼层占用的 Conversation id 集合
func findCrossProfileConversationConflicts(
    candidateIds: [String],
    currentProfileId: String,
    in context: ModelContext
) throws -> Set<String> {
    var conflicts = Set<String>()
    guard !candidateIds.isEmpty else { return conflicts }
    for start in stride(from: 0, to: candidateIds.count, by: crossProfileQueryBatchSize) {
        let chunk = Array(candidateIds[start..<min(start + crossProfileQueryBatchSize, candidateIds.count)])
        let pid = currentProfileId
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { chunk.contains($0.id) && $0.profileId != pid }
        )
        for hit in try context.fetch(descriptor) {
            conflicts.insert(hit.id)
        }
    }
    return conflicts
}

/// 返回 candidateIds 中已被其它楼层占用的 MessageNode id 集合
func findCrossProfileNodeConflicts(
    candidateIds: [String],
    currentProfileId: String,
    in context: ModelContext
) throws -> Set<String> {
    var conflicts = Set<String>()
    guard !candidateIds.isEmpty else { return conflicts }
    for start in stride(from: 0, to: candidateIds.count, by: crossProfileQueryBatchSize) {
        let chunk = Array(candidateIds[start..<min(start + crossProfileQueryBatchSize, candidateIds.count)])
        let pid = currentProfileId
        let descriptor = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { chunk.contains($0.id) && $0.profileId != pid }
        )
        for hit in try context.fetch(descriptor) {
            conflicts.insert(hit.id)
        }
    }
    return conflicts
}

/// 一个 batch 里需要跳过的对话 id 集合
func crossProfileConflictedConversationIds(
    payloads: [ImportedConversationPayload],
    currentProfileId: String,
    in context: ModelContext
) throws -> Set<String> {
    guard !payloads.isEmpty else { return [] }
    var conflicted = try findCrossProfileConversationConflicts(
        candidateIds: payloads.map(\.id),
        currentProfileId: currentProfileId,
        in: context
    )
    let nodeConflicts = try findCrossProfileNodeConflicts(
        candidateIds: payloads.flatMap { $0.nodes.map(\.id) },
        currentProfileId: currentProfileId,
        in: context
    )
    if !nodeConflicts.isEmpty {
        for payload in payloads where payload.nodes.contains(where: { nodeConflicts.contains($0.id) }) {
            conflicted.insert(payload.id)
        }
    }
    return conflicted
}

func crossProfileConflictSuffix(_ count: Int) -> String {
    count > 0 ? "；⚠️ \(count) 条对话已存在于其他楼层，已跳过" : ""
}
```

### 步骤2：在 ConversationImporter.swift 的 normal import 和 merge import 批处理循环里加防护

在 `for batchStart in stride(...)` 循环内，在遍历 batch 之前：
```swift
let batchPayloads = batch.map { makePayload(from: $0) }
let conflictedIds = try crossProfileConflictedConversationIds(
    payloads: batchPayloads.filter { !existingConversationIds.contains($0.id) },
    currentProfileId: scopedProfileId,
    in: context
)
```

然后在每条对话写入前检查：
```swift
if conflictedIds.contains(incoming.id) {
    crossProfileConflicts += 1
    continue
}
```

完成文案加后缀：`+ crossProfileConflictSuffix(crossProfileConflicts)`

### 步骤3：ClaudeImporter.swift 同样加防护（逻辑完全一样）

**参考**：粟粟 commit 873ab9c 的完整 diff
**参考文件**：`/root/projects/SusuPalace/MemoryPalace/Services/ImportSupport.swift`（第42-108行）

**commit**：`fix(import): P0-1 跨楼层 upsert 防护`

---

## 规则

- 按 P0-2 → P0-4 → P0-1 顺序做，每个单独 commit + push
- 只改列出的文件，不碰其他文件
- 不加新的依赖或类型
- 参考粟粟代码时只看逻辑，不直接复制粘贴（避免引入我们没有的类型引用）
- 禁触文件：MemoryPalaceApp.swift（别再碰它了）

## 验证清单

- [ ] build 通过
- [ ] 新建楼层导入带角色卡 → 问候对话出现在新楼层（P0-2）
- [ ] 设置→通用 点世界书 ✕ → 弹确认弹窗，取消不删除（P0-4）
- [ ] 楼层 A 导入一份 ChatGPT 导出，切楼层 B 导入同一份 → 提示"N 条已存在于其他楼层，已跳过"（P0-1）

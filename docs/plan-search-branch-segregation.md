# Plan：搜索分支隔离 + 主线导航修复

**日期**：2026-05-08
**Research**：`docs/research-search-branch-segregation.md`
**目标**：粟粟的 6 条预期 ①-⑥ 全部满足
**预计工作量**：8 个 task，~2-3 小时

---

## 决策定档

| 问题 | 决策 |
|---|---|
| Q1 默认"全部"内容搜索只搜主线 | ✅ 是 |
| Q2 分支结果点击行为 | **A. 切 branch + toast "已切换到分支 N"** |
| Q3 分支结果视觉区分 | **加 🌿 标签 + 缩进** |
| Q4 自动 page 切换实现 | **NotificationCenter（解耦）** |
| Q5 navigate 去抖窗口 | **300ms** |

---

## Task checklist

### [ ] T1. 提取 main path helper（不影响行为，仅复用准备）

**文件**：`MemoryPalace/ViewModels/ConversationViewModel.swift`

新增 static func（放在 buildTreeInBackground 旁边）：

```swift
/// 给定 nodes 和 currentNodeId 算出主线 nodeId 集合。
/// 用 buildTreeInBackground 的同一套算法（trace + 顺向）。
/// 重复在搜索 / mainPath UI 显示等多处使用。
static func computeMainPathSet(
    nodes: [MessageNode],
    currentNodeId: String
) -> Set<String>
```

实现：复制 buildTreeInBackground 行 200-302 的核心逻辑（infoMap 构建 + ancestor chase + mainPathIds trace + 顺向 pathNodeIds 构建），但只返回 `Set(pathNodeIds)`。

**重要**：原 buildTreeInBackground 不重写、不复用本 helper（避免回归风险）。两个并存，算法保持一致是契约。

**验证**：单测不写，跑一次 17 Air 复现，对比金瓶梅对话的 mainPath 数字应等于 buildTree 出口打的 `pathNodeIds=180`。

---

### [ ] T2. SearchResourceKind 加 .branchContent

**文件**：`MemoryPalace/Services/SearchService.swift`

```swift
enum SearchResourceKind: String, CaseIterable {
    case conversation       // "全部" — 标题 + 内容（内容仅主线）
    case branchContent      // 🌿 分支 — 仅搜分支气泡内容
    case sticker
    case characterCard
    case worldBook
    case memory
}
```

---

### [ ] T3. fetchContentWithKeyword 加主线过滤

**文件**：`MemoryPalace/Services/SearchService.swift`

`performSearch` 行 144-176 现状：
```swift
var contentNodes = fetchContentWithKeyword(...)
// 时间过滤
for node in contentNodes {
    // 直接进 contentByConv
}
```

改成：

```swift
var contentNodes = fetchContentWithKeyword(...)
// 时间过滤（不变）

// === 新增：主线/分支过滤 ===
let needsMainPathFilter = filter.resourceKind == .conversation || filter.resourceKind == .branchContent
if needsMainPathFilter {
    // 按 conversationId group
    let nodesByConv = Dictionary(grouping: contentNodes) { $0.conversationId }
    var allowedNodeIds = Set<String>()

    for (convId, nodesInConv) in nodesByConv {
        // fetch this conversation 的 currentNodeId + 全部 nodes
        let cid = convId
        let pid = scopedProfileId
        let convDesc = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { $0.id == cid && $0.profileId == pid }
        )
        guard let conv = try? context.fetch(convDesc).first else { continue }

        let allNodesDesc = FetchDescriptor<MessageNode>(
            predicate: #Predicate<MessageNode> { $0.conversationId == cid && $0.profileId == pid }
        )
        let allNodes = (try? context.fetch(allNodesDesc)) ?? []
        let mainPathSet = ConversationViewModel.computeMainPathSet(
            nodes: allNodes,
            currentNodeId: conv.currentNodeId
        )

        for node in nodesInConv {
            switch filter.resourceKind {
            case .conversation:
                if mainPathSet.contains(node.id) { allowedNodeIds.insert(node.id) }
            case .branchContent:
                if !mainPathSet.contains(node.id) { allowedNodeIds.insert(node.id) }
            default:
                break
            }
        }
    }

    contentNodes = contentNodes.filter { allowedNodeIds.contains($0.id) }
}

// 后续不变
for node in contentNodes { ... }
```

**性能预算**：keyword 命中 N 个 conv → N 次 fetch + N 次 computeMainPathSet。N=62 conv，每次 fetch+trace ~3ms → ~200ms。如果实测 >500ms 加 PROBE PERF 优化（可考虑批量 fetch）。

---

### [ ] T4. SidebarView typeChip 加 🌿 分支

**文件**：`MemoryPalace/Views/SidebarView.swift` 行 2351-2359

```swift
HStack {
    categoryLabel("类型")
    typeChip("全部", kind: .conversation)
    typeChip("🌿 分支", kind: .branchContent)        // 新增
    typeChip("🎨 贴纸", kind: .sticker)
    typeChip("👤 助手模板", kind: .characterCard)
    typeChip("📚 世界书", kind: .worldBook)
    typeChip("🧠 记忆", kind: .memory)
}
```

`.branchContent` 走 conversation 的搜索路径（行 200-263 的 perform），所以不需要新增 resourceResultsView 分支——只复用现有 content row 渲染。

---

### [ ] T5. 搜索结果行加视觉区分（仅 branchContent）

**文件**：`MemoryPalace/Views/SidebarView.swift`

在 ContentMatchRow 那一段（行 1758-1774）或 searchContentRow（行 1714 起），根据当前 `searchFilter.resourceKind == .branchContent` 加视觉：

```swift
ContentMatchRow(...)
    .padding(.leading, searchFilter.resourceKind == .branchContent ? 32 : 16)
    .overlay(alignment: .topLeading) {
        if searchFilter.resourceKind == .branchContent {
            Text("🌿")
                .font(.system(size: 11))
                .padding(.leading, 8)
                .padding(.top, 4)
                .opacity(0.6)
        }
    }
```

**注意**：先看下 ContentMatchRow 的当前 padding，避免破坏现有布局。

---

### [ ] T6. navigateToNodeById 改造（核心修复）

**文件**：`MemoryPalace/Views/SidebarView.swift` 行 1334-1343

改成：

```swift
@State private var lastNavigateAt: Date? = nil
@State private var lastNavigateNodeId: String? = nil

private func navigateToNodeById(_ nodeId: String, conversationId: String) {
    // 300ms 去抖：同 nodeId 短时间重复点击直接跳过
    let now = Date()
    if let last = lastNavigateAt, lastNavigateNodeId == nodeId,
       now.timeIntervalSince(last) < 0.3 {
        return
    }
    lastNavigateAt = now
    lastNavigateNodeId = nodeId

    let cid = conversationId
    let pid = profileManager?.currentProfile.id ?? ""
    let convDesc = FetchDescriptor<Conversation>(
        predicate: #Predicate<Conversation> { conv in conv.id == cid && conv.profileId == pid }
    )
    guard let conversation = try? modelContext.fetch(convDesc).first else { return }

    // 判断 nodeId 是否在主线上
    let allNodesDesc = FetchDescriptor<MessageNode>(
        predicate: #Predicate<MessageNode> { $0.conversationId == cid && $0.profileId == pid }
    )
    let allNodes = (try? modelContext.fetch(allNodesDesc)) ?? []
    let mainPathSet = ConversationViewModel.computeMainPathSet(
        nodes: allNodes,
        currentNodeId: conversation.currentNodeId
    )
    let isOnMainPath = mainPathSet.contains(nodeId)

    viewModel.pendingScrollNodeId = nodeId

    if isOnMainPath {
        // 主线 node：path 不切，scroll 即可
        viewModel.loadConversation(conversation, context: modelContext)
    } else {
        // 分支 node：切 branch + toast
        viewModel.loadConversation(conversation, context: modelContext, scrollTargetNodeId: nodeId)
        // 弹 toast（用现有 ToastManager 或新建）
        ToastManager.shared.show("已切换到分支")
    }

    // 触发 page 0→1 切换
    NotificationCenter.default.post(name: .conversationNavigationRequested, object: nil)
}
```

**两处微 bug 修复**：
- 同 conv search 重复点击不再每次都重 build tree（现在的 loadConversation 不会 short-circuit，T6 也不加 short-circuit；但去抖防 300ms 内连点）
- 主线 node 走"不切 branch"路径

---

### [ ] T7. ContentView 加 NotificationCenter 监听切 page

**文件**：`MemoryPalace/Views/ContentView.swift`

新增 Notification.Name extension（放在合适的位置，可能新建 `MemoryPalace/Models/Notifications.swift` 如果还没有）：

```swift
extension Notification.Name {
    static let conversationNavigationRequested = Notification.Name("conversationNavigationRequested")
}
```

ContentView 行 385-389 旁边加：

```swift
.onReceive(NotificationCenter.default.publisher(for: .conversationNavigationRequested)) { _ in
    if iOSPage != 1 {
        withAnimation { iOSPage = 1 }
    }
}
```

**注意**：现有 `.onChange(of: viewModel.selectedConversation?.id)`（行 385）保留不动——它处理切到不同对话的情况；新通知处理同 conv 的搜索点击。

---

### [ ] T8. ToastManager 检查（如果不存在则简实现）

先 grep `ToastManager` 看有没有。
- 有 → 直接调
- 没有 → 在 ConversationViewModel 加一个 `transientToast: String? = nil`，让某 view 监听显示

如果新建 ToastManager 太重，**退化为 simpler 方案**：直接在 ConversationViewModel 里加 `@Observable transientToast: (text: String, id: UUID)?`，CardFlowView 监听显示。

---

### [ ] T9. 移除 PROBE B20-2

commit 4399691 加的 PROBE 已经完成使命，移除：
- `MemoryPalace/ViewModels/ConversationViewModel.swift`：buildTree 出口、applyTree 出口的 print
- `MemoryPalace/Views/SidebarView.swift`：navigateToNodeById 入口的 print

也包括 `var fallbackTriggered = false`（不再需要）—— 还原回 if 直接判断。

---

### [ ] T10. 双端 build + 17 Air 真机验证

```bash
cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace"
xcodegen generate
xcodebuild -scheme MemoryPalace build         # macOS
xcodebuild -scheme MemoryPalaceIOS -destination 'generic/platform=iOS Simulator' build
```

17 Air 真机复现金瓶梅对话场景：
- [ ] ① 进对话 → path 完整 180 条
- [ ] 搜 "话本" → 默认"全部"类目，结果都在主线（不出现分支 node）
- [ ] 点结果 → 自动从 sidebar 翻到 chat page
- [ ] 点结果 → scroll 到那条气泡
- [ ] 点结果 → 主对话仍 180 条（不切 branch）
- [ ] 切到 🌿 分支 类目 → 搜 "话本" → 出现的全是分支气泡（视觉有 🌿 标 + 缩进）
- [ ] 点分支结果 → 自动 page + scroll + 切 branch + 弹 toast "已切换到分支"
- [ ] 短时间连点同一 result 5 次 → 只 trigger 1 次 navigate（300ms 去抖生效）

---

### [ ] T11. commit + push + 标 roadmap

- commit 1: T1 helper（不影响行为）
- commit 2: T2-T5 搜索分支隔离 UI + 数据
- commit 3: T6 navigateToNodeById 重构 + 去抖
- commit 4: T7-T8 自动 page 切换 + toast
- commit 5: T9 移除 PROBE
- commit 6: docs/PROJECT_ROADMAP.md 标 B20 ✅

---

## 风险与回退

### 风险点

1. **mainPath 算法漂移**：T1 helper 的算法跟 buildTreeInBackground 必须一致。如果有 bug → "明明能看到的气泡搜不出来"。**修法**：做 helper 时小心抄写，跑 17 Air 实测对比。

2. **性能 200ms+**：N=62 conv 搜索 → N 次 fetch + N 次 trace。如果用户 keyword 命中 200+ conv 可能 800ms 卡顿。**修法**：先实现简单版，T10 验证时打 [PERF] 时间，超 500ms 再优化（缓存 mainPath / 批量 fetch）。

3. **分支 toast 干扰**：每点一次都弹 toast 用户烦。**修法**：toast 只在"实际发生 branch 切换"时弹，同分支再点不弹。

4. **去抖误伤**：300ms 内用户主动想切到不同 search result（点 a 又点 b）会被吃掉。**修法**：去抖 key = nodeId，**不同 nodeId 不去抖**（T6 实现已包含）。

### 回退路径

- 如果 mainPath helper 写错出 regression → revert T1-T3，保留 T6/T7/T8（即 a/b/c/d/e 修，f 不修）。粟粟仍然能用，只是默认搜索还是含分支结果。
- 如果 ToastManager 没现成 + 实现太重 → 跳 T8，改成"分支结果点击后在 chat 顶部 PinBar 临时显示分支 chip 高亮"作为视觉反馈。

---

## 实施顺序

```
T9 (清 PROBE) → T1 (helper) → T2-T5 (搜索过滤 + UI) → T6 (导航重构)
              → T7 (Page 切换通知) → T8 (Toast) → T10 (验证) → T11 (commit)
```

**关键检查点**：每个 commit 后 `xcodebuild` 验证编译，跑 17 Air 验证关键路径不 regress。

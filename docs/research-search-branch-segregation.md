# Research：搜索分支隔离 + 主线导航修复

**日期**：2026-05-08
**触发**：B20 part 2（搜索点击导致对话气泡"消失一大截"）
**关联**：`docs/research-b20-sticker-overflow.md`（B20 part 1 贴纸出格已修复）
**状态**：research，待粟粟确认后写 plan

---

## 一、症状（粟粟现场描述 + log 印证）

### 现场全程（粟粟）

```
1. 进金瓶梅对话                    → 对话从头到尾完整显示 ✅
2. 搜索关键词 "话本"                → 搜出 62 个对话, 137 条结果（截图 1）
3. 点击搜索结果 a                   → 视觉无反应（page 还在 sidebar）
4. 手动从 page0(sidebar) 翻到 page1(chat)  → 对话末尾消失了一大截
5. 点击搜索结果 b                   → 对话又在另一个中间结束
```

### 粟粟的预期

| 序 | 预期 |
|---|---|
| ① | 主对话永远完整（搜索不改对话内容显示） |
| ② | 搜索结果不修改对话本身的状态 |
| ③ | 点搜索结果 → 自动跳到 chat page + scroll 到那条 |
| ④ | 默认内容搜索只搜主分支气泡，不出现分支 node |
| ⑤ | 单独类目"分支"，选了才搜分支气泡 |
| ⑥ | 不能每次回主线都要重新选好多遍分支 |

---

## 二、log 印证（17 Air 真机一次复现）

PROBE 在 commit 4399691。复现 log 关键行：

```
# 直接进金瓶梅
[PROBE B20-2 buildTree] currentNodeId=019db120 inMap=true infoMap=251
                       mainPath=180 pathNodeIds=180 fallback=false
[PROBE B20-2 applyTree] currentPath=180 nodeMap=251 droppedByCompactMap=0

# 点搜索结果 a (019daae9)
[PROBE B20-2 navigate] tapNodeId=019daae9 savedCurrentNodeId=019db120
[PROBE B20-2 buildTree] currentNodeId=019daae9 mainPath=120 pathNodeIds=128
[PROBE B20-2 applyTree] currentPath=128 droppedByCompactMap=0 pendingInPath=true

# 点搜索结果 b (019daa61)
[PROBE B20-2 navigate] tapNodeId=019daa61 savedCurrentNodeId=019db120
[PROBE B20-2 buildTree] currentNodeId=019daa61 mainPath=84 pathNodeIds=84
[PROBE B20-2 applyTree] currentPath=84 droppedByCompactMap=0 pendingInPath=true
```

### 三条铁的事实

1. **没有数据丢失**：`droppedByCompactMap=0`、`nodeMap=251` 始终满，`fallback=false`。SwiftData fetch 完整。
2. **path 变短是 by design**：搜索点击的 `tapNodeId` 被作为 path 起点 trace mainPathIds，搜索结果在哪条 branch 就只走那条 branch（180→128→84）。
3. **conversation.currentNodeId 全程没变**（`savedCurrentNodeId=019db120` 始终）。说明持久化数据没坏，问题是**渲染层面**的 path 切换。

### 性能/UX bug

- 同一 nodeId 触发了 **19 次** navigate（log 时间戳间隔 1-2s）。粟粟"点了没反应又点几次"。
- 每次都重 build tree（"buildTreeInBackground=30~58ms"）+ rebuild applyTreeData。

---

## 三、当前代码事实

### 1. 搜索代码结构

**文件**：`MemoryPalace/Services/SearchService.swift`

```swift
enum SearchResourceKind: String, CaseIterable {
    case conversation     // 对话（标题 / 内容 / 标题+内容）
    case sticker          // 贴纸
    case characterCard    // 角色卡
    case worldBook        // 世界书条目
    case memory           // 记忆
}

struct SearchFilter {
    var keyword: String
    var dateRange: DateRange
    var roles: Set<String>           // ["user", "assistant"]
    var sortOrder: SearchSort
    var scope: SearchScope            // .titleOnly / .contentOnly / .both
    var resourceKind: SearchResourceKind = .conversation
    var conversationIdScope: Set<String>? = nil
    var includeDeletedConversations: Bool = false
}
```

**`fetchContentWithKeyword`**（行 250-288）：
- SwiftData predicate：`profileId + isDeleted=false + role ∈ {user,assistant} + content.localizedStandardContains(keyword)`
- **不区分主分支/分支**，所有 displayable node 都进结果集
- 返回 `[MessageNode]`

### 2. 搜索结果点击路径

**文件**：`MemoryPalace/Views/SidebarView.swift`

行 1769-1774（ContentMatchRow.onTapGesture）：
```swift
.onTapGesture {
    if let idx = flatMatches.firstIndex(where: { $0.id == match.id }) {
        currentMatchIndex = idx
    }
    navigateToNodeById(match.id, conversationId: match.conversationId)
}
```

行 1334-1343（navigateToNodeById）：
```swift
private func navigateToNodeById(_ nodeId: String, conversationId: String) {
    ...
    viewModel.pendingScrollNodeId = nodeId
    viewModel.loadConversation(
        conversation,
        context: modelContext,
        scrollTargetNodeId: nodeId    // ← bug 根源：把 search nodeId 当 path 起点
    )
}
```

### 3. path 切换机制

**文件**：`MemoryPalace/ViewModels/ConversationViewModel.swift`

行 153：`let currentNodeId = scrollTargetNodeId ?? conversation.currentNodeId`

行 254-261（trace mainPath 从 currentNodeId 反向到 root）：
```swift
var mainPathIds = Set<String>()
var rootId: String? = nil
var traceId: String? = currentNodeId
while let nid = traceId, let info = infoMap[nid] {
    mainPathIds.insert(nid)
    if info.parentId == nil || infoMap[info.parentId ?? ""] == nil {
        rootId = nid
    }
    traceId = info.parentId
}
```

行 297-300（顺向构建 pathNodeIds 时分叉选 child）：
```swift
} else {
    let mainChild = children.first(where: { mainPathIds.contains($0) })
    currentId = mainChild ?? children[0]
}
```

→ 传 `scrollTargetNodeId=搜索nodeId` ⇒ trace 路径只覆盖 search 节点所在的 branch ⇒ 顺向走时只走那条 branch ⇒ pathNodeIds 短。

### 4. 自动切 page（iOSPage 0→1）的现状

**文件**：`MemoryPalace/Views/ContentView.swift`

行 43：`@State private var iOSPage: Int = 1`（私有 state，外部访问不到）

行 385-389：
```swift
.onChange(of: viewModel.selectedConversation?.id) { _, newId in
    if newId != nil && iOSPage == 0 {
        withAnimation { iOSPage = 1 }
    }
}
```

→ 监听 `selectedConversation?.id` 变化才切 page。**搜索点击同一对话时 id 不变 → onChange 不触发 → page 不切**。这就是"点了没反应"的根因。

### 5. 类型筛选 UI

**文件**：`MemoryPalace/Views/SidebarView.swift` 行 2351-2359

```swift
HStack {
    categoryLabel("类型")
    typeChip("全部", kind: .conversation)
    typeChip("🎨 贴纸", kind: .sticker)
    typeChip("👤 助手模板", kind: .characterCard)
    typeChip("📚 世界书", kind: .worldBook)
    typeChip("🧠 记忆", kind: .memory)
}
```

可以扩展加 `.branchContent` 或类似 case。

---

## 四、技术挑战

### 主分支判断需要的信息

要在搜索时过滤掉非主线 node，每个 conversation 都要知道"它的主线 path 包含哪些 nodeId"。

**主线判定算法**（来自 ConversationViewModel.buildTreeInBackground）：

```
输入: conversation.currentNodeId, 该 conversation 的所有 MessageNode
1. fetch 所有 nodes → infoMap[id → NodeInfo]
2. 从 currentNodeId 反向 trace → mainPathIds (Set<String>)
3. 找 rootId (最顶层可达祖先)
4. 从 rootId 顺向走，分叉时优先 mainPathIds.contains(child) 的 child
   → 走出来的就是主线 pathNodeIds
5. 主线 = Set(pathNodeIds)
```

性能成本：每个 keyword 命中的 conversation 都要跑一遍。如果 keyword 命中 62 个对话 → 62 次 trace（251 节点的 trace 大约 1-2ms） → 估计 100ms 内可接受。

### 复用现有 buildTree 代码

`buildTreeInBackground` 是 private static func，可以提取一个轻量 helper：

```swift
static func computeMainPath(
    nodes: [MessageNode],
    currentNodeId: String
) -> Set<String>
```

只返回主线 nodeId 集合，不算 effectiveChildren / branchInfo 等。

---

## 五、问题归类（确认根因）

| # | 问题 | 性质 | 根因位置 |
|---|---|---|---|
| a | 搜索点击没自动 page 0→1 | UX 漏功能 | ContentView.swift:385 onChange 没覆盖同 conv |
| b | 搜索点击悄悄切 branch | 设计 bug | SidebarView.swift:1342 `scrollTargetNodeId: nodeId` |
| c | 切 branch 后无视觉反馈 | UX bug | b 的衍生 |
| d | 同一 result 触发 19 次 navigate | UX/性能 bug | 用户连点 + 没去抖 |
| e | path 切了不会 reload 回主线 | 缓存 bug | b 的衍生（state 保留） |
| f | 内容搜索默认搜分支气泡（粟粟不要） | 设计需要变更 | SearchService.fetchContentWithKeyword |

修了 b/f → c/e 自动消。a/d 是独立修。

---

## 六、修法选择（待粟粟确认）

### 方案 P（推荐）：搜索类目加分支 + 默认主线

**SearchResourceKind 扩展**：

```swift
enum SearchResourceKind {
    case conversation       // "全部"：标题/内容（内容仅主线）
    case branchContent      // 新增 "🌿 分支"：仅搜分支气泡内容
    case sticker
    case characterCard
    case worldBook
    case memory
}
```

**SearchService.fetchContentWithKeyword 改造**：
- 拿到 keyword 命中的 nodes 后
- 按 conversationId group
- 每个 conv 计算 mainPathIds（用 conversation.currentNodeId trace）
- 根据 resourceKind 过滤：
  - `.conversation`：保留 `node.id ∈ mainPathIds`
  - `.branchContent`：保留 `node.id ∉ mainPathIds`

**navigateToNodeById 改造**：
- 移除 `scrollTargetNodeId: nodeId` 参数（path 始终按 conversation.currentNodeId 走）
- 保留 `pendingScrollNodeId = nodeId`
- 加自动切 page 触发（见下）

**自动 page 0→1 触发**：
- 方案 1：在 navigateToNodeById 里发通知 `Notification.Name("scrollToConvNode")`，ContentView 订阅切 page
- 方案 2：暴露 `iOSPage` binding 给 SidebarView（破坏封装但简单）
- 方案 3：复用现有 onChange 机制 + 加一个"force page switch"信号

**.branchContent 点击行为**：
- 选项 X：传 `scrollTargetNodeId` 切到那条 branch（+ 弹 toast 提示"已切换到分支"）
- 选项 Y：跳到主线最近的"前父"，主线不动（粟粟可能想要这个）
- 选项 Z：直接切 branch，不提示

**19 次重复 navigate 修法**：
- 在 navigateToNodeById 加去抖（300ms 内同 nodeId 跳过）

### 方案 Q：单独"主线 only" 切换

把 SearchScope 拆成正交的"是否含分支"开关，UX 像 toggle："含分支搜索"。但跟现有"类型"框架冲突，类目列里看不到"分支"概念。不推荐。

---

## 七、要粟粟确认的边缘 case 决策

**Q1**：默认（"全部"类目）的内容搜索只搜主线 — 确认吗？✅（粟粟已说"是"）

**Q2**：分支结果点击的行为？
- A. 切 branch + toast "已切换到分支 N" — 操作明确
- B. 跳到主线最近前父，主线不切 — 主线神圣不可侵犯
- C. 切 branch 无 toast — 跟现状一样但有"分支"标签提示
- D. 其他

**Q3**：分支搜索结果是否在搜索结果列表里加视觉区分？
- 比如标 `🌿 分支`、缩进、灰色等
- 还是不区分（既然分类已经隔离）

**Q4**：自动 page 切换实现路径？
- A. 通知（解耦但有间接性）
- B. 暴露 iOSPage binding（直接但破坏封装）
- C. 通过 ConversationViewModel 加一个 trigger 字段

**Q5**：19 次重复 navigate 的去抖窗口？
- 300ms？500ms？还是直接 disable button + 短暂 spinner？

---

## 八、Plan 草稿（确认后转 plan doc）

```
[ ] 1. 提取 ConversationViewModel.computeMainPath(nodes:currentNodeId:) helper
[ ] 2. SearchResourceKind 加 .branchContent case
[ ] 3. SearchService.fetchContentWithKeyword 加 mainPathFilter 参数
       - 跑完 fetch 后按 conversationId group
       - 每个 conv 跑 computeMainPath
       - 过滤
[ ] 4. SidebarView typeChip 加 "🌿 分支"
[ ] 5. SidebarView.navigateToNodeById 改造：
       - 移除 scrollTargetNodeId 传参（默认场景）
       - branchContent 点击行为按 Q2 决策实现
       - 加 300ms 去抖
[ ] 6. ContentView 加 page 自动切换钩子（按 Q4 决策实现）
[ ] 7. 双端 build 验证（macOS + iOS）
[ ] 8. 移除 [PROBE B20-2] log（commit 4399691 加的）
[ ] 9. 17 Air 真机复现 → 验证 ①②③④⑤⑥ 全满足
[ ] 10. commit + push + 标 PROJECT_ROADMAP.md B20 ✅
```

---

## 九、风险与回退

- **性能**：每个搜索都要 N 次 mainPath trace。N=62 conv，每次 ~2ms → ~120ms。可接受，但加 [PROBE PERF] 实测确认。
- **数据一致性**：mainPath 算法跟 buildTreeInBackground 必须完全一致，否则会出现"对话视图能看到的气泡，搜索却搜不到"。**helper 必须从 buildTreeInBackground 抽出来共用，不能各写一套**。
- **回退**：方案 P 如果实现复杂或有 regression，可以快速回退到"完全不切 branch + 不限制 mainPath"——只修 a/b/c/d/e，不管 f。这版本下"分支气泡"也能搜到，点击不切 branch（搜到了但 scroll 滚不到，要给提示），是可接受的退化版本。

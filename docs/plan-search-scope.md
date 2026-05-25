# Plan: 搜索范围筛选（标题 / 内容 / 标题+内容）

## 所有决策（来自 research 批注）

- ① Overlap：**B**，两块都出现（重复，不直觉总比找不到好）
- ② 分隔：**Y**，一根细线 + 淡灰 count
- ③ 排序：**分别排**，标题块总在上
- ④ 时间：标题块用 `conv.createTime`，内容块用 `node.createTime`
- ⑤ 粟粟批注："范围=标题 不就等于列表过滤模式吗？" → 对。两套模式自然融合
- 默认值：**标题**（输入即实时过滤，不用多按一下）

## 新心智模型

| 范围 | 不按 ➡️ 时 | 按 ➡️ 后 |
|---|---|---|
| 标题（默认） | 列表过滤（现在的 SwiftData title 过滤） | 全量搜索 only title，结果同列表 |
| 内容 | 列表仍按 title 过滤（保持视觉稳定） | 全量搜索 only content |
| 标题+内容 | 列表按 title 过滤 | 全量搜索分两块：标题块 + 内容块 |

**refreshList / fetchPage 始终只按 title 过滤，不看 scope**。scope 只影响按 ➡️ 后的 performSearch 行为。

## Task 1 — SearchFilter 加 scope ⬜

**文件**：`SearchService.swift`

```swift
enum SearchScope: String, CaseIterable {
    case titleOnly, contentOnly, both
}

struct SearchFilter {
    var scope: SearchScope = .titleOnly  // 默认=标题
    ...
}
```

## Task 2 — performSearch 按 scope 分支 ⬜

**文件**：`SearchService.swift:89` `performSearch`

逻辑改为：

```
switch filter.scope {
case .titleOnly:
    跑 fetchFilteredConversations（title + conv.createTime 过滤）
    每个 conv 生成 SearchResult(isTitleMatch=true, matchedNodes=[])
case .contentOnly:
    跑 fetchContentWithKeyword + 内存过滤 node.createTime
    group by convId，每个生成 SearchResult(isTitleMatch=false, matchedNodes=[...])
case .both:
    两个都跑
    先生成 title 块 SearchResult（matchedNodes=[]）
    再生成 content 块 SearchResult（matchedNodes=[...]，**不去重，overlap conv 两块都出**）
}

// 两块分别按 sortOrder 排
titleBucket.sort(by: sortOrder)
contentBucket.sort(by: sortOrder)

return titleBucket + contentBucket   // 标题总在上
```

**关键点**：
- `both` 模式下，overlap conv（既 title 匹又 content 匹）在**两块都出现**（粟粟决策 B）
- 两块各自内部按 `sortOrder` 排，拼接时标题块恒在上

## Task 3 — SearchResult 增字段以便 UI 区分 ⬜

**文件**：`SearchService.swift:67` `SearchResult`

现有 `isTitleMatch: Bool` 可以直接复用：
- `isTitleMatch=true` → 标题块的 row（不展开 matchedNodes）
- `isTitleMatch=false` → 内容块的 row（展开 matchedNodes）

在 `both` 模式下，生成 title 块时 **matchedNodes 强制传 `[]`**（即使 content 也匹到，不展开）。

## Task 4 — UI 加分块渲染 ⬜

**文件**：`SidebarView.swift:233-330` 搜索结果 ScrollView

```swift
let titleMatches = searchResults.filter { $0.isTitleMatch }
let contentMatches = searchResults.filter { !$0.isTitleMatch }

ScrollView {
    LazyVStack(spacing: 2) {
        // 标题块
        if !titleMatches.isEmpty {
            // 小标签：标题 (count)
            ForEach(titleMatches) { ... 不展开 matchedNodes row ... }
        }
        // 分隔（只在两块都有时显示）
        if !titleMatches.isEmpty && !contentMatches.isEmpty {
            Divider() // 细线
                .padding(.vertical, 4)
        }
        // 内容块
        if !contentMatches.isEmpty {
            // 小标签：内容 (count)
            ForEach(contentMatches) { ... 原来的展开 matchedNodes 逻辑 ... }
        }
    }
}
```

- Count 标签字号 Theme.F.badge，灰色 Theme.textMuted，左对齐 padding
- 单一块模式（titleOnly / contentOnly）只显示一块，count 标签仍可留（一致性）

## Task 5 — AdvancedSearchPanel 加「范围」行 ⬜

**文件**：`SidebarView.swift:1730` AdvancedSearchPanel

在「时间」之前加一行：

```swift
HStack(alignment: .firstTextBaseline, spacing: 18) {
    categoryLabel("范围")
    scopeChip("标题", scope: .titleOnly)
    scopeChip("内容", scope: .contentOnly)
    scopeChip("标题+内容", scope: .both)
}
```

```swift
private func scopeChip(_ title: String, scope: SearchScope) -> some View {
    filterOption(title, isActive: filter.scope == scope) {
        withAnimation(.easeInOut(duration: 0.15)) {
            filter.scope = scope
        }
        onFilterChanged()
    }
}
```

**onFilterChanged** 已有逻辑：`isSearchActive` → triggerSearch；否则 refreshList。scope 改变自动走这条。

## Task 6 — 角色/时间在 scope=titleOnly 时灰掉策略 ⬜

调整 Task 4（上轮）的 `isContentSearchActive` 参数语义：

**旧**：是否按了 ➡️  
**新**：是否**正在搜 content**（scope != .titleOnly 且当前场景会搜 content）

列表过滤模式（!isSearchActive）：看不到 content，角色无意义。保留灰掉。  
全量搜索模式：
- scope=.titleOnly → 角色灰掉
- scope=.contentOnly / .both → 角色激活

具体 flag 定义：
```swift
let roleFilterMeaningful = isSearchActive && filter.scope != .titleOnly
```

传 `roleFilterMeaningful` 作为参数替代 `isContentSearchActive`。

（时间筛选两种模式下都有意义：标题模式用 conv.createTime，内容模式用 node.createTime，不灰）

## Task 7 — Build 验证 ⬜

```bash
cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace"
xcodebuild -scheme MemoryPalace build
```

## Task 8 — 手测清单 ⬜

1. 默认范围=标题 → 输入"你" → 实时列表过滤（= 上轮行为）✅
2. 范围=标题 + 按 ➡️ → 结果页只有标题块（和列表一样）✅
3. 范围=内容 + 按 ➡️ → 结果页只有内容块（一堆消息展开）✅
4. 范围=标题+内容 + 按 ➡️ → 两块分离，标题块在上（无 matchedNodes 展开），细线，内容块在下 ✅
5. 标题+内容下，overlap conv（如标题"我爱你" + 内容也含"你"）→ **两块各出现一次**（决策 B）✅
6. 范围=内容 时「角色」chip 从灰变亮，能点 ✅
7. 范围=标题 时「角色」chip 灰（不可点）✅
8. 时间"90 天" + 按 ➡️ + 标题+内容 → 标题块按 conv.createTime 过滤、内容块按 node.createTime 过滤 ✅
9. Z→A + 标题+内容 → 标题块内部 Z→A，内容块内部 Z→A，**标题块不会跑到内容块下面** ✅

## Task 9 — commit + push ⬜

```
feat: 搜索加「范围」筛选（标题 / 内容 / 标题+内容）+ 分块结果渲染
```

---

## 粟粟批注区

<!-- 有疑问写这里 -->

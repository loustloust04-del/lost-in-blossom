# Research: 标题搜索的筛选独立化

## 粟粟的需求

> 现在是标题就是不按➡️，内容就是按了➡️。
> 我输入"你"，出来按时间排序的列表（对的）→ 点 Z→A → 跳到了内容搜索（错的）。
> 标题搜索的时候就不要全量，而且所有已有的筛选（时间范围 / 时间排序 / A→Z Z→A）对标题搜索生效。

## 现状：两种搜索模式（但用户不知道）

| 模式 | 触发 | 代码路径 | 状态变量 |
|---|---|---|---|
| **列表过滤**（标题） | 输入框 onChange | `refreshList()` → `fetchPage()` → SwiftData `Conversation.title.localizedStandardContains` | `isSearchActive=false` |
| **全量搜索**（内容+标题） | 按 ➡️ / 回车 | `triggerSearch()` → `SearchService.performSearch` | `isSearchActive=true` |

## Bug 根因

`SidebarView.swift:1228`

```swift
private func triggerSearchIfActive() {
    guard isSearchActive || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchFilter.dateRange != .all else { return }
    triggerSearch()
}
```

**`!searchText.isEmpty` 这个条件把列表过滤模式也纳入了**，导致点任何筛选按钮（时间/角色/排序）都触发 `triggerSearch()`，从列表过滤模式偷偷升级到全量内容搜索。

`AdvancedSearchPanel.onFilterChanged` → `triggerSearchIfActive()` → 中招。

## 另一处相关逻辑：fetchPage 现状

`SidebarView.swift:1292-1395` — `fetchPage()` 负责列表过滤模式下的 SwiftData 查询。

- **排序**：`line 1356` 已经是 `searchText.isEmpty ? defaultSort : conversationSortDescriptors()` — 即有关键词时用 `searchFilter.sortOrder`，所以 Z→A 理论上对标题筛选**本来就生效**，只是被 `triggerSearchIfActive` 打断看不到。
- **时间范围**：predicate 完全没应用 `searchFilter.dateRange` — 这是目前缺的。
- **角色**：`role` 在 Conversation 层级没有意义，不适用。

三个分支（trash / selectedTag / 普通）都需要同样的 dateRange 处理。

## `conversationSortDescriptors()` 的问题

`line 1356` 的条件是 `searchText.isEmpty ? defaultSort : conversationSortDescriptors()` —
但粟粟将来可能想「没输入关键词，只靠时间范围 + A→Z 筛选列表」。这种场景下 `searchText` 空，会 fallback 到 `defaultSort` 忽略 `sortOrder`。**要不要顺手修掉**，见 plan 讨论。

## 贴纸类型

`searchShowStickers` 切换走独立路径 `searchPlacedStickers`。列表过滤模式下无意义，不动。

## 影响文件

- `MemoryPalace/Views/SidebarView.swift` 唯一文件
  - `triggerSearchIfActive()` :1228
  - `fetchPage()` :1292
  - `AdvancedSearchPanel` :1730 — 角色灰掉
  - 可能：`conversationSortDescriptors()` 的 fallback 条件

- `MemoryPalace/Services/SearchService.swift` **不需要改**（那是全量搜索路径）

## 20 万节点的性能考虑

列表过滤模式全程只查 `Conversation`（1723 条），不查 `MessageNode`，无性能风险。加 dateRange predicate 也是 `Conversation.createTime`，已有索引行为。

## 粟粟确认过的决策

- Q1 范围：**暂不做**，下一轮做
- Q2 角色：在只搜标题模式下 **灰掉不可点**
- Q3 排序：对列表过滤模式生效
- 不按➡️ = 标题筛，按➡️ = 内容搜，两种模式**不要互相串**

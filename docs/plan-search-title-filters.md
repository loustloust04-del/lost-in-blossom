# Plan: 标题搜索的筛选独立化

## 目标

列表过滤模式（不按➡️）下，时间范围 + 排序（最近/最早/A→Z/Z→A）必须全部生效，**不要跳到全量内容搜索**。

## 非目标

- 不做"范围"筛选（标题/内容切换）— 下一轮
- 不改 `SearchService.performSearch`（全量搜索路径不动）
- 不改贴纸搜索

## 改动位置（只动 SidebarView.swift）

### Task 1 — 修 `triggerSearchIfActive()` 判定条件 ⬜

**文件**：`SidebarView.swift:1228`

**现在**：
```swift
guard isSearchActive || !searchText.trimmingCharacters(...).isEmpty || searchFilter.dateRange != .all else { return }
triggerSearch()
```

**改成**：
```swift
// 只有已经进入全量搜索模式才重新跑全量；否则刷新列表过滤
if isSearchActive {
    triggerSearch()
} else {
    refreshList()
}
```

含义：在没按➡️前，点任何筛选按钮 → 只刷新 conv 列表，不升级模式。

### Task 2 — `fetchPage` 里加 dateRange 过滤 ⬜

**文件**：`SidebarView.swift:1292-1395`

三个分支都加上 `searchFilter.dateRange` 的 interval 过滤（基于 `Conversation.createTime`）：
- Trash 分支（:1296-1328）
- SelectedTag 分支（:1331-1353）
- 普通 / Favorites 分支（:1355-1379）

由于 `#Predicate` 的编译限制，最干净的做法是：**准备一个中间变量 `interval: (Date, Date)?`，每个分支根据有无 interval 构造两种 predicate**（和 `SearchService.fetchFilteredConversations` 相同套路，参考 SearchService.swift:332）。

**注意**：`Conversation.createTime` 不是 optional（Conversation model 已确认），predicate 写法可以直接 `conv.createTime >= s && conv.createTime <= e`。

### Task 3 — 排序 fallback 扩展 ⬜

**文件**：`SidebarView.swift:1356`

**现在**：
```swift
let sortBy = searchText.isEmpty ? defaultSort : conversationSortDescriptors()
```

**改成**：
```swift
// 有关键词 OR 有时间筛选 OR 显式改过排序 → 都用用户选的 sortOrder
let usingFilters = !searchText.isEmpty || searchFilter.dateRange != .all || searchFilter.sortOrder != .recent
let sortBy = usingFilters ? conversationSortDescriptors() : defaultSort
```

这样粟粟光设时间范围 + A→Z、不输关键词也能用。

### Task 4 — AdvancedSearchPanel 的「角色」在列表模式下灰掉 ⬜

**文件**：`SidebarView.swift:1730` AdvancedSearchPanel

传一个 `isContentSearchActive: Bool` 进来（= 父层的 `isSearchActive`）。`roleChip` 在 `!isContentSearchActive` 时：
- 文字 `Theme.textMuted.opacity(0.4)`
- `.disabled(true)`
- 保留点击时无反馈（不要消失，避免粟粟问"角色去哪了"）

粟粟批注：这里我挑了 **灰掉**（不是隐藏），粟粟回邮件说 **2a**，确认。

### Task 5 — Build 验证 ⬜

```bash
cd "/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace"
xcodegen generate && xcodebuild -scheme MemoryPalace build
```

### Task 6 — 手测清单 ⬜

1. 输入"你" → 默认按最近排序的标题列表 ✅（baseline）
2. 不按➡️，点 Z→A → 列表直接变 Z→A，**不跳全量搜索** ✅（核心 bug 修复）
3. 不按➡️，点"今天" → 列表只剩今天创建的 conv，按当前排序 ✅
4. 不按➡️，确认「角色」**灰掉**、点不动 ✅
5. 按➡️ → 进入内容搜索，所有筛选按现在一样生效（不要被上面改坏了）✅
6. 在全量搜索模式下点筛选 → 照旧重新跑全量搜索 ✅
7. 回收站 / 自定义 tag / 收藏 tab 下输入 + 筛选都正常 ✅

### Task 7 — commit + push ⬜

```
fix: 标题搜索点筛选不再偷偷跳全量搜索 / 时间范围对列表生效
```

---

## 粟粟批注区

<!-- 想改什么直接写下面 -->

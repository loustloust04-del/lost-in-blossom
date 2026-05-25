# Plan: 高级搜索 (Phase 1 — 结构化筛选查询)

基于 `docs/research-advanced-search.md`，方案 A。

---

## 架构决策

### 搜索逻辑抽出独立 Service
当前 `performSearch()` 在 `SidebarView.swift:706-793`，200 行搜索逻辑混在 1200 行 View 里。
→ 新建 `SearchService.swift`，View 只负责展示。

### 后台线程搜索
当前搜索在主线程 fullscan 20 万条。
→ `SearchService` 在 `DispatchQueue.global(qos: .userInitiated)` 跑，主线程回调更新 UI。
→ 搜索期间显示 loading indicator。

### Predicate 组合策略
SwiftData `#Predicate` 是编译时宏，不能运行时动态拼。
→ 用**分步过滤**：先用时间范围 + 角色的 predicate 缩小范围（SQLite 索引级），再在内存里 `localizedStandardContains` 匹配关键词。
→ 这样 fullscan 只发生在已缩小的子集上，不是 20 万条。

### UI 策略
搜索栏右侧加漏斗图标 `line.3.horizontal.decrease`，点击展开/收起筛选面板。
筛选面板内嵌在搜索栏下方（不用 popover，保持上下文）。

---

## 文件改动一览

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| 新建 `Services/SearchService.swift` | 新文件 | 搜索引擎：查询构建、后台执行、结果组装 |
| `Models/Conversation.swift` | 改 | MessageNode 加索引 |
| `Views/SidebarView.swift` | 改 | 搜索 UI 重构：筛选面板 + 调用 SearchService |
| `project.yml` | 检查 | 确认新文件被 xcodegen 收入 |

---

## 原子任务清单

### Step 1: 新建 SearchService — 数据层

- [ ] **1.1** 新建 `MemoryPalace/Services/SearchService.swift`
- [ ] **1.2** 定义 `SearchFilter` 结构体：
  ```swift
  struct SearchFilter {
      var keyword: String = ""
      var dateRange: DateRange = .all
      var roles: Set<String> = ["user", "assistant"]  // 默认搜这两个
      var sortOrder: SearchSort = .recent
  }
  
  enum DateRange: Equatable {
      case all
      case today
      case last7Days
      case last30Days
      case last90Days
      case custom(start: Date, end: Date)
      
      /// 返回 (startDate, endDate)，.all 返回 nil
      var dateInterval: (start: Date, end: Date)? { ... }
  }
  ```
- [ ] **1.3** 定义 `SearchResult` 结构体（从 SidebarView 的 `SearchResultGroup` 演进）：
  ```swift
  struct SearchResult: Identifiable {
      let id: String           // convId
      let convTitle: String
      let convTime: Date
      let matchedNodes: [MatchedNode]
      let isTitleMatch: Bool
      var isExpanded: Bool
  }
  
  struct MatchedNode: Identifiable {
      let id: String           // node.id
      let nodeId: String
      let role: String
      let preview: String      // 带关键词上下文的预览
      let createTime: Date?
      let conversationId: String
  }
  ```
- [ ] **1.4** 实现 `SearchService.performSearch(filter:container:) async -> [SearchResult]`：
  - 在后台线程新建 `ModelContext(container)`
  - **第一步**：按 `filter.dateRange` + `filter.roles` 构建 predicate，fetch MessageNode（这步利用索引，快）
  - **第二步**：如果 `keyword` 非空，在内存中 `localizedStandardContains` 过滤
  - **第三步**：搜标题（Conversation.title），同样带时间范围 predicate
  - **第四步**：按 conversationId 分组，组装 `SearchResult`
  - **第五步**：排序（recent/oldest/titleAZ/titleZA）
  - 返回结果
- [ ] **1.5** 实现 `buildPreview(_:keyword:) -> String`（从 SidebarView:817-834 搬过来）
- [ ] **1.6** Predicate 工厂方法 — 为不同筛选组合生成对应 predicate：
  ```swift
  /// 时间 + 角色，不含关键词（关键词在内存过滤）
  private static func buildNodePredicate(
      roles: Set<String>, 
      startDate: Date?, 
      endDate: Date?
  ) -> Predicate<MessageNode>
  ```
  注意：`#Predicate` 不支持 `Set.contains()`，需要展开为 `||` 条件。
  由于角色组合有限（user/assistant/system/tool 的子集），写 3-4 个预定义 predicate 覆盖常见情况：
  - user + assistant（默认）
  - 仅 user
  - 仅 assistant
  - user + assistant + system（高级模式）

### Step 2: MessageNode 加索引

- [ ] **2.1** 在 `Conversation.swift` 的 MessageNode 模型上加索引：
  ```swift
  @Attribute(.index) var createTime: Date?
  @Attribute(.index) var conversationId: String
  ```
  ⚠️ 注意：这是 SwiftData schema 变更，需验证是否自动轻量迁移。先在 dev 环境测试。如果 `@Attribute(.index)` 不触发破坏性迁移（只是加索引），应该安全。
- [ ] **2.2** build 验证，确认迁移无报错

### Step 3: SidebarView 搜索 UI 重构

- [ ] **3.1** 删除 SidebarView 中的旧搜索类型（`SearchResultGroup` struct，行 10-28）
- [ ] **3.2** 删除旧搜索方法 `performSearch()`（行 706-793）和 `buildPreview()`（行 817-834）
- [ ] **3.3** 替换 `@State private var searchResults: [SearchResultGroup]` → `@State private var searchResults: [SearchResult]`
- [ ] **3.4** 加新 state：
  ```swift
  @State private var showAdvancedFilter = false
  @State private var searchFilter = SearchFilter()
  @State private var isSearching = false  // loading 状态
  ```
- [ ] **3.5** 搜索栏改造（行 63-114 区域）：
  - 搜索框右侧加漏斗图标按钮 `line.3.horizontal.decrease`
  - 点击 toggle `showAdvancedFilter`
  - 漏斗图标在有非默认筛选时变色（`Theme.branchIndicator`）表示有筛选激活
- [ ] **3.6** 新建筛选面板 View（内嵌在搜索栏和 filter chips 之间）：
  ```
  if showAdvancedFilter {
      AdvancedSearchPanel(filter: $searchFilter)
  }
  ```
  面板内容：
  - **时间范围**：横排 chip 选择器（全部 / 今天 / 7天 / 30天 / 90天 / 自定义）
    - 选"自定义"时展开两个 `DatePicker`（起始/结束）
  - **角色**：横排 toggle chip（你 / 小雾），默认两个都选
  - 整体用 `VStack` + `.transition(.opacity.combined(with: .move(edge: .top)))` 动画展开
- [ ] **3.7** `AdvancedSearchPanel` 独立成 struct View，定义在 SidebarView.swift 底部（和 FilterChip、ContentMatchRow 同级），参数：
  ```swift
  struct AdvancedSearchPanel: View {
      @Binding var filter: SearchFilter
      let userName: String
      let assistantName: String
  }
  ```
- [ ] **3.8** 触发搜索的逻辑改造：
  - `searchText` 变化 + `onSubmit` → 更新 `searchFilter.keyword` → 调用搜索
  - 筛选条件变化 → 如果已有关键词，自动重新搜索
  - 搜索调用改为：
    ```swift
    private func triggerSearch() {
        searchFilter.keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchFilter.keyword.isEmpty || searchFilter.dateRange != .all else {
            clearSearch()
            return
        }
        isSearching = true
        isSearchActive = true
        let filter = searchFilter
        let container = modelContext.container
        Task.detached {
            let results = await SearchService.performSearch(filter: filter, container: container)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
    ```
- [ ] **3.9** 搜索结果列表适配新 `SearchResult` / `MatchedNode` 类型（行 194-288 区域）：
  - `ForEach($searchResults)` 内部的 `group.matchedNodes` 改用 `MatchedNode`
  - `ContentMatchRow` 改为接收 `MatchedNode` 而不是 `MessageNode`（因为后台线程不能传 SwiftData 对象跨线程）
  - `navigateToNode` 改为接收 `nodeId: String` + `conversationId: String`，内部 fetch node

### Step 4: ContentMatchRow 适配

- [ ] **4.1** `ContentMatchRow`（行 1176-1215）改为接收值类型：
  ```swift
  struct ContentMatchRow: View {
      let nodeId: String
      let role: String
      let convTitle: String
      let preview: String
      let createTime: Date?    // 新增：显示时间
      let userName: String
      let assistantName: String
  }
  ```
- [ ] **4.2** 在每条结果行里加时间显示：
  ```swift
  if let time = createTime {
      Text(time, style: .date)
          .font(.caption2)
          .foregroundColor(Theme.textMuted.opacity(0.5))
  }
  ```
- [ ] **4.3** `navigateToNode` 调用处改为传 `nodeId` + `conversationId`（搜索结果里已有）

### Step 5: Loading 状态 UI

- [ ] **5.1** 搜索进行中（`isSearching == true`）时，搜索结果区域显示 `ProgressView`：
  ```swift
  if isSearching {
      VStack {
          ProgressView()
              .scaleEffect(0.7)
          Text("搜索中...")
              .font(.caption)
              .foregroundColor(Theme.textMuted)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 40)
  }
  ```
- [ ] **5.2** 搜索完成但无结果时，沿用现有"没有找到结果"空状态

### Step 6: 允许纯筛选搜索（无关键词）

- [ ] **6.1** 支持不输关键词、只选时间范围的搜索（比如"今天的所有对话"）：
  - `triggerSearch()` 条件改为：keyword 非空 OR dateRange 非 all
  - 无关键词时跳过内容匹配，只返回时间范围内的对话列表
  - 结果每个对话只显示标题 + 时间，不展开消息

### Step 7: Build + 测试

- [ ] **7.1** `xcodegen generate && xcodebuild -scheme MemoryPalace build` 编译通过
- [ ] **7.2** 手动验证：
  - 关键词搜索（旧功能不退步）
  - 关键词 + 时间范围
  - 关键词 + 角色筛选
  - 纯时间范围（无关键词）
  - 漏斗按钮展开/收起
  - 搜索中 loading indicator
  - 点击结果跳转到对话+消息
- [ ] **7.3** git commit + push

---

## UI 详细布局

```
┌──────────────────────────────────────────────┐
│ 🔍 搜索对话...              [▼] [✏️] [➕]    │  ← 搜索栏（现有）
│                              ↑漏斗                │
├──────────────────────────────────────────────┤
│ ⏱ 全部  今天  7天  30天  90天  自定义...     │  ← 时间 chips
│ 👤 [你 ✓] [小雾 ✓]                          │  ← 角色 toggles
├──────────────────────────────────────────────┤  ← 筛选面板（折叠状态下隐藏）
│ 全部 | ⭐收藏 | 🗑回收站       📁+            │  ← 现有 filter chips（不动）
├──────────────────────────────────────────────┤
│ 3 个对话，12 条结果                           │
│ ▾ 对话标题 A                          (5)    │
│    🔍 ...匹配内容预览...      你  3/15       │
│    🔍 ...匹配内容预览...      小雾  3/14     │
│ ▸ 对话标题 B                          (3)    │
│ ▸ 对话标题 C (标题匹配)               (4)    │
└──────────────────────────────────────────────┘
```

### 时间 Chip 样式
- 和现有 `FilterChip` 同风格（圆角胶囊，选中时 `Theme.accent` 背景）
- "自定义" chip 选中后下方展开两个 `DatePicker`（compact 样式）

### 角色 Chip 样式
- 小圆角矩形，选中时 `Theme.branchIndicator.opacity(0.3)` 背景 + `Theme.branchIndicator` 文字
- 未选中时 `Theme.mainBg` 背景 + `Theme.textMuted` 文字
- 支持多选（可以同时选"你"和"小雾"）

### 漏斗按钮状态
- 默认（无筛选）：`Theme.textMuted`
- 有筛选激活：`Theme.branchIndicator`（薄荷绿，和其他功能按钮一致）

---

## 线程模型

```
[主线程] triggerSearch()
    ↓ 设 isSearching = true
    ↓ Task.detached
[后台线程] SearchService.performSearch()
    ↓ 新建 ModelContext(container)
    ↓ fetch (predicate: 时间+角色) → [MessageNode]
    ↓ 内存过滤 keyword
    ↓ 组装 [SearchResult]（纯值类型，可跨线程）
    ↓ await MainActor.run
[主线程] searchResults = results, isSearching = false
```

**关键**: `MatchedNode` 是纯值类型（不持有 SwiftData managed object），可以安全跨线程。
后台 `ModelContext` 的 managed objects 在 `performSearch` 结束后释放。

---

## 边界情况

1. **空关键词 + 时间范围**：返回该时间段所有对话（只标题，不展开消息）
2. **空关键词 + 默认筛选**：不搜索（和现在一样，清除搜索状态）
3. **搜索中用户改了筛选**：取消上一次搜索（用 Task + cancel），重新触发
4. **结果为零**：显示"没有找到结果"
5. **极短关键词（1 字符）**：允许，交给 `localizedStandardContains` 处理
6. **清空搜索框**：清除搜索状态，回到对话列表，但保留筛选面板状态
7. **切换楼层**：搜索状态清除（`searchFilter` reset），因为数据库换了

---

## 不做的事（本次范围外）

- ❌ SQLite FTS5 全文索引（Phase 2）
- ❌ 语义搜索 / NLContextualEmbedding（Phase 3）
- ❌ LLM query 理解（Phase 3）
- ❌ 搜索历史 / 保存查询
- ❌ 搜索 Memory（记忆库）内容
- ❌ 跨楼层搜索
- ❌ 正则 / 布尔表达式
- ❌ 搜索结果内关键词高亮（可后续加，本次只做预览文字）

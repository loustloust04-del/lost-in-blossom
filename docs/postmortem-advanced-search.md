# 复盘：高级搜索功能开发

**时间**: 2026-04-01 ~ 2026-04-03
**commits**: `3b8e4da` → `37c36cf` → `d20af5a` → `ae7eba1` → `e0f2936`

---

## 做了什么

在现有关键词搜索基础上，增加高级搜索：
- **SearchService** — 搜索逻辑从 SidebarView 抽出，独立 Service，后台线程执行
- **时间范围筛选** — 今天 / 7天 / 30天 / 90天 / 自定义日期
- **角色筛选** — 你 / 小雾，可多选
- **筛选面板 UI** — 漏斗按钮展开，有筛选激活时变色
- **搜索结果增强** — 每条结果显示日期，点击定位到具体气泡

## 犯的错

### Bug 1: 搜索卡死（`37c36cf` 修）

**错误**: 把 `localizedStandardContains(keyword)` 从 `#Predicate` 里拿出来，改成先 fetch 再内存过滤。

**后果**: 无时间范围时 fetch 全部 20 万条 MessageNode 到内存，逐条匹配 → app 卡死。

**教训**: **20 万条数据的过滤必须在 SQLite 侧完成**。`#Predicate` 里的 `localizedStandardContains` 虽然也是 fullscan，但是 SQLite 的行级扫描，不需要把对象全部实例化到内存。内存过滤只适用于已被 predicate 大幅缩小的子集。

**规则**: 除非 predicate 已经把范围缩到几百条以内（比如有时间范围），否则关键词匹配必须留在 predicate 里。

### Bug 2: 点击搜索结果不定位到气泡（`d20af5a` ~ `e0f2936` 修，经历 3 次尝试）

**尝试 1** (`d20af5a`): 加 `pendingScrollNodeId`，在 `applyTreeData` 完成后设 `scrollToNodeId`。
→ 失败。原因没想清楚就动手了。

**尝试 2** (`ae7eba1`): 加 `scrollTargetNodeId` 参数让 path 经过目标 node + 两步 scroll。
→ 失败。path 问题是真实的（目标可能在分支上），但不是主要原因。

**尝试 3** (`e0f2936`): 找到根因 — `isLoading=false` 和 `scrollToNodeId=id` 在同一同步块，SwiftUI 合成一次渲染，ScrollView 创建时 onChange 收到的是初始值不是变化，不触发。`DispatchQueue.main.async` 推到下一 turn。
→ 成功。

**教训**: SwiftUI 的 `onChange(of:)` **不响应初始值**，只响应变化。如果一个 view 的创建（`if` 分支切换）和被观察值的赋值发生在同一渲染周期，onChange 不会 fire。必须把赋值推到下一个 runloop turn。

**规则**: 当 view 的存在与否（`if/else`）和 `onChange` 监听的值在同一代码块里变化时，用 `DispatchQueue.main.async` 延迟赋值。

## 做对的事

- **Research → Plan → Implement** 三步流程，文档先行
- SearchService 独立出来，View 不再混业务逻辑
- 后台线程搜索，主线程不卡
- `MatchedNode` 用纯值类型，安全跨线程
- 筛选面板 UI 简洁，漏斗图标有激活状态指示

## 下一步

- [ ] 搜索结果关键词高亮（气泡内 highlight）
- [ ] Phase 2: SQLite FTS5（如果关键词搜索性能不够）
- [ ] Phase 3: 语义搜索（NLContextualEmbedding / LLM query 理解）
- [ ] `@Attribute(.index)` 等升 target 到 macOS 15 再加

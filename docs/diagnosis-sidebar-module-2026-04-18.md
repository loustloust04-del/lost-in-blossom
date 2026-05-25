# 诊断：iOS 左栏模块收尾后的边界 / 交互 / 债务盘点

**时间**: 2026-04-18，左栏视觉收尾（commit `4f1751d` → `c50e190`）之后、进入下一个模块之前的自检。

---

## 1. 边界情况（没处理 / 没验证）

### tab 栏与手势
- **`hasCustomTags` 0↔1 切换瞬间**：`sidebarTabBarBody` 的两条分支（fillWidth / ScrollView）会整个重建 → `TabBarGestureContainer` 的 `UIHostingController` 也重建 → `blockerPan` 要重新 `attachDependency`。期间翻页手势可能短暂失守。没实机测过。
- **正在选中的自定义 tag 被删除**：`currentTab` 和 `snappedTabId` 的同步路径没穷举。`scrollPosition` 可能 stuck 在已不存在的 id 上。
- **`attachDependency` 依赖 `view.window` 非 nil**：SidebarView 被嵌到非主 window 的场景（sheet / modal / Preview）下，blocker 会静默失效。没有 fallback。
- **Dynamic Type / VoiceOver**：tab 字号用 `Theme.F.secondary` 固定值，大字号模式下 tab 栏高度可能爆。

### 搜索
- **竞态**：切 tab 触发新一轮 `triggerSearch`，但旧的 `performSearch` 可能还在跑 → SearchService **没有 cancel token**。快速切 tab 会看到旧结果闪烁或错位。
- **自定义日期**：`customStart > customEnd` 没校验，走到 predicate 就是空集，UI 无提示。
- **tag 对话被移到回收站**：tag 的 `conversationIdScope` 里还留着它的 id，但 `includeDeleted=false` → 搜不到。用户感觉「我标过这个，怎么找不到了」。
- **空 scope 短路**：SearchService 短路返回空集，但 UI 显示「无结果」卡片还是卡在旧结果上，未验证。

### 筛选器
- **跨 tab 保留**：role / sort / type 的选择切 tab 后继续保留。是 feature 还是 bug 没定义。
- **`showStickers` 初始态**：三态（false / true），UI 只两按钮，初次打开高级筛选面板的默认视觉态不明确。

---

## 2. 和下一个模块（贴纸）交互可能出的问题

### 手势冲突会复现
- 当前 `iOSTabBarGestureBlocker` 只包 **tab 栏**区域。贴纸如果是无限画布 + 拖拽缩放，画布内的 pan / pinch 会跟 `TabView(.page)` 翻页再次打架。
- 要么把整个 `iOSListPage` 内容区也套 blocker，要么换成按页面整体 toggle `collectionView.panGestureRecognizer.isEnabled`。

### 搜索假设要打破
- `StickerSearchResult` 已经在 SearchService 里，但筛选器的「角色」对贴纸没语义。
- `conversationIdScope` 是按 conversation id 限定的 —— 贴纸可能不从属 conversation（独立 gallery），scope 对贴纸搜索就不适用。
  - 方案：再加 `stickerIdScope`，或把 scope 升级成枚举 `SearchScope`（.conversations(Set<String>) / .stickers(Set<String>) / .all）。

### card 样式假设要打破
- `sidebarCardShape(for:)`（见本次债务修法）用 `tab == .all` 判断 topLeading 是否清零。
- 如果贴纸作为一个 tab 插入 `allTabs` 列表中间，这条件就不对了。
- 正确抽象应该是「tab 在 tabs 数组里的 **位置**（第一个 / 最后一个 / 中间）」而不是硬编码特定 case。本次先不做，等贴纸模块真动到 tab 结构再一起改。

### TabView page 扩展
- 贴纸 gallery 作为独立 page 还是进 iOSListPage 的列表？如果是独立 page，`ContentView.updateKeyboardBehavior(for:)` 的 switch 要扩。

---

## 3. 技术债盘点

### 已经在本次修复（见 commit `<TBD>`）
- [x] **`UnevenRoundedRectangle` clipShape 5 处复制粘贴** → 抽成 `View.sidebarCardShape(for:)` modifier
- [x] **`docs/plan-tab-gesture-conflict.md` 计划与实现不一致** → 文件顶部加 `superseded` 标记，指向 postmortem

### 暂缓（不阻塞下一模块）
- **SourceKit 诊断噪音**（Cannot find type 假错误）：xcodegen 生成的项目和 SourceKit 索引不同步。不影响 build 但污染 edit signal。根因未查。
- **`conversationIdScope` 大 scope 下 predicate `IN` 性能**：未压测。粟粟的 Conversation 数量级较小（几百～几千），scope 实际传入通常是几百条以内的 Set，暂时不是瓶颈。
- **AdvancedSearchPanel magic numbers**（spacing 18 / padding 25 / vstack 13 / bottom 18）：散在代码里。下一模块用不到筛选器就不动。
- **search state 状态机**：`isSearchActive` / `isSearching` / `searchFilter` / `searchShowStickers` / `currentTab` 五个状态没穷举路径。Bug 面比较深，留到实际踩到再整。

---

## 行动建议（给粟粟）

1. **本次先还两条硬债**（clipShape ViewModifier + plan 文档 supersede 标记），进贴纸模块时不会因为 5 处散装样式浪费时间。
2. **进贴纸模块前先决策两件事**：
   - 贴纸 gallery 作为独立 TabView page，还是进 iOSListPage 列表？
   - 搜索筛选器对贴纸的语义：贴纸用独立筛选器，还是复用并禁用无关选项（角色）？
3. **上线前补一次真机边界测试**：动态加删 tag（尤其选中状态下删）、快速切 tab 触发搜索、Dynamic Type 大字号、横屏。这些边界现在都是理论风险。

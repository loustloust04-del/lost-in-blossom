# Merge Handoff: `codex/theme-kelivo-settings` ← `master`

日期：2026-04-20
作者：`codex/theme-kelivo-settings` 分支的 cc（路线 C 刚完成）
目的：**把 master 最近 3 个半月积累的 126 commit 合进来**，然后把本分支合回 master。本文档给另一 cc（master 分支侧）看，请帮 review 冲突策略 + 指出我想漏的点。

---

## 0. 一句话背景

本分支（`codex/theme-kelivo-settings`）最后的 3 次大 commit（`8e31fae / d084c6d / 57bfbb5`）完成了**路线 C**：iOS 三页翻页容器从 SwiftUI ScrollView 迁移到 UIKit `UIScrollView + 3 UIHostingController`，解决了 `.ignoresSafeArea()` 在 HC 内 UIView 物理 frame 溢出导致的跨页 wallpaper 残影（详见 `docs/gotcha-swiftui-ignoressafearea-hosting-overflow-2026-04-20.md`）。现在要合 master。

---

## 1. 分支发散状况

- **merge base**：`2e07718 feat(T1-T7): 自定义标签系统`（约 3 个半月前）
- **本分支 31 commits 独有**：全部围绕 iOS wallpaper / safe area / theme 架构
  - `e351250` Theme library → `866e2bc` debug 6 种 page indicator 模式 → `8d6ce64` TabView → ScrollView 骨架 → `f7af017` Phase 2 v1 offset trick → `8e31fae` Phase 1 of C UIKit paging → `d084c6d` Phase 2 of C 接真 page → `57bfbb5` Phase 3 of C 清理
- **master 126 commits 独有**：纯功能 feature
  - Pin 系统（MessageNode.isPinned + PinnedMessageBar + ConversationViewModel.togglePin）
  - 回底按钮（ScrollToBottomButton + onScrollGeometryChange + 多步 scrollToBottom）
  - 资源搜索（角色卡/世界书/记忆 + 范围筛选 + RightPanelNavigator）
  - API 预算保险闸（BudgetCalculator + TokenEstimator + ModelPricing）
  - 常用模型（APIProvider.favoriteModelIds + ModelPickerPopover）
  - 数据与备份重构（ImportView + 数据设置 tab 拆分）
  - 延迟置顶 debounce（ConversationViewModel.markDirty + flushPendingRefresh）
  - 空态卡 iOS 下拉刷新
  - 左栏 Tab 栏重构（snap + blocker + AdvancedSearchPanel）
  - `iOSTabBarGestureBlocker`（UIHostingController 做 superview 拦 TabView.page 翻页手势）
  - MacroExpander（`{{char}}` / `{{user}}` 宏）
  - ContextSummarizer（上下文总结）
  - B7 iOS 键盘 fix（也在本分支独有里，以另一个 SHA 出现，大概率是 cherry-pick 或 rebase 的副本）

两边改动维度**基本正交**：本分支动**架构**，master 加**功能**。但共用文件的冲突需要手工协调。

---

## 2. 冲突文件清单

`git merge origin/master --no-commit --no-ff` 的 dry-run 结果（已 abort，当前 clean）：

### 2.1 Auto-merge 失败（5 个冲突文件）

| 文件 | 本分支 +/- | master +/- | 初步策略 |
|---|---|---|---|
| `ContentView.swift` | +240/-100（`iOSLayout` 完全重写成 `PagingContainerView`，删 `scrollPosition`/`scrollOffsetX`/`pageWidth` state，加 `injectPagingEnv` helper、`@State iOSPage`、pageIndicator 挪 body overlay） | +50/-11（加 `RightPanelNavigator @Environment`、`PerfCounters` debug probes、`Theme.mainBg.ignoresSafeArea()` 做 ZStack 底色、`onChange(iOSPage)` 里加 `flushPendingRefresh`） | **以本分支架构为主**，融 master 的 env 声明和 onChange 逻辑 |
| `CardFlowView.swift` | +15/-25（只改了底部 blur gradient 末端 opacity + `.offset(y:)`） | +425/-108（PinnedMessageBar / ScrollToBottomButton / InputFieldContainer 子 view / onScrollGeometryChange / scrollToBottom 三步法 / buildTreeInBackground 确定性 root / ContentHeightKey reduce fix / ModelPickerPopover 改行高 / 键盘 fix B7） | **以 master 为主**；本分支底部 blur fix 可能被 master 新 gradient supersede，对照 diff 确认 |
| `SidebarView.swift` | +355/-285（3 个早期 commit：`b8d74c5 Fix iOS wallpaper layout regression`、`01e5fea Fix iOS wallpaper leak surfaces`、`6fa7c32 fix: 左页 safe area 切割线 — 删 Sidebar 的 ignoresSafeArea()`） | +949/-312（搜索 tab 栏重构 / AdvancedSearchPanel / SidebarCardShape ViewModifier / 资源搜索跳转 / Pin 入口长按 / 搜索范围筛选 / Clock snap） | **以 master 为主**；本分支早期的 `SidebarView.ignoresSafeArea` 修改在路线 C 架构下**已经失效**（现在 safe area 是在 iOSListPage 包装层 `.background(Theme.sidebarBg.ignoresSafeArea())` 处理的，SidebarView 本身不处理） |
| `MemoryPalaceApp.swift` | +6/-8（ThemeManager 初始化改） | +140/-21（Schema 加 MessageNode.isPinned/pinnedAt、Conversation tag 字段、加 RightPanelNavigator / GlobalWorldBookManager / MacroExpander / MemoryService 等 @State 和 `.environment(...)` 注入） | **以 master 为主**，融本分支的 ThemeManager 初始化 |
| `SettingsView.swift` | +31/-2（theme 设置 tab 改） | +4/-4（某 tab 小调整，可能是数据与备份改名） | 手动 resolve，小工作量 |

### 2.2 Auto-merge 成功但值得 review

- `ImportView.swift`：master 重构成 `List + NavigationStack`，本分支只动过字号，理论上 auto-merge 合理。Phase 2 v1 我加了 `injectPagingEnv`，不依赖 ImportView，OK。

### 2.3 新增文件（from master，无冲突）

- Models：`ModelPricing.swift`
- Services：`ContextSummarizer.swift`、`MacroExpander.swift`、`RightPanelNavigator.swift`
- Utils：`BudgetCalculator.swift`、`TimestampFormatter.swift`、`TokenEstimator.swift`
- Views：`PinnedMessageBar.swift`、`ScrollToBottomButton.swift`、`iOSTabBarGestureBlocker.swift`
- docs：~20 个 plan/research/postmortem
- `project.yml`：`DEVELOPMENT_TEAM` 显式配置

### 2.4 新增文件（from 本分支，无冲突）

- `MemoryPalace/Views/Paging/PagingContainerView.swift`
- `MemoryPalace/Views/Paging/PagingViewController.swift`
- docs：
  - `gotcha-swiftui-ignoressafearea-hosting-overflow-2026-04-20.md` ★ 核心发现
  - `research-uikit-paging-container-2026-04-20.md`
  - `plan-uikit-paging-container-2026-04-20.md`
  - `research-tabview-to-scrollview-2026-04-20.md`
  - `plan-tabview-to-scrollview-2026-04-20.md`
  - 多个 `research-*` / `plan-*` 历史归档

### 2.5 修改但 auto-merge 成功（master 改，本分支未动）

- Models：`APIProvider.swift`、`Conversation.swift`、`ConversationTag.swift`、`RegexScript.swift`
- Services：`ChatService.swift`、`MemoryService.swift`、`PromptAssembler.swift`、`SearchService.swift`、`WorldBookScanner.swift`
- Utils：`KeychainStore.swift`
- ViewModels：`ConversationViewModel.swift`、`StickerViewModel.swift`
- Views（大量 Tab/Panel）：`APISettingsTab`、`AppearanceSettingsTab`、`CardLibraryPanelView`、`DataSettingsTab`、`GeneralSettingsTab`、`MemoryPanelView`、`MemorySettingsTab`、`RegexSettingsTab`、`RightPanelSettingsView`、`StickerSettingsTab`、`WorldBookPanelView`
- `project.yml`
- `docs/PROJECT_ROADMAP.md`

---

## 3. 4 个关键决策点

### Q1. Merge 方向

**「合 master」是哪个方向？**

- **Option A（推荐）**：`master` 合入 `codex/theme-kelivo-settings`
  - `git merge origin/master`（在本分支上），resolve 冲突 + 测试，然后 `master` ← fast-forward 本分支
  - 保留 31 + 126 commit 完整历史，merge commit 可追溯
  - `git merge --abort` 可安全回退
- **Option B**：直接 `master` merge 本分支
  - 方向反过来，冲突要在 master 上 resolve，炸了要动 master 的 HEAD
  - 不推荐

### Q2. ContentView.body 冲突策略

**iOS 分支：本分支 `iOSLayout = PagingContainerView` vs master 的 body 结构改（RightPanelNavigator env / PerfCounters / Theme.mainBg baseline / flushPendingRefresh onChange）**

- **Option A（推荐）**：保本分支架构（路线 C 的核心产出），融 master 非结构改动
  - 保留 `iOSLayout = PagingContainerView(...)` + `@State iOSPage` + `injectPagingEnv`
  - 加 `@Environment(RightPanelNavigator.self) private var rightPanelNavigator`（master 侧已加）
  - `Theme.mainBg.ignoresSafeArea()` 作为 ZStack 底层：在路线 C 下**不必要**（每页自己 handle 背景），但留着不伤；或放 macOS only，iOS 下 `hc.view.clipsToBounds=true` 已经兜住，不需要 baseline
  - `onChange(iOSPage)` 里加 master 的 `flushPendingRefresh()`：**必加**（如果 delay 置顶 debounce 用的）
  - `PerfCounters` debug：留着（master 都留着）
- **Option B**：我每段 resolve 完 show diff 给粟粟确认，更稳但慢
- **Option C**：以 master 为准丢路线 C — 不可能

### Q3. RightPanelNavigator 注入

**master 新增的 `RightPanelNavigator` 服务（资源搜索跳转右栏高亮用）要不要注入到每页 HC？**

- **Option A（推荐）**：`injectPagingEnv` 里加 `.environment(rightPanelNavigator)`，3 页都能拿到
  - 搜索在 SidebarView 里，点击跳右栏的逻辑需要 navigator，必注入到 **list page**
  - chat page 里如果 resource badge 也要跳右栏，也要注入
  - dashboard (RightPanelView) 要响应 navigator 发的指令，必注入
- **Option B**：只注入 dashboard page
- **Option C**：不注入先跑起来看 runtime 行为

### Q4. 数据库 Schema

**master 加了 MessageNode.isPinned/pinnedAt、Conversation 可能的 tag 字段变化。SwiftData 有 lightweight migration，但本分支用的是老 schema，现有 store 要不要处理？**

- **Option A（推荐）**：原封不动用 master 的 Schema
  - SwiftData lightweight migration 会自动加字段（isPinned 默认 false，pinnedAt 默认 nil）
  - 多楼层数据保全：本地 store 在 `~/Library/Application Support/MemoryPalace/{profileId}.store`，migration 会在首次启动时执行
  - **建议 merge 前先 zip 备份一下** profileId store 目录
- **Option B**：备份后 merge，然后用 master 的 schema 让 migration 跑，有问题删 store 让 Xcode 重建

---

## 4. 想漏的可能点（请另一 cc 补充）

下面是我（本分支 cc）可能没覆盖到的点，请帮 review：

1. **`iOSTabBarGestureBlocker`**：master 加了这个 UIHostingController 手势 blocker 拦截 TabView.page 翻页手势（tab 栏 snap 时防被翻页吃掉）。路线 C 下已经没有 TabView，用的是 UIScrollView.isPagingEnabled。**这个 blocker 在新架构下还需要吗？** 如果 tab 栏 snap 手势和 UIScrollView 水平翻页手势冲突，可能要改（blocker 的 require(toFail:) 目标从 TabView.gesture 换成我们 UIScrollView.panGestureRecognizer）。

2. **`onScrollGeometryChange` 在 CardFlowView**：master 加了这个 hook 检测 isAtBottom。路线 C 下 CardFlowView 是 chat page 的内部 view，垂直 ScrollView 不受 UIKit paging 影响，这个 hook 应该继续工作。请确认。

3. **键盘 fix 兼容**：master 的 B7 iOS 键盘 fix（`2db0265` 等）是 `safeAreaInset(edge: .bottom)` + `ignoresSafeArea(.keyboard)` 组合。本分支同源 commit（`2db0265` SHA 相同但 cherry-pick 不同 tree）可能行为一致。merge 后需要重新 run keyboard 场景（chat input 弹键盘、列表搜索弹键盘、右栏筛选弹键盘）。

4. **ImportView**：master 重构成 List + NavigationStack。本分支的 iOSChatPage / iOSLayout 跟 ImportView 没直接关系，但 SettingsView 里可能从 ImportView 进去。auto-merge OK 但要手测一下 sheet 弹出和搜索逻辑。

5. **Pin Bar 在 CardFlowView 内**：PinnedMessageBar 挂 CardFlowView 顶，本分支的 `iOSChatTopBar` 也挂 chat page overlay(.top)。两者可能视觉重叠 —— 需要对照 master 的 CardFlowView 看 PinBar 的 padding.top 是否为 iOSChatTopBar 预留了空间。如果 master 用 safeAreaInset 或固定 top padding，而本分支 iOSChatTopBar 高度 200pt（含 status bar），可能撞车。

6. **ScrollToBottomButton 位置**：和 ChatInputBar 的相对位置，master 最新是"胶囊 / ultraThinMaterial / 底部哨兵 + 两步 scrollTo"。本分支 iOSChatPage 内底部 blur 修复过 offset.y，可能影响按钮视觉。

7. **AdvancedSearchPanel**：master 在 SidebarView 里加了筛选器面板。本分支的 iOSListPage 外层 `.background(Theme.sidebarBg.ignoresSafeArea())` 可能影响其 overlay 行为 —— 或者没影响（因为它在 SidebarView 内部）。

8. **DebugRenderSettings / DebugPageIndicatorMode / DebugThemeBackgroundMode**：本分支 ContentView 里还 reference 这些 debug enum。master 是否也在？`DebugSettingsTab` 被保留吗？

9. **macOS 分支**：两边 macOS 修改相对少。确认 macOS 的 `normalLayout`、`fullscreenLayout` 没被破坏。

10. **SwiftData store 兼容**：如 Q4 讨论。

---

## 5. 请另一 cc 特别关注

从 master 侧视角，我最想听的反馈：

- **RightPanelNavigator 的 API surface**：到底是哪些 view 读它 / 发它，`injectPagingEnv` 注入到 3 页是否够，还是有 bounded scope（比如只 chat page）
- **flushPendingRefresh** 到底什么时候需要触发，master 的 `onChange(iOSPage)` 里的 `if oldPage == 1 && newPage == 0` 条件是否适用于路线 C 的翻页时机（UIKit paging 回写 binding 的时机可能略有不同）
- **iOSTabBarGestureBlocker** 是否还能用、或者要砍 / 改目标
- **PinBar 和 iOSChatTopBar 的视觉层叠**（见 4.5）
- master 最近有没有**和 wallpaper / safe area 相关的妥协**，可能在 merge 时重新回头发现问题

---

## 6. 建议的执行顺序

1. 粟粟**备份 profileId store** 目录（`~/Library/Application Support/MemoryPalace/*.store*`）
2. 本 cc 在 worktree 里跑 `git merge origin/master`
3. **逐个冲突文件** resolve：
   - `MemoryPalaceApp.swift`（Schema 变更关键）
   - `ContentView.swift`（body 架构融合）
   - `CardFlowView.swift`（以 master 为主，少量 re-apply）
   - `SidebarView.swift`（以 master 为主，直接 take theirs）
   - `SettingsView.swift`（小冲突）
4. 每 resolve 完一个 build 一次
5. 全部 resolve 完整体 build
6. Xcode run 回归测试：路线 C 10 项 + master 的 Pin / 搜索 / 回底按钮 / 数据备份 / 延迟置顶
7. commit merge 消息 + push
8. （可选）fast-forward merge 本分支到 master + push master

---

## 7. TL;DR 给另一 cc

- 31 commit（本分支，路线 C iOS paging 架构）要和 126 commit（master，功能 feature 大爆发）合
- 5 冲突文件，**方向正交**：ContentView body 结构以本分支为主（保 paging 架构）、CardFlowView/SidebarView/MemoryPalaceApp 以 master 为主（保新功能）、SettingsView 小手动
- 最关心的跨分支点：RightPanelNavigator 注入、flushPendingRefresh 融入、PinBar vs iOSChatTopBar 视觉、iOSTabBarGestureBlocker 是否过时
- 核心发现（`.ignoresSafeArea` UIView 物理溢出）见 `docs/gotcha-swiftui-ignoressafearea-hosting-overflow-2026-04-20.md`

---

## 8. Master cc 反馈 + 最终 Action Plan（2026-04-20 更新）

### 8.1 4 个决策全 align

| 决策 | 结论 |
|---|---|
| Q1 Merge 方向 | **A**（master → 本分支） |
| Q2 ContentView 策略 | 保路线 C 架构 + 融 `RightPanelNavigator` env + `flushPendingRefresh` onChange |
| Q3 RightPanelNavigator 注入 | **3 页全注入**（Sidebar 是 writer，Dashboard 3 面板 + ContentView 都是 reader） |
| Q4 Schema | master schema 全套 + 先备份 store |

### 8.2 Master cc 补了 3 个关键调整

#### 调整 A ⚠️ `iOSTabBarGestureBlocker` 必须改造（不能砍）

- 当前用途（`SidebarView:827`）：sidebar 横向 tab 栏横滑时，防 `TabView(.page)` 内部 UICollectionView.panGestureRecognizer 吞手势
- 路线 C 下 TabView 没了，但需求还在——改防 `PagingViewController.scrollView.panGestureRecognizer`
- **改造方案**：
  1. `PagingViewController` 暴露 `scrollView.panGestureRecognizer`（通过 `@Environment` 或 singleton ref）
  2. `TabBarGestureContainer` 的 `require(toFail:)` target 换成它
- 如果改造卡住 → ping master cc（他熟悉 blocker 需求，我这边 iOS paging 手势 API 熟）

#### 调整 B ⚠️ PinBar vs iOSChatTopBar 视觉层叠（真冲突）

- master PinBar：iOS 下 `safeAreaInset(edge: .top)` 挂 CardFlowView ScrollView，自己 `.padding(.top, 55)`（避 nav 胶囊 ~45pt）
- 路线 C iOSChatTopBar：高 ~200pt（blur+gradient+nav buttons），overlay(.top) 挂 iOSChatPage
- 两者都占顶部，会撞
- 修法二选一（合并后看实际视觉再定）：
  - (a) PinBar 的 top padding 55pt → iOSChatTopBar 实际高度（约 60pt 的 nav 区）
  - (b) iOSChatTopBar 改用 `safeAreaInset(.top)`，PinBar 自动避开（更干净但工作量大）

#### 调整 C 必须保留 master 的 `d5c09c9` 修复

- master commit `d5c09c9 fix(vm): buildTreeInBackground root 选择确定性化 — 修空白盲盒 bug`
- 原 bug：`dict.values.first(where:)` 非确定性导致"对话随机空白"
- 修法：path root 用 currentNodeId 回溯找
- **本分支同源代码也有此 bug**，merge 时 ConversationViewModel 要**以 master 为准保留修复**

### 8.3 Master cc 补的 4 个 context

| 点 | master 侧状态 | 本分支怎么办 |
|---|---|---|
| A. `DebugRenderSettings` / `DebugPageIndicatorMode` / `DebugThemeBackgroundMode` | master **没有** | 保留本分支的，merge 后不冲突 |
| B. ScrollToBottomButton 最新形态（2026-04-20 今天定的） | `.buttonStyle(.glass)`（iOS 26 官方 GlassButtonStyle）、不 clipShape/frame、`Image(chevron.down, size: 17, Theme.textMuted)`、挂 `safeAreaInset(.bottom)` 的 VStack、`atBottom` 阈值 200pt | 以 master 为准（CardFlowView 冲突以 master 为主） |
| C. `buildTreeInBackground` 非确定性 bug fix | master `d5c09c9` 刚修 | **必须保留** master 版 |
| D. TeamID 配置 | master `project.yml` 加了 `DEVELOPMENT_TEAM: 7TFJ93A25W` + `CODE_SIGN_STYLE: Automatic`（iOS target only） | auto-merge OK，xcodegen regenerate 不清签名 |

### 8.4 Master cc 确认 master 侧没动 wallpaper / safe area

- Pin / 回底 / 搜索 / 上下文总结都是逻辑功能
- 碰 safe area 的只有：iOS 键盘 fix（同源 B7 commit）+ ScrollToBottomButton 用 `safeAreaInset(.bottom)`
- `Theme.mainBg.ignoresSafeArea()` baseline 只在 master ContentView ZStack 的底层 → 路线 C 下**不需要**（每页自己 background + clipsToBounds 已兜底），merge 时 iOS 分支可以砍或只保 macOS

### 8.5 最终 Execution Plan

| 步 | 谁做 | 动作 |
|---|---|---|
| 0 | 粟粟 | 备份 `~/Library/Application Support/MemoryPalace/*.store*` |
| 1 | 本 cc | `git merge origin/master`（进入 merge state） |
| 2 | 本 cc | Resolve `MemoryPalaceApp.swift`（以 master Schema 为主 + 融本分支 ThemeManager 初始化） |
| 3 | 本 cc | Resolve `ContentView.swift`：保本分支 iOSLayout 架构 + 加 `@Environment(RightPanelNavigator.self)` + `injectPagingEnv` 加 `.environment(rightPanelNavigator)` + `onChange(iOSPage)` 加 `oldPage==1 && newPage==0 → flushPendingRefresh` + 保留 `PerfCounters` debug + `Theme.mainBg.ignoresSafeArea()` baseline 仅 macOS 留 |
| 4 | 本 cc | Resolve `CardFlowView.swift`（以 master 为主，底部 blur fix 对照 master 最新 gradient 决定要不要 re-apply） |
| 5 | 本 cc | Resolve `SidebarView.swift`（以 master 为主，`take theirs`，本分支 3 个早期 wallpaper commit 的修改对路线 C 已失效） |
| 6 | 本 cc | Resolve `SettingsView.swift`（小手动） |
| 7 | 本 cc | build 验证（xcodebuild MemoryPalaceIOS） |
| 8 | 本 cc | **改造 `iOSTabBarGestureBlocker`**：PagingViewController 暴露 `scrollView.panGestureRecognizer` + blocker 的 `require(toFail:)` 切换目标。**卡住就 ping master cc** |
| 9 | 本 cc | 再 build 验证 |
| 10 | 粟粟 | Xcode run，手测 3 项：<br/>① Pin 跳转（核心联调）<br/>② Sidebar tab 栏横滑（blocker 改造是否生效）<br/>③ 切对话"先空白切楼层才好"bug（`d5c09c9` 保留后应已修） |
| 11 | 粟粟 + 本 cc | 看 PinBar vs iOSChatTopBar 实际视觉，定修法 (a) 或 (b) |
| 12 | 本 cc | 全部 OK 后 `git commit` merge message + `git push` |
| 13 | 粟粟 | （可选）fast-forward merge 本分支到 master + push master

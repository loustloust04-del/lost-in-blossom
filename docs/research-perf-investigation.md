# Research: 卡顿全面诊断（2026-04-19）

> 粟粟报告：17 Air 小卡 / 14 大卡；重装 app 首次卡；打字输入卡。
> "现在卡顿的问题其实很严重了"。
> 这份 doc 不改码，先分类可疑点 + 给她 3 个快速诊断实验。

## 一、症状分类

| 症状 | 设备 | 触发时机 | 可能性质 |
|------|------|----------|---------|
| A. 冷启动/重装后**首次点对话**卡 | 两端都卡 | 新装 app 第一次进入对话 | SwiftData store 首次打开、SwiftUI view 首次布局、或 **近期 B7 系列 view tree 变复杂** |
| B. 键盘**打字**卡 | 两端都卡 | 发消息时输入延迟 | SwiftUI TextField re-render cascade，最可疑是 B7 的 `.onTapGesture` + ChatInputBar @Observable 依赖 |
| C. 14 比 17 Air 明显卡 | 14 专属放大 | 所有操作 | SoC 性能差 + 同样代码在 A15 上开销更大。T9 范畴。|

**关键约束**：A 是"重装后首次"—— store 干净空的，排除"20 万 node 大 store 扫描"那条假设。说明问题在**代码/框架层**而非数据层。

## 二、最可疑的 regression 点（本次 B7 + 延迟置顶改动）

按近 2 天我改动的范围，从**最可能**到**最不可能**排列：

### R1 — ContentView 新观察 ProfileManager
我在 `ContentView` 加了：
```swift
@Environment(\.scenePhase) private var scenePhase
@Environment(ProfileManager.self) private var profileManager: ProfileManager?
.onChange(of: scenePhase) { _, newPhase in ... }
.onChange(of: profileManager?.currentProfile.id) { _, _ in ... }
```

**问题**：`@Observable ProfileManager` 任何 property 变化都会触发 ContentView body 重算；每次 body 重算，所有依赖 body 输出的子 view（`iOSLayout`、`SidebarView`、`iOSChatPage`）都要 diff。

而 `ContentView` 的 body 挂着**整个 iOS 三页 TabView + 所有 sheet**，重算一次开销不小。

**另外**：`MemoryPalaceApp:378 .id(profileManager.currentProfile.id)` —— 这是个**重建炸弹**。只要 `currentProfile.id` 变化，SwiftUI 销毁并重建整个 ContentView（连同 ConversationViewModel、所有子 view、ScrollView state）。这本来只在"切楼层"时触发；但现在 `scenePhase`、`.onChange(of: ...)` 等任何 body 读取，都会让 ContentView 在 body 期间 observe profileManager。**如果 ProfileManager 在 app 启动后短时间内触发多次通知**，可能重建 ContentView 多次。

### R2 — ChatInputBar 新加 `.onTapGesture`
```swift
.glassEffect(.regular.tint(...).interactive(), in: .rect(cornerRadius: 20))
.contentShape(Rectangle())
.onTapGesture { isFocused = true }
```

`.onTapGesture` 在 iOS 26 + glassEffect(interactive) 组合上性能开销未知。`.contentShape(Rectangle())` 会让整个 HStack 都参与 hit test。但在一般 app 里这都不致于 "卡"。

风险中等：tap gesture 挂在覆盖整个 input bar 的 Rectangle 上，每次 TextField 内部 layout 改（光标闪烁、placeholder 动画）时 hit-shape 可能重算。

### R3 — `padding(.bottom, isFocused ? 5 : 8)`
依赖 `isFocused` 的 animation transition。和 glass blur 的 `height: isFocused ? 60 : 160` + `offset(y: isFocused ? 10 : 40)` 同时驱动。每次键盘 focus 切换触发多个 view 的 frame/offset 动画。这不是新引入的，但 5 和 8 这种小 delta 让动画更频繁（大 delta 能"一锤子")。

### R4 — iOS 四个 ScrollView 都加了 `.refreshable` + `.scrollBounceBehavior(.always)` + `.scrollIndicators(.hidden)`
`.refreshable` 挂 UIRefreshControl + pan gesture。4 个 ScrollView 每个都挂，view tree 变重。每次 `sidebarRefreshTrigger++` 触发 re-fetch，ScrollView 可能重建。

`.scrollBounceBehavior(.always)` iOS 17+ API 强制 always bounce，可能禁用了一些优化路径。

### R5 — 排序从 `[lastOpenedAt DESC, updateTime DESC]` 简化为 `[updateTime DESC]`
不应该变快变慢（没加索引情况下两者都是全表扫描）。除非 SwiftData 有某种隐式 "lastOpenedAt 有缓存"的优化（不太可能）。**影响不大**。

### R6 — `StickerViewModel.onConversationMutated` closure
每次 CardFlowView.onAppear 重新 assign closure。OK but no-op on perf.

### R7 — debounce Task
Task.sleep(3s) 在 markDirty 后运行，基本是 idle state，极小开销。

## 三、固有性能瓶颈（非本次引入）

即使 revert 到今天之前的代码，这些仍可能贡献卡顿：

### F1 — `ConversationViewModel` 是**巨型 @Observable class**
~1000 行，几十个 @Observable 字段（`selectedConversation`, `currentPath`, `branchChoices`, `isLoading`, `scrollToNodeId`, `highlightedNodeId`, `sidebarRefreshTrigger`, `globalWorldBookEntries`, `inConvSearchKeyword`, `inConvMatches`, `inConvMatchIndex`, `bubbledBranches`, `branchInfoMap`, `streamingText`...）。

**问题**：`@Observable` 的观察粒度虽然 per-property，但如果某个 view 用了任一字段（哪怕只读一次），该字段变化就重算。streamingText **每个 token 都变** → 触发所有 observe ConversationViewModel 的 view 重算。按经验这会让流式 AI 回复时整个 CardFlowView 每个 token 都抖动。

打字时 inputText 只在 ChatInputBar 内部（@State），不会扩散；但如果 chat 气泡有 `isStreaming` 条件（line 29 `isNodeStreaming = viewModel.providerRouter.isStreaming && ...`）—— provider isStreaming 变化会让整个 LazyVStack 重 diff。

### F2 — MarkdownUI 每气泡每次重新 parse
`Markdown(displayText)` 每次 body 调用就重建 View（没有 memoization）。单条长消息（360 条对话里的大段）MarkdownUI parse + layout 几十毫秒。

### F3 — `ContentCleaner.clean` 有 NSCache 但是 cacheKey 带 `node.content.count`
CardFlowView:860: `ContentCleaner.clean(node.content, cacheKey: "\(node.id)_\(node.content.count)")`。Streaming 时 content 每 token 变化 → cacheKey 变化 → cache miss → 重新 clean。这是流式刷屏的热点。但发完消息就稳定了。

### F4 — 首次冷启动 ProfileManager 初始化
`ProfileManager.init()` → `loadProfiles()` (UserDefaults) → `makeContainer(for:)` (SwiftData container 打开)。`Self.migrateMemoryNotesIfNeeded(container:)` 在 `MemoryPalaceApp.init` 里**同步**跑：
```swift
init() {
    FontManager.registerImportedFonts()  // iOS noop
    Self.migrateMemoryNotesIfNeeded(container: profileManager.container)
}
```

`migrateMemoryNotesIfNeeded` 第一次跑要 fetch 所有 `MemoryNote` → 过滤 manual → 转成 Memory。粟粟数据可能几千条记忆，**阻塞 app 启动主线程直到完成**。

**但重装 app 后 MemoryNote 是空的** → migrateMemoryNotesIfNeeded 第一次 fetch 返回空 → 立刻 set key 完事。这条**不会引起**重装后首次卡。

### F5 — SwiftData store 首次打开的 schema 验证
即使 store 空，`ModelContainer(for: schema, configurations: [config])` 首次会建 CoreData store 文件、跑 schema 验证。Schema 有 12 个 model type（Conversation、MessageNode、UserCard、ConversationTag、FavoriteItem、ImportRecord、ImportConversationChange、MemoryNote、Memory、WorldBook、StickerAsset、PlacedSticker）。每个 model 要注册 SQLite 表、索引、关系。**重装后第一次必然慢几百毫秒**。这是 SwiftData 固有开销。

### F6 — 整个 app 的 view tree 纵深
ContentView 里：
```
ContentView
 └─ iOSLayout
     └─ TabView(.page)  ← UICollectionView
         ├─ iOSListPage  (SidebarView，巨大)
         ├─ iOSChatPage  (ZStack + CardFlowView + 顶栏按钮)
         └─ iOSDashboardPage (RightPanelView)
     + 页面指示器 overlay
```

每个 iOS page 都包含大量 @Observable 依赖 + SwiftData fetch。SwiftUI 初次 layout 需要**全部遍历**。

## 四、我建议的快速诊断实验（请粟粟帮跑）

### Exp-1：Git bisect 级回滚验证是不是 B7 + 延迟置顶引入
从 `4a653c2`（B7 前的 commit）打一个 TestFlight/debug build 装粟粟 17 Air，对比：
- 重装测"第一次点对话"卡不卡？
- 打字卡不卡？

**如果不卡** → R1/R2/R3 是元凶，按可能性逐个 revert 测
**如果也卡** → 是 F1-F6 固有问题，B7 只是放大

### Exp-2：Instruments Time Profile（我指导粟粟用 Xcode）
1. Xcode Product → Profile，选 Time Profiler
2. 装 app 到真机，启动后做"点对话 + 打字"
3. 导出 trace 给我看
4. 热函数 top 10 就知道在哪烧时间

### Exp-3：打一个"性能探针 debug build"
在以下位置打 `CFAbsoluteTimeGetCurrent()` 日志：
- `ProfileManager.init()` 开始/结束
- `ModelContainer` 创建
- `ContentView.body` 进入（每次记录，看 N 秒内 body 被调用几次）
- `loadConversation` 开始/applyTreeData 结束
- `ChatInputBar.body` 被调次数

跑一遍看 log。相比 Instruments 更轻量但需要我改码加 log。

## 五、不用实验也能直接做的"降风险"改动

以下改动几乎无风险，可以先上：

### Quick-Win 1：去掉 ContentView 的 `@Environment(ProfileManager.self)` 依赖
改用 `NotificationCenter`（Profile change 发通知）或者在更深层的 view 里 observe，让 `ContentView.body` 不 re-eval profile。

**代价**：`.onChange(of: profileManager?.currentProfile.id)` 的 flush 要换成另一种方式（或者放到 SidebarView 内部 observe）。

### Quick-Win 2：把 `@Environment(\.scenePhase)` 和相关 onChange 搬到更小的 wrapper view
同上思路，把"app 生命周期监听"隔离到独立 view，不污染 ContentView。

### Quick-Win 3：`ConversationViewModel` 拆 observed scope
`streamingText` 单独拎成一个 observable holder，这样它每 token 变化只触发订阅了 `streamingText` 的 view（具体那条 assistant 气泡），不扩散到 sidebar / InputBar。

**代价**：影响面最大，重构级。先别动。

### Quick-Win 4：`.scrollBounceBehavior(.always)` 可能是性能开销源
只有空态 ScrollView 真需要这个（让下拉能触发）。其它 3 个有内容 ScrollView 去掉它。
```swift
// 空态卡保留
.scrollBounceBehavior(.always)

// 有内容的 3 个 ScrollView 删掉
```

零风险。

### Quick-Win 5：`.refreshable` 只给有内容 ScrollView 加
空态卡已经有 debounce flush 在外层（chat→sidebar 切换），其实可以不挂 refreshable（pull 无意义 since 没啥可"刷新"）。

**代价**：空态下拉不转圈（可能失去你喜欢的 UX）。低价值选项。

## 六、我建议的下一步

**我倾向先做 Exp-1（git bisect 回滚验证）** —— 用 `git stash` + `git checkout 4a653c2` 打一个 baseline build 装真机。如果 4a653c2 不卡，我们就知道问题是本次新改动引入。

但 revert 到 4a653c2 意味着键盘 fix / 列表下拉刷新 / 延迟置顶**暂时回退**。粟粟体验倒退，只为诊断。

替代方案：我**单独 revert R1（ContentView 新 observer）** 一个 commit 装测 —— 更精准。

---

## 七、问粟粟

1. **要不要 Exp-1（完整回滚到 B7 前）装测？** 还是要我**只 revert R1**（单独去掉 ContentView 的 ProfileManager/scenePhase observer）？后者影响面小，但诊断精度低。
2. **Instruments Time Profile 你会用吗？** 要我写个 step-by-step？（我自己不能操作你的 Xcode，但能教你怎么 profile）
3. **"打字卡"** 能描述更精确？是：
   - 点 TextField 到键盘弹起的延迟？（iOS 系统键盘冷启动，app 管不了）【有】
   - 键盘已弹起后，按键到字出现的延迟？（SwiftUI TextField re-render 问题）【也有】
   - 打中文拼音候选词时卡？（输入法 + SwiftUI binding 性能）
4. **"第一次点对话"** 从哪里点？**新建对话** 还是 **列表里已有对话**？新装时列表应该空的。

   【先只 revert R1（ContentView 的 ProfileManager/scenePhase observer），单独装测看看。

   帮我加 Exp-3 的性能探针 log，我跑完把 console 输出截图给你。

   打字卡是键盘已经弹起来之后，按键到字出现有延迟，一顿一顿的。

   已有的】

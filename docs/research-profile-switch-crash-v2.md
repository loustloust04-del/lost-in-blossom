# Research: 切楼层 crash —— 现行 7cb7601 fix 仍翻车

> 2026-04-22 · 粟粟反馈：「前几次修法都失败了。你必须深度调研，先用模拟机测试好了再喊我用真机。」
> 分支：`codex/theme-kelivo-settings`（worktree `theme-kelivo-settings`）
> 触发：iOS 真机 切楼层
> 前置：commit `7cb7601` 已经加了 `Notification.profileWillSwitch`（ConversationViewModel / PagingViewController / MemoryPanelView / MemorySettingsTab ×2 订阅），但粟粟反馈还在 crash。

## 1. 现行 7cb7601 fix 的**plan vs 实况** diff

参照 `docs/plan-profile-switch-atomic.md` 5 步 checklist：

| Step | plan 要求 | 实际 `7cb7601` | 差异 |
|---|---|---|---|
| 1 | `Notification.Name.profileWillSwitch` 定义 | ✅ MemoryPalaceApp.swift:570 | — |
| 2 | `switchTo` **3 步**：notify → flip `currentProfile` → `DispatchQueue.main.async { container = ... }` | ❌ **同一 run loop 同步** flip `currentProfile` + `container`（MemoryPalaceApp.swift:139-142） | **缺 `DispatchQueue.main.async`** —— container 换没有异步到下一 run loop，旧 view 没有"一 tick 喘息" |
| 3 | `ConversationViewModel.init` observer 清 SwiftData 实例 ref | ✅ ConversationViewModel.swift:42-65 | — |
| 4 | `StickerViewModel.init` observer 清 `placedStickers` / `stickerAssets` / `selectedPlacedStickerId` | ❌ **完全没做** —— StickerViewModel 里没 observer（StickerViewModel.swift 全文 grep 无 `profileWillSwitch`） | **漏一整步** |
| 5 | `MemoryPanelView` + `MemorySettingsTab ×2` `.onReceive` 清 `memories` | ✅ MemoryPanelView:184 / MemorySettingsTab:221 / 550 | — |

**额外**：commit 7cb7601 附加了一个 plan 没写过的动作 ——
- PagingViewController observer 把 3 个 child HC.rootView 替换成 `Color.clear`（Paging/PagingViewController.swift:118-131）

这在 plan 外是 OK 的（提前拆 child HC 的 SwiftUI sub-tree），但它**不能替代** step 4 的 StickerViewModel 清理。

## 2. 粟粟日志分析

粟粟贴的 log（精简版）：

```
[PERF] App.init total=68ms
[PERF] ContentView.body #1 t=798548157.697
[PERF] ContentView.body #2 t=798548162.057
[PERF] ContentView.body #3 t=798548167.252
[PERF] ContentView.body #4 t=798548171.194
<0x1521eb340> Gesture: System gesture gate timed out.
Called -[UIContextMenuInteraction updateVisibleMenuWithBlock:] while no context menu is visible. This won't do anything.
Adding '_UIReparentingView' as a subview of UIHostingController.view is not supported ... (× 3)
[PERF] ContentView.body #5 t=798548173.150
[PERF] ContentView.body #6 t=798548173.151   ← 1ms 后
```

### 关键观察

**(a)** body #5 / #6 相差 1ms —— 同一 run loop 两次重算，和 "currentProfile flip + container flip 在同一 run loop" 时序吻合（plan step 2 缺失的证据）。

**(b)** 3 条 `_UIReparentingView` 警告对应 3 个 child HC（list / chat / dash）。触发机制：handleProfileWillSwitch 把每个 HC 的 rootView 换成 `Color.clear`，SwiftUI 拆旧 view tree 时发现里面的 `.contextMenu` modifier 的 preview reparent view 没法 reparent 到正在被拆的 HC.view 上。

- iOS 文档警告原文："Add your view above `UIHostingController.view` in a common superview or insert it into your SwiftUI content in a `UIViewRepresentable` instead."
- 含义：**context menu 的 reparent 机制假设 `hc.view` 是顶层**（window 的 rootVC 的 view）。路线 C 下 `hc.view` 是 PagingVC.scrollView 的 subview —— 上面有 `UIScrollView + UIView` 这两层 UIKit，reparent view 加不上去。

→ 这 3 条警告**不直接 crash**，但它是个**信号**：路线 C 下旧 SwiftUI view tree 在 dismount 时，内部 contextMenu 的生命周期清理跑不完整。清理残留可能让旧 view tree 的 body 在下一拍还在跑。

**(c)** "Gesture: System gesture gate timed out" —— UIKit 手势协调 warning，通常伴随 `.contextMenu` long-press 或 paging 水平 swipe 的 require(toFail:) 依赖超时。配合 (b) 看，说明切楼层瞬间 sidebar 或 chat 页上的 `.contextMenu` long-press 识别器还在 pending。

**(d)** 粟粟没贴 fatal error stack —— 日志到 body #6 就断了。两种可能：
- 日志被截断（Xcode console 或 Console.app 滚出去了）
- 不是真 crash，是 UI 完全卡死（6 次 body 后 main thread 陷入死循环或 UI layer 状态不一致渲染不出来）

**建议**：让粟粟下次 crash 时抓 **Xcode Debug Navigator 的 stack trace** 或 iOS Device Logs 的 `.ips` crash 文件。现行日志判不了是哪一行 fatal。

## 3. 没被 7cb7601 清的 `@Model` / SwiftData ref 盘点

这是**最大的技术债**。plan step 4 漏了，除此之外我又盘了一遍其他 @State / @Observable 里可能持有旧 container 的 @Model 实例。

### 3.1 **StickerViewModel**（plan step 4 漏，当前版本仍未修）

文件：`MemoryPalace/ViewModels/StickerViewModel.swift:13-60`

| 字段 | 类型 | 旧 container reset 后影响 |
|---|---|---|
| `stickerAssets` | `[StickerAsset]`（@Model） | ⚠️ fatal 候选 |
| `placedStickers` | `[PlacedSticker]`（@Model） | ⚠️ fatal 候选 |
| `selectedPlacedStickerId` | `UUID?` | 安全（不是 @Model ref） |
| `stickerSizes` | `[UUID: CGSize]` | 安全 |
| `bubblePositions` | `[String: CGFloat]` | 安全 |
| `copiedSnapshot` | `StickerSnapshot`（value type） | 安全 |
| `undoStack` | `[StickerUndoSnapshot]` | 需看 StickerUndoSnapshot 是不是持 @Model —— **未盘** |

`stickerAssets` / `placedStickers` 在这些 body 路径被读：
- `StickerCanvasLayer.body`（CardFlowView 里 active chat page）—— `ForEach(stickerVM.placedStickers, id: \.id) { ... }`（StickerCanvasLayer.swift:31）
- `StickerCanvasLayer.stickerItem` 内部读 `sticker.stickerAssetId` / `sticker.noteContent` / `sticker.noteStyle`（可能 fatal）
- `StickerKeyboardPanel.body` —— `ForEach(stickerVM.stickerAssets, id: \.id)`（StickerKeyboardPanel.swift:109）
- `StickerLibraryView.body` —— `stickerVM.stickerAssets`（StickerLibraryView.swift:25）

**推理**：切楼层 → container reset → 旧 PlacedSticker 实例被 destroy → 旧 CardFlowView.body 在 dismount 最后一次跑时 iterate `placedStickers` 访问 `sticker.id` → **fatal**。

这个路径和 plan 里 "Crash B: Conversation.id.getter ← CardFlowView.body" 完全同构。只不过触发实例从 Conversation 换成 PlacedSticker / StickerAsset。

### 3.2 **WorldBookPanelView** 的 `@State` 残留

文件：`MemoryPalace/Views/WorldBookPanelView.swift:13-34`

```swift
@State private var worldBooks: [WorldBook] = []
@State private var editingEntry: WorldBookEntry?
@State private var renamingBook: WorldBook?
@State private var deletingBook: WorldBook?
```

`WorldBook` / `WorldBookEntry` 如果是 @Model：切楼层时这个 view 如果还 mounted（右栏"世界书"tab 打开），body 跑时 `ForEach(worldBooks, id: \.id)` 访问 id → **fatal 候选**。

`WorldBookEntry` 看起来是 value type（从命名推测），`WorldBook` 是 @Model。需要实证：

```bash
grep -n "@Model\|final class WorldBook" MemoryPalace/Models/WorldBook*.swift
```

### 3.3 **@Query 的 SidebarView / CalendarPanelView**

- `SidebarView.swift:36` `@Query(sort: \ConversationTag.order) private var tags: [ConversationTag]`
- `CalendarPanelView.swift:9` `@Query(...)`

`@Query` 理论上自动跟 `.modelContext` 变化 re-fetch，但**不保证 dismount 前的最后 body 不读旧数组**。路线 C 下 SidebarView 在 page 0 的 child HC 里 —— `handleProfileWillSwitch` 把 rootView 换成 `Color.clear` 后，SwiftUI 拆旧 tree 时 `tags.map(...)` 可能读已 reset 的 @Model 实例。

但这个不是"大概率"候选 —— @Query 自己有 SwiftData 的防御层，而且路线 C 的 PagingVC.handleProfileWillSwitch 先拆 rootView 的逻辑已经**在 container flip 之前**执行了（Notification 是同步的）。所以 SidebarView 拆在 container reset 之前，应该安全。

→ 暂列为低优先级。

### 3.4 其他未盘的 @State

- `MemoryPanelView.swift` 有几个 `@State` 存 `NavigationTarget`（值类型？）
- `CardFlowView` 有 `@State var pinCurrentIndex: Int` 等，都是 value
- ContentView 有 `@State private var viewModel = ConversationViewModel()` + `@State private var stickerVM = StickerViewModel()` —— 这两个 VM 重建 @State 随 `.id(profile.id)` 变化**会整个丢**，新 profile 用新 VM 实例。**但**旧 VM 的 deinit 发生在 SwiftUI reconcile 下一拍，旧 body 还能跑一拍。

## 4. Route C 架构的根性坑（为什么 master 不 crash）

- **master**：`TabView(.page) { ... }.id(profile.id)` —— 所有 3 页都在主 SwiftUI tree 里。`.id()` 变 → SwiftUI commit phase 原子 dismount 旧 tree + mount 新 tree，旧 body 不会在 container reset 后再跑。
- **kelivo 路线 C**：`PagingContainerView(UIViewControllerRepresentable)` 包 `PagingViewController`（UIKit VC），里面 3 个 `UIHostingController`。每个 HC 有**独立的 SwiftUI sub-tree**，生命周期由 UIKit `addChild/didMove` 管理。SwiftUI 主 tree dismount（`.id()` 变触发）**不会原子拆** child HC 的 SwiftUI sub-tree —— UIKit 层 child HC 先于 SwiftUI 清理完，SwiftUI sub-tree 的最后 body 有机会在 `modelContainer` 注入 new container 后跑。

这就是 7cb7601 commit msg 里写的根因。Notification 方案是**权宜修法**（让旧 body 读到 nil/空），不动路线 C 架构。

## 5. 三种可能的 fix 路线（从小到大）

### 路线 A（最小）：补 plan 没做的两件事

**改动**：
1. `MemoryPalaceApp.switchTo`：container swap 挂 `DispatchQueue.main.async`（plan step 2 原文）
2. `StickerViewModel.init` 加 `profileWillSwitch` observer 清 `placedStickers` / `stickerAssets` / `selectedPlacedStickerId`（plan step 4 原文）

**风险**：如果 WorldBook 也是 @Model，还得补 WorldBookPanelView 的 `.onReceive` 清 `worldBooks` / `renamingBook` / `deletingBook`。

**性价比**：高。修完看 log 是不是还 crash，不行再上路线 B。

### 路线 B（中）：彻底扫盲 @Model ref

同路线 A + 系统性补齐所有持 @Model ref 的 @State / @Observable 字段的清理：
- WorldBook 相关 @State
- 其他 Panel / Settings Tab 的 fetch 缓存
- CardLibraryPanelView, FavoriteItem 相关 view

**风险**：改动面大，容易漏。

### 路线 C（大）：重构 ContentView.id 对 container 的依赖

放弃 Notification 方案，改成：
- `PagingContainerView` 本身挂 `.id(profile.id)` → SwiftUI 直接销毁重建 PagingVC 和 3 个 HC
- 或：`PagingContainerView` 的 `makeUIViewController` 的 `coordinator` / `hostingController` 数组监听 profile change，主动 `removeFromParent` + 重新 `addChild` 新 HC

**风险**：重构路线 C 架构，可能引入新的 UI bug（键盘 / 背景 / 翻页 / 贴纸 / 滚动）。上一个 postmortem（`postmortem-kelivo-keyboard-wallpaper.md`）花一天才修好路线 C 下的键盘 + 背景，不敢乱动。

## 6. 模拟器复现尝试（今天）

- `xcodebuild -scheme MemoryPalaceIOS -destination "platform=iOS Simulator,name=iPhone 17 Pro"` build ✅
- `xcrun simctl install + launch` ✅ app 启动
- 试图用 `cliclick` 自动 tap 进 "设置 → 通用" 查找 profile 切换入口 —— **绝大部分 tap 不 fire**（osascript 报 `-25211` 缺辅助权限；cliclick 只有第一次开 sheet 的 tap 生效，后续 tap 静默）
- 换 `dd+du` / `osascript` / `System Events click at` 都被辅助权限或 Simulator 事件传递机制挡掉

**结论**：
- 纯 code 分析已够定位 plan step 2 + step 4 的漏洞，不需要非跑复现
- 真要跑完整复现，要粟粟先给 Claude 在 "System Preferences → Privacy & Security → Accessibility" 里加 `cliclick` 和 `osascript`（或者粟粟手动点一次 sim 验证）

## 7. 未盘的事（下一步调研）

- [ ] `WorldBook` / `WorldBookEntry` / `StickerUndoSnapshot` 是否 @Model
- [ ] `CardLibraryPanelView` 里的 `@State [UserCard]` 是否持 @Model ref（UserCard 是 @Model）
- [ ] `ImportView` / `ImportRecord`  相关 view 的 @State 盘点
- [ ] `GeneralSettingsTab` / `StickerSettingsTab` 的 fetch 缓存（`stickerAssetCount` 是 Int 安全，但内部有别的 fetch 没？）
- [ ] 真机 crash 的 stack trace（粟粟提供 .ips 或 Xcode Debug Navigator 截图）

## 8. 粟粟要批注的点

- [ ] 3 路线选哪个（我建议先试 **路线 A**，log 还 crash 再补路线 B 的未盘项）
- [ ] 下次 crash 能不能抓 stack trace？光 console log 判不了 fatal 在哪
- [ ] 有没有一种"能稳定复现"的 repro 步骤（比如 "开 app → 点左上角 chat 图标 → 点 profile 切换" 这种 1-2-3 步）。我在模拟器试了但切换路径没走通

---

**我的判断**：7cb7601 修漏了 plan 原计划的 step 2（DispatchQueue.main.async）和 step 4（StickerViewModel observer）两个关键点。StickerViewModel 里的 `placedStickers` / `stickerAssets` 持的是 `@Model` 实例，container reset 后旧 CardFlowView.body 读 `placedStickers` 就 fatal —— 和原 plan 里 "Crash B" 路径完全同构。

先做 路线 A 俩小改，build 干净 → 粟粟真机测一轮。不行再上路线 B。

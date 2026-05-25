# Research: iOS 翻页容器 UIKit 重构 — 每页独立 UIHostingController

日期：2026-04-20
分支：`codex/theme-kelivo-settings`
前置：Phase 1 (commit `8d6ce64`) + Phase 2 v1 (commit `f7af017`) 的 SwiftUI ScrollView + offset trick
状态：**Research，等粟粟批注**

---

## §0 TL;DR

- SwiftUI 框架内 `.ignoresSafeArea` 的 safe area extension 和 `.offset`（或 UIScrollView contentOffset translate）**在同一 UIHostingController scope 下架构性不兼容**，extension 由 UIHostingController 在 UIKit 层独立渲染，不跟 SwiftUI transform / scroll 走。这是 Phase 2 v1 "safe area 残影"的根因。
- 解法：**用 UIKit `UIScrollView` + 三个独立 `UIHostingController` 做翻页**。每页独立 VC，每页独立 safe area context，wallpaper 放 chat page 内部 `.background { … }.ignoresSafeArea()`，随 page UIView 的 frame 物理位置 translate（UIScrollView.contentOffset 改变所有 subview 的 rendering position）。
- 选 `UIScrollView(手动 paging)` 而不是 `UIPageViewController`：3 页静态，不需要 VC 动态 load/unload；`UIScrollView` 的 `isPagingEnabled` / `bouncesHorizontally` / `isScrollEnabled` 都是直接属性，更可控。
- 动态壁纸 future-proof：以后 chat page 内的 `ChatWallpaperBackdrop` 换 Lottie / MetalView / Shader 都只改 chat page 内部，不动翻页架构。

---

## §1 背景 / 为什么必须走 UIKit

### 1.1 Phase 2 v1 的两个 bug

`f7af017` 的结构：

```swift
body
  .background {
      ZStack {
          Theme.sidebarBg
          ChatWallpaperBackdrop(...).offset(x: pageWidth - scrollOffsetX)
      }
      .ignoresSafeArea()
  }
  .overlay(alignment: .top) {
      iOSChatTopBar.offset(x: pageWidth - scrollOffsetX)
  }
```

测试截图（iPhone 17 Air + Dynamic Island）显示：

- **Bug A**：Page 2（dashboard）时屏幕**最左一条 ~10px 窄带**漏出 wallpaper。Page 2 的 `offset = -pageWidth`，wallpaper 应推到左屏外。10px 残留怀疑是 `pageWidth` state 与 `ScrollView` 的 paging step 差几 px，但没实测确认过。
- **Bug B**：Page 0（列表）时**右上 status bar 右侧 + 右下 home indicator 右侧**漏出 wallpaper。Page 0 的 `offset = +pageWidth`，wallpaper 主体推到右屏外，但 **top / bottom safe area extension 没跟 offset 走**，留在原位。Dynamic Island / iOSChatTopBar 遮住中间，仅岛右侧露出 wallpaper 真实纹理。

### 1.2 `.ignoresSafeArea` 和 `.offset` 的架构性不兼容

**Hypothesis（基于观察 + `SwiftUI` doc `ignoresSafeArea(_:edges:)` 的 "Expands the safe area of a view" 语义）**：

- SwiftUI view X `.ignoresSafeArea()` → 告诉 UIHostingController 在 X 的 view 渲染**外扩到 window edges**
- 这个外扩是 UIHostingController 级别的**渲染指令**，而不是 X 自身 UIView 的 frame 扩大
- SwiftUI `.offset()` → 作用 X 的 UIView.transform 做 translation。X 的主体 rendering 跟着 transform
- 但 UIHostingController 的 safe area "extension tiles" 是**独立渲染层**，**不受 X.transform 影响**

→ 结果：`.offset` 能推动 X 本体但推不动 extension。**在同一个 UIHostingController scope 里绕不过去**。

### 1.3 SwiftUI 内已穷举的路

| 方案 | 结果 |
|---|---|
| body `.background { wallpaper.offset.ignoresSafeArea }` | Bug B（当前 Phase 2 v1） |
| `.background { wallpaper.ignoresSafeArea.offset }` | 同 Bug B（顺序无关） |
| GeometryReader 手动 `.frame(screenSize)` + 反向 offset 不用 `.ignoresSafeArea` | GeometryReader 在 `.background` 里拿到的 safeAreaInsets 可能不稳定；复杂且脆弱 |
| `.mask(Rectangle.offset)` 替 `.offset` | wallpaper 不跟手滑（不是"一页就是一页"） |
| wallpaper 放 iOSChatPage `.background.ignoresSafeArea`（**同** UIHostingController scope） | 之前测：wallpaper 漏到相邻页 safe area → 同 Bug B 根因 |
| SwiftUI ScrollView `.ignoresSafeArea()` 让所有 page view 扩展到 safe area | 控件（nav buttons / input bar）跟着扩展到 safe area 里，位置诡异 |
| TabView | 每页独立 UIHostingController（safe area 独立 ✓），但翻页动画相邻页可见（"穿模"），bounce 不好禁 |

**结论**：SwiftUI 框架内**没有**同时满足"每页独立 safe area + 无 bounce + 无穿模 + wallpaper 漫满屏 + 一页就是一页"的方案。走 UIKit。

### 1.4 动态壁纸 future-proof

粟粟之后想做动态壁纸（Lottie / MetalView / Shader / 视频）。这些组件：

- 通常是 UIView-based（`UIImageView` / `MTKView` / `WKWebView` / `AVPlayerLayer`），嵌入 SwiftUI 需要 `UIViewRepresentable`
- 动态壁纸的动画独立于翻页动画，**必须和翻页解耦**

**如果 wallpaper 在 body 层 + offset trick**，动态壁纸组件也得跟着 offset 动画 → 动画与翻页耦合。

**如果 wallpaper 在 chat page 内部**，chat page 被 UIScrollView 物理 translate，wallpaper 跟着 translate（物理位置移动），动态壁纸自己的动画不受影响。**完美解耦**。

---

## §2 架构

### 2.1 组件层级

```
ContentView.body (SwiftUI)
  └─ PagingContainerView (UIViewControllerRepresentable)
       ├─ makeUIViewController() → PagingViewController(UIKit)
       │    ├─ view = UIScrollView(isPagingEnabled: true, bouncesHorizontally: false)
       │    └─ addChild × 3 → UIHostingController<ListPage/ChatPage/DashPage>
       │         ├─ .view added to UIScrollView at x = 0 / pageW / 2·pageW
       │         └─ 每个 HC 独立 safe area context
       └─ updateUIViewController(_:context:) → 同步 SwiftUI state 到 UIKit
```

### 2.2 数据流

**SwiftUI → UIKit**（`updateUIViewController` 里）：

- `currentPage: Int`（binding）变化 → `PagingViewController.scrollToPage(_:animated:)`
- `disableScroll: Bool`（e.g. `stickerVM.isEditingStickers`）→ `scrollView.isScrollEnabled = !disableScroll`
- 每页的 SwiftUI content 作为 rootView 参数传入，变化时 `hostingController.rootView = newRootView`

**UIKit → SwiftUI**（`UIScrollViewDelegate` 回调）：

- `scrollViewDidEndDecelerating` → 算出 page index → `currentPage = newPage`
- `scrollViewDidEndScrollingAnimation` → 程序化切页完成的同步

### 2.3 每页的 SwiftUI content

```swift
// List page
iOSListPage
  .background(Theme.sidebarBg.ignoresSafeArea())   // 列表页自己的底色漫 safe area

// Chat page
iOSChatPage
  .background {
      ChatWallpaperBackdrop(...)       // wallpaper 在这里
          .ignoresSafeArea()           // per-page scope, 不漏到其他页
  }
  .overlay(alignment: .top) {
      iOSChatTopBar                    // top bar 也放进 chat page 内部
  }

// Dashboard page
iOSDashboardPage
  .background(dashboardBg.ignoresSafeArea())       // 右栏自己的底色漫 safe area
```

**关键**：每页 `.ignoresSafeArea()` 的 scope 是该页的 UIHostingController，不会漏到其他页。

---

## §3 关键 API 确认

### 3.1 UIHostingController（SwiftUI framework）

- `init(rootView: Content)` — 标准初始化
- `addChild(_: UIViewController)` — 作为 child VC 添加（继承自 UIViewController）
- `safeAreaRegions: SafeAreaRegions`（default `.all`）— "Disabling a safe area region omits it from the SwiftUI layout system altogether. **An example of when this is appropriate to use is when hosting content that you know should never be affected by the safe area, such as a custom scrollable container.**"（Apple doc）
  - **我们不需要禁**，保留 `.all` default
  - 每页的 HC 各自享受 window safe area insets（通过 parent VC 的 UIScrollView 继承）
- `rootView: Content`（mutable）— updateUIViewController 里替换 rootView 让 SwiftUI 内容随 state 更新

### 3.2 UIScrollView 配置

| 属性 | 值 | 作用 |
|---|---|---|
| `isPagingEnabled` | `true` | 开启 paging |
| `bouncesHorizontally` | `false`（iOS 17.4+） | **彻底禁水平 bounce**（比 SwiftUI 的 `.scrollBounceBehavior` 硬） |
| `bouncesVertically` | `true`（默认） | 不影响（PagingVC 只水平 scroll） |
| `contentInsetAdjustmentBehavior` | `.never` | **防止自动 adjust**（Apple doc：horizontal scroll 在 nonzero safe area insets 下会 auto adjust，我们要自己控制） |
| `showsHorizontalScrollIndicator` | `false` | 藏指示器 |
| `decelerationRate` | `.fast` | paging 时 snap 更快 |
| `isScrollEnabled` | from SwiftUI binding | 贴纸编辑时锁 |
| `delegate` | `PagingViewController` | 实现 `scrollViewDidEndDecelerating` 回报 page index |

### 3.3 Child VC lifecycle

标准 pattern（Apple doc）：

```
addChild(hc)
scrollView.addSubview(hc.view)
hc.didMove(toParent: self)
```

`didMove(toParent:)` 必须调用，否则 child VC 的 lifecycle 回调（`viewWillAppear` 等）不触发。

### 3.4 SwiftUI `.ignoresSafeArea(_:edges:)`

"Expands the safe area of a view." — 在每页 UIHostingController scope 内，该页 view 扩展到 HC 的 view bounds（我们会让 HC view 占满 UIScrollView 一页 = window 一屏宽 × full 高含 safe area）。

**关键约束**：`.ignoresSafeArea` 的 extension 是**UIHostingController 内部**的 safe area extension，**不跨 HC 边界**。所以每页的 wallpaper extension 被限制在该页 HC 的 view bounds 内，翻页时该 view 被 UIScrollView translate，extension 跟着走。

---

## §4 wallpaper 在 chat page 内部的行为

### 4.1 视觉

- Chat page 居中（`scrollView.contentOffset.x = pageW`）：
  - chat page 的 view frame = `(pageW, 0, pageW, screenH)` in scrollView content coord
  - `.contentOffset.x = pageW` → chat page 视觉位置 = `(0, 0, pageW, screenH)` in viewport
  - wallpaper 漫整个 chat page view bounds（含 top/bottom safe area）
  - **完美填满屏幕，不漏，不残影**
- 翻到 list page（`contentOffset.x = 0`）：
  - chat page 视觉位置 = `(pageW, 0, pageW, screenH)` — 整个 chat page 推到屏幕右边外
  - wallpaper 跟着 chat page 物理位置到屏外
  - **不漏到 list page 的 safe area**（因为 wallpaper 是 chat page UIView 的 subview，不在 list page HC scope 内）
- 翻到 dashboard page（`contentOffset.x = 2·pageW`）：
  - 对称，wallpaper 跟 chat page 到屏幕左外

### 4.2 为什么这次 wallpaper 能跟走（Phase 2 v1 跟不走）

| 对比 | Phase 2 v1 | 路线 C |
|---|---|---|
| wallpaper 挂哪 | body.background（**root HC scope**） | chat page HC（**per-page HC scope**）|
| wallpaper 怎么"跟走" | SwiftUI `.offset`（visual transform） | UIScrollView 改子 UIView 的物理位置 |
| ignoresSafeArea extension | root HC 渲染，不跟 `.offset` | **chat page HC 自己渲染，跟 HC.view 物理位置走** |
| 跨页泄漏 | 是（extension 是 window-level）| 否（extension 限在 chat page HC bounds）|

---

## §5 SwiftUI ↔ UIKit 状态同步细节

### 5.1 environment / modelContext 透传

`UIHostingController(rootView:)` 的 rootView **不继承** parent SwiftUI 的 environment。

**方案**：`PagingContainerView` 在 `makeUIViewController` 和 `updateUIViewController` 时把 environment 值（`ModelContainer`、`ProfileManager`、`StickerVM` 等）作为参数传给各 page view，page view 内部用 `.environment(...)` / `.environmentObject(...)` 注入。

具体：

```swift
struct PagingContainerView: UIViewControllerRepresentable {
    @Binding var currentPage: Int
    let disableScroll: Bool
    let modelContainer: ModelContainer
    let manager: ProfileManager
    let stickerVM: StickerVM
    // ... 其他需要透传的环境

    func makeUIViewController(context: Context) -> PagingViewController {
        let listPage = iOSListPage(...).modelContainer(modelContainer).environmentObject(manager)
        let chatPage = iOSChatPage(...).modelContainer(modelContainer).environmentObject(manager)
        // ...
        return PagingViewController(
            pages: [AnyView(listPage), AnyView(chatPage), AnyView(dashPage)],
            onPageChanged: { currentPage = $0 }
        )
    }

    func updateUIViewController(_ vc: PagingViewController, context: Context) {
        vc.setScrollEnabled(!disableScroll)
        if vc.currentPage != currentPage {
            vc.scrollToPage(currentPage, animated: true)
        }
        // 重建 pages 让 SwiftUI 状态变化 propagate（rootView 替换）
        let listPage = iOSListPage(...).modelContainer(modelContainer).environmentObject(manager)
        vc.updatePages([AnyView(listPage), ...])
    }
}
```

**细节点**：
- `updateUIViewController` 会在每次 SwiftUI body 重算时被调用。替换 rootView 会触发 SwiftUI diff → 页内容更新。
- 频繁替换 `rootView` 性能？SwiftUI 内部有 diff，实际重算只重算变化的部分。可接受。
- **备选**：不用 AnyView 传，而是 PagingViewController 暴露 `listHC: UIHostingController<iOSListPageView>`、`chatHC: UIHostingController<iOSChatPageView>` 三个具体类型的 HC，updateUIViewController 里 `vc.chatHC.rootView = newChatPage`。更类型安全，但需要固定每页类型。

### 5.2 程序化切页

SwiftUI 里当前用 `scrollPosition.scrollTo(id: 1)` 切到聊天页（e.g. 列表选对话触发）。

新方式：`@Binding var currentPage: Int` 改为目标页，`updateUIViewController` 里调用 `vc.scrollToPage(1, animated: true)`。

```swift
func scrollToPage(_ page: Int, animated: Bool) {
    let x = CGFloat(page) * scrollView.bounds.width
    scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
}
```

程序化切页完成 → `scrollViewDidEndScrollingAnimation` → 确认 currentPage binding 同步（正常不需要再写回 binding，因为本来就是 binding 从 SwiftUI → UIKit）。

### 5.3 当前页回报（手动翻页）

```swift
func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
    guard page != currentPage else { return }
    currentPage = page
    onPageChanged?(page)
}
```

SwiftUI binding 更新 → SwiftUI body 重算 → `.sensoryFeedback(.impact, trigger: currentPage)` 在 SwiftUI 层触发。

### 5.4 scrollDisabled 同步

```swift
func setScrollEnabled(_ enabled: Bool) {
    scrollView.isScrollEnabled = enabled
}
```

贴纸编辑时 SwiftUI `stickerVM.isEditingStickers == true` → `disableScroll = true` → `updateUIViewController` → `setScrollEnabled(false)`。

---

## §6 Edge cases / 风险

### 6.1 页面 lifecycle：三页同时 mount vs lazy

**方案**：三页同时创建 + 始终 mount（和 Phase 2 一样）。

内存开销：
- iOSListPage：对话列表（20 万+ MessageNode 的 app，列表页本身不全量 fetch，只 fetch 当前 conversations 列表 + 贴纸）
- iOSChatPage：CardFlowView（当前对话的 MessageNode，分支冒泡后的 visible path）
- iOSDashboardPage：角色卡库 / 知识 / 设置等，大部分懒加载

三页同时 mount 内存尚可。

**如果以后内存紧张**：UIScrollView 改用 `UICollectionView` + cell reuse，每 cell 是 UIHostingController cache pool。太复杂，先不做。

### 6.2 键盘响应

每页的 UIHostingController 自己响应键盘。chat page 的 `ChatInputBar` 用 SwiftUI 的 `.keyboardLayoutGuide` / 自动 keyboard avoidance。

**但 UIScrollView 本身有 keyboard adjust 行为**（通过 `scrollView.keyboardDismissMode` + 自动 content inset）。我们设 `contentInsetAdjustmentBehavior = .never` 已经禁掉 auto adjust。

**风险**：键盘弹出时，chat page 的 hosting controller 自己 adjust，但 scroll container 的 bounds 不变 → chat page view 的 bounds 不变 → CardFlowView 内部 SwiftUI 的 keyboardLayoutGuide 应该正常工作。**需要实测**。

粟粟之前在 B7 已经 fix 过很多键盘问题（phase 1/2），这些 fix 在 chat page 内部，应该继续有效。

### 6.3 sticker 手势系统（memory 里说过有 gesture 陷阱）

sticker 的 UIViewRepresentable 手势 / zIndex 都在 chat page 内部。**路线 C 不改 chat page 内部结构**，只改外层容器。sticker 手势继续工作。

scrollDisabled 在贴纸编辑时锁 UIScrollView（本方案）和锁 chat page 内部的 CardFlowView ScrollView（`setStickerEditScrollLock` / `setAllScrollViewsEnabled` 保留）。这两锁分开：
- 外层 PagingVC 的 UIScrollView 锁水平翻页
- 内层 CardFlowView 的 SwiftUI ScrollView 锁垂直滚动

### 6.4 屏幕旋转 / SceneKit

`viewDidLayoutSubviews` 重新算 contentSize + 每页 frame。旋转时自动触发。

### 6.5 sensoryFeedback 触发时机

SwiftUI `.sensoryFeedback(.impact, trigger: iOSPage)` 在 iOSPage 变化时触发。`currentPage` binding 从 UIKit 写回后，SwiftUI body 重算 → `.sensoryFeedback` 检测 trigger 变化 → 触发震动。

**但 SwiftUI `.sensoryFeedback` 在 `PagingContainerView` 外的 body 层，currentPage binding 是在 body level，没问题。**

### 6.6 SwiftUI state 频繁更新 → rootView 频繁替换 → hosting controller 重渲染

如果 state 变化频繁（比如 chat page 内有动画、ChatInputBar 的每字输入）：

- `updateUIViewController` 每次 SwiftUI body 重算都调用
- 如果每次都把 rootView 替换成新 copy，三个 HC 都 "重渲染"

**SwiftUI 内部 diff** 应该能 cache 不变的部分，实际重算量有限。**需要 profile 实测**，如果有性能问题再优化（比如只替换变化的 page 的 rootView）。

### 6.7 initial page

默认开启从 `currentPage = 1`（chat page）进。要确保 `viewDidLayoutSubviews` 第一次设 contentOffset 到 `pageW`，并在 `updateUIViewController` 不要 override。

```swift
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if !hasLaidOutInitialPage {
        scrollView.setContentOffset(CGPoint(x: CGFloat(initialPage) * scrollView.bounds.width, y: 0), animated: false)
        hasLaidOutInitialPage = true
    }
    // 继续 layout 每页 frame + contentSize
}
```

### 6.8 pageIndicator（底部的点）

Phase 2 v1 有 `iOSLayout.ZStack(alignment: .top) { ScrollView; if !isKeyboardVisible { pageIndicator } }`。pageIndicator 是 3 个点示意当前页。

路线 C 下 pageIndicator 怎么摆？
- 选项 A：还挂在 ContentView body `.overlay(alignment: .bottom)` 层（在 PagingContainerView 之上），用 `currentPage` binding 显示
- 选项 B：放每页内部（每页画自己高亮的 indicator）—— 不自然

**选 A**：pageIndicator 是 UI-level 的 overlay，不是翻页容器的一部分。

### 6.9 每页的 ScrollView 和外层 UIScrollView 的手势冲突

chat page 的 CardFlowView 是 SwiftUI ScrollView（垂直滚动）。外层 PagingVC UIScrollView 是水平 paging。

两者方向正交，手势**通常不冲突**（UIScrollView 自动识别方向）。

**但 bounce 时可能有边界 case**：chat page ScrollView 到顶 / 底时继续拉会 bounce，这时外层 UIScrollView 也可能 intercept 水平手势。`isDirectionalLockEnabled = true` 在外层和内层都设可以避免对角线滑动。

### 6.10 `Theme.mainBg` / `Theme.sidebarBg` 怎么分配

当前：`Theme.sidebarBg` 在 body.background 做"全屏底色"。

路线 C 下：
- 不再有 body.background 大底
- 每页自己 `.background(pageColor.ignoresSafeArea())`
  - list page 用 `Theme.sidebarBg` 或更合适的 listBg
  - chat page 用 wallpaper（fill = `Theme.mainBg`）
  - dashboard page 用 dashboardBg（可能 `Theme.sidebarBg` 或别的）
- UIScrollView 自己的背景色？设 `.clear` 或 `.black`（默认）。因为每页 view 铺满 scroll 的 page frame，scroll 背景色只在内容外可见（理论上看不到，除非 bounces = true 漏出）。设 `.clear` 稳妥。

---

## §7 Files 改动预估

### 新增（2 个）

- `MemoryPalace/Views/Paging/PagingContainerView.swift` — UIViewControllerRepresentable
- `MemoryPalace/Views/Paging/PagingViewController.swift` — UIKit UIViewController + UIScrollView

（目录 `Views/Paging/` 为新增，整个模块隔离）

### 修改（`ContentView.swift`）

- 删：
  - `@State var scrollPosition` / `scrollOffsetX` / `pageWidth`
  - body `.background { ZStack { sidebarBg; wallpaper.offset }.ignoresSafeArea() }`
  - body `.overlay(alignment: .top) { iOSChatTopBar.offset }`
  - `iOSLayout` 里的 `ScrollView(.horizontal) + HStack + scrollTargetLayout + scrollPosition + scrollBounceBehavior + onScrollGeometryChange`
  - `setStickerEditScrollLock` 里**外层** ScrollView 的锁（内层垂直 ScrollView 锁保留）
- 改：
  - `iOSLayout` 的 ScrollView 换成 `PagingContainerView(...)`
  - `iOSChatPage` 内部加 `.background { ChatWallpaperBackdrop(...).ignoresSafeArea() }` + `.overlay(alignment: .top) { iOSChatTopBar }`
  - `iOSListPage` 加 `.background(Theme.sidebarBg.ignoresSafeArea())`
  - `iOSDashboardPage` 加 `.background(dashboardBg.ignoresSafeArea())`
  - `iOSPage` 从 computed (from scrollPosition) 改为 `@State var iOSPage = 1`（通过 PagingContainerView 的 binding）
  - pageIndicator 从 `iOSLayout` 里挪到 body `.overlay(alignment: .bottom)`

### 不改

- `ChatWallpaperBackdrop.swift`
- `CardFlowView.swift`（chat page 内部，不动）
- `SidebarView.swift`（list page 内部，不动）
- dashboard 各页内部
- macOS 分支完全不动
- `Theme.swift` / 主题编辑 / 贴纸模块

---

## §8 验收 criteria

核心（翻页 + safe area 正确）：

- [ ] 翻页：左右滑动三页，**无水平 bounce**，paging snap 正常
- [ ] Chat page 居中：wallpaper 漫满屏（status bar + dynamic island 周围 + home indicator）
- [ ] 翻到 list page / dashboard page：**wallpaper 完全消失**，所有区域（含 safe area）看到的是该页自己的背景色
- [ ] Dynamic Island 周围两侧没有 wallpaper 残影
- [ ] Home indicator 周围没有 wallpaper 残影

交互（翻页流畅度）：

- [ ] 程序化切页（list 选对话 → chat page）动画流畅
- [ ] 触感反馈（切页时震动）OK
- [ ] 贴纸编辑时水平翻页锁死
- [ ] 聊天页输入法打开时气泡位置正常（CardFlowView / ChatInputBar）
- [ ] chat page 内部贴纸手势（点击、拖动、编辑）正常
- [ ] chat page 内部 CardFlowView 垂直滚动正常

环境（SwiftUI state 透传）：

- [ ] SwiftData ModelContainer 在每页生效（能查 conversation / MessageNode）
- [ ] ProfileManager 切楼层在每页生效
- [ ] StickerVM 状态在 chat page 生效

其他：

- [ ] iOSChatTopBar blur + gradient + nav buttons 在 chat page top 正常（盖 status bar 区）
- [ ] pageIndicator 在 body bottom overlay 反映当前页
- [ ] 键盘打开时不会 hijack 水平翻页手势

性能：

- [ ] 首次启动加载时间与 Phase 2 v1 相当
- [ ] 翻页动画无卡顿

---

## §9 选型说明 / Push back 考虑

### Q1：UIScrollView 手动 paging vs UIPageViewController？

选 `UIScrollView` 手动。理由：

- 3 页静态，**不需要** `UIPageViewController` 的 data source + 动态 VC load/unload
- `UIPageViewController` 的 `setViewControllers` 是**异步**，程序化切页有 lag
- `UIScrollView` 的 `isPagingEnabled` / `bouncesHorizontally` / `isScrollEnabled` 都是**直接属性**，直接 toggle 生效
- UIPageViewController 的 bounce 控制要遍历子 UIScrollView + hack，不优雅
- `UIScrollView` + 3 subview 代码更短、更可读

### Q2：回 TabView 重试 wallpaper 放 chat page 内部？

TabView 的每页确实也是独立 UIHostingController（SwiftUI 内部实现）。理论上 wallpaper 放 `iOSChatPage.background.ignoresSafeArea()` 应该和路线 C 一样 work。

**不选**的原因：

1. **翻页穿模**：TabView `.page` 样式基于 UIPageViewController，翻页动画让**相邻页可见一部分**（这是 paging scroll 的本质，不是 bug）。粟粟明确 reject 过这种视觉"色乱"。
2. **Bounce 不好禁**：要遍历 TabView 内部的 UIPageViewController → UIScrollView hack 改 `bounces = false`，已经试过不稳定（设了又被 TabView 内部重置）。
3. **程序化切页 lag**：TabView `@State` binding 切页 → UIPageViewController setViewControllers 异步，有 ~100ms 延迟
4. **架构失控**：TabView 内部实现 Apple 控制，之后要做更定制化的翻页（比如 parallax、动态壁纸解耦）更难

→ 走 UIScrollView 路。

### Q3：SwiftUI ScrollView 再给一次机会？

**不行**。SwiftUI ScrollView 是**单一** UIHostingController，三页共享 safe area context。这是 `.ignoresSafeArea + .offset` 不兼容的根因。没有 per-page HC 的天然隔离。

### Q4：每页全 wallpaper（route E）复活？

粟粟明确要"一页就是一页 + wallpaper 漫满屏 + future 动态壁纸独立"，E 的妥协不满足。

---

## §10 粟粟需要理解的几点

### 10.1 为什么 Phase 1 的清理工作不白做

Phase 1 删除的 `disableTabViewBounce` / `disableBounceInSubviews` / `updateKeyboardBehavior` / `findCollectionView` 是**针对 TabView 内部 UIScrollView 的 hack**，是"打补丁"。

路线 C 是**主动选择用 UIKit UIScrollView**，直接用它的官方属性（`bouncesHorizontally`、`isScrollEnabled`），**不是打补丁**。结构对称、直接控制。

### 10.2 为什么这次 wallpaper 在 chat page 内部会成功

- **关键是每页独立 UIHostingController**：`.ignoresSafeArea` 的 extension 限在该 HC scope
- HC 的 view 是 UIScrollView.subview，UIScrollView 改 contentOffset 时 subview 的物理位置改变，**extension 作为 HC 内部 subview 跟着走**
- Phase 2 v1 是**单 HC + SwiftUI `.offset`**，extension 不跟 visual transform → 残影

### 10.3 动态壁纸的 future-proof 具体落地

以后做动态壁纸（比如 Lottie 动画 / Metal shader / 视频背景）：

- 新建一个 `DynamicChatWallpaperView: UIViewRepresentable` / SwiftUI View
- 在 `iOSChatPage.background` 里替换 `ChatWallpaperBackdrop` 为 `DynamicChatWallpaperView`
- **不动翻页容器代码**
- 动画由该组件自己管（`CADisplayLink` / `MTKView.draw` 等）

### 10.4 实现顺序思路（给后面的 Plan 参考）

1. **先搭空壳**：PagingContainerView + PagingViewController 跑通 3 个 empty page + 翻页
2. **接真 page**：把 iOSListPage / iOSChatPage / iOSDashboardPage 内容接进去，验证 SwiftUI state 透传 / 键盘 / scrollDisabled
3. **挪 wallpaper + topBar 进 chat page**：验证 wallpaper 每页独立
4. **删老代码**：清 Phase 2 v1 的 offset trick state
5. **edge cases**：旋转 / 键盘 / 贴纸手势 / 程序化切页 / 性能

每步 build 验证，checklist 勾一个。

### 10.5 有哪些风险还没完全 resolve（等 implement 时实测）

- **SwiftUI `.ignoresSafeArea` 在 UIHostingController scope 内的具体行为**：我的 hypothesis 是 "extension 限在 HC bounds，跟 HC view 的物理位置走"。这是基于 Apple doc 的间接推断，**没有直接 Apple 文档确认**。如果实测发现 extension 还是跑到 window level → 需要 fallback（e.g. 给每页加 explicit frame 包含 safe area）。
- **SwiftUI state 频繁更新 → rootView 频繁替换的性能开销**：需要 profile。
- **键盘弹出时 UIScrollView 的 keyboard adjust 行为**：`contentInsetAdjustmentBehavior = .never` 应该足够，但 UIKit 的 KB avoidance 有时还是会 kick in。实测确认。

---

（Plan 文档见 `plan-uikit-paging-container-2026-04-20.md`，待本文档粟粟批注确认后再写）

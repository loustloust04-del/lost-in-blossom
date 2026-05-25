# Plan: iOS 翻页容器 UIKit 重构 — 路线 C

日期：2026-04-20
分支：`codex/theme-kelivo-settings`
前置 commit：`f7af017`（Phase 2 v1）
Research：`research-uikit-paging-container-2026-04-20.md`
状态：**Draft，等粟粟批注**

---

## 1. 实施顺序（3 Phase，每 phase 独立 commit，小步验证）

### Phase 1: 空壳 + 核心假设验证 ★ 关键

**目标**：跑通 UIScrollView paging + 3 个独立 UIHostingController + 中间页挂测试 wallpaper，**验证 research §3.4 / §10.5 的核心假设**——wallpaper `.ignoresSafeArea()` 的 extension 限在 chat page HC 内、跟 HC.view 物理位置走。

**如果 Phase 1 失败（wallpaper 仍漏），停止，切到 §5 Fallback**。

- [ ] **P1.1** 新增目录 `MemoryPalace/Views/Paging/`
- [ ] **P1.2** 写 `PagingViewController.swift`（UIKit）
  - UIViewController subclass
  - `view` = UIScrollView，配置：`isPagingEnabled = true` / `bouncesHorizontally = false`（iOS 17.4+）/ `contentInsetAdjustmentBehavior = .never` / `decelerationRate = .fast` / `showsHorizontalScrollIndicator = false` / `delegate = self`
  - 三个 child `UIHostingController<AnyView>`，`addChild + addSubview + didMove(toParent:)`
  - `viewDidLayoutSubviews`：设 `contentSize = (3·pageW, pageH)` + 每页 frame + 初始 `contentOffset = initialPage·pageW`（只第一次）
  - `scrollViewDidEndDecelerating` → 回调 `onPageChanged(page)`
  - 公开方法：`scrollToPage(_:animated:)` / `setScrollEnabled(_:)` / `updatePages(_:)`
- [ ] **P1.3** 写 `PagingContainerView.swift`（`UIViewControllerRepresentable`）
  - 参数：`listPage/chatPage/dashPage: AnyView`、`currentPage: Binding<Int>`、`disableScroll: Bool`、`initialPage: Int`
  - `makeUIViewController`：构造 `PagingViewController`，设 `onPageChanged` 回写 `currentPage`
  - `updateUIViewController`：`updatePages` + `setScrollEnabled(!disableScroll)` + 如果 `currentPage` 变了则 `scrollToPage(..., animated: true)`
- [ ] **P1.4** ContentView.swift 临时把 `iOSLayout` 内容替换成 `PagingContainerView(测试版)`
  - 用 `@State var debugUseNewPaging = true`（方便一键切回 Phase 2 v1 对比）或直接替换，任选
- [ ] **P1.5** 测试 page 内容：
  - Page 0 = `Color.blue.ignoresSafeArea()` + overlay `Text("List")`
  - Page 1 = `Color.clear.background { ChatWallpaperBackdrop(fill: .orange, imageURL: 当前壁纸, scheme: .light, backgroundStyle: .default).ignoresSafeArea() }` + overlay `Text("Chat")`
  - Page 2 = `Color.green.ignoresSafeArea()` + overlay `Text("Dashboard")`
  - **关键：wallpaper 一定要用粟粟当前用的那张图**（有图案、对比强），空白壁纸看不出漏没漏
- [ ] **P1.6** build + iPhone 17 Air 安装
- [ ] **P1.7** 核心验证清单（**逐项打勾**）：
  - [ ] 水平翻页 OK（左右滑，snap paging）
  - [ ] 水平 **无 bounce**（到两端硬边）
  - [ ] 中间页 wallpaper 漫满屏：status bar 区 + Dynamic Island 两侧 + home indicator 区全是壁纸图案
  - [ ] 翻到左页（蓝）：**整屏蓝色，含 safe area，零 wallpaper 残影**
  - [ ] 翻到右页（绿）：**整屏绿色，含 safe area，零 wallpaper 残影**
  - [ ] 翻页过程中相邻页可见是正常的（paging scroll 本质），**关键看停稳后有无残影**
  - [ ] 竖直方向 safe area respected（Color 的 ignoresSafeArea 生效到位）
- [ ] **P1.8** commit "P1: UIKit paging 容器空壳 + wallpaper 每页独立核心假设验证"

---

### Phase 2: 接真 page + 挪 wallpaper/topBar + Environment 透传

**目标**：把测试 page 换成真 `iOSListPage / iOSChatPage / iOSDashboardPage`，wallpaper 和 topBar 从 body 挪进 chat page，清 Phase 2 v1 的 offset trick。

- [ ] **P2.1** 替换 P1.5 的 3 个测试 page 为真 page
- [ ] **P2.2** `iOSChatPage` 内部加 wallpaper：
  ```swift
  .background {
      ChatWallpaperBackdrop(
          fill: Theme.mainBg,
          imageURL: manager.currentBackgroundImageURL,
          scheme: manager.activeScheme,
          backgroundStyle: manager.currentBackgroundStyle
      )
      .ignoresSafeArea()
  }
  ```
- [ ] **P2.3** `iOSChatPage` 内部加 topBar：
  ```swift
  .overlay(alignment: .top) { iOSChatTopBar }
  ```
- [ ] **P2.4** `iOSListPage` 加 `.background(Theme.sidebarBg.ignoresSafeArea())`
- [ ] **P2.5** `iOSDashboardPage` 加 `.background(dashboardBg.ignoresSafeArea())`（dashboardBg 见 §7 待确认）
- [ ] **P2.6** 清 body 的 Phase 2 v1 遗留：
  - 删 `.background { ZStack { Theme.sidebarBg; ChatWallpaperBackdrop.offset }.ignoresSafeArea() }`
  - 删 `.overlay(alignment: .top) { iOSChatTopBar.offset }`
- [ ] **P2.7** Environment 透传（PagingContainerView 参数里把每 page wrap）：
  ```swift
  chatPage: AnyView(
      iOSChatPage
          .modelContainer(modelContainer)
          .environmentObject(manager)
          .environmentObject(stickerVM)
  )
  ```
  （具体 environment 列表看 ContentView 现有的 modifier chain）
- [ ] **P2.8** `iOSPage` 从 computed（读 scrollPosition）改成 `@State var iOSPage = 1`，通过 `PagingContainerView.currentPage: $iOSPage` binding
- [ ] **P2.9** 程序化切页：原先的 `withAnimation { scrollPosition.scrollTo(id: 1) }` 改成 `withAnimation { iOSPage = 1 }`
- [ ] **P2.10** `disableScroll`：`PagingContainerView(... disableScroll: stickerVM.isEditingStickers ...)`
- [ ] **P2.11** sensoryFeedback 保留：`.sensoryFeedback(.impact(weight: .light), trigger: iOSPage)` 在 body level
- [ ] **P2.12** build + iPhone 17 Air 安装
- [ ] **P2.13** 回归测试清单：
  - [ ] 三页内容正常显示
  - [ ] Chat page 居中时 wallpaper 漫满屏（含 safe area，**和 Phase 1 测试一致**）
  - [ ] 列表页 / 右栏页各自背景色漫 safe area（**零 wallpaper 残影**）
  - [ ] 列表选对话跳聊天页（程序化切页动画流畅）
  - [ ] 贴纸编辑时水平翻页锁死
  - [ ] Chat page 气泡 / 输入法响应正常
  - [ ] Chat page CardFlowView 垂直滚动正常
  - [ ] Chat page 贴纸手势（点击 / 拖动 / 编辑）正常
  - [ ] 切页触感震动 OK
  - [ ] iOSChatTopBar 的 blur + gradient + nav buttons 正常
- [ ] **P2.14** commit "P2: 接真 page + wallpaper/topBar 进 chat page"

---

### Phase 3: 清理旧 state + pageIndicator + edge cases

**目标**：删 Phase 2 v1 残留 state，pageIndicator 挪位置，验证 edge cases。

- [ ] **P3.1** 删 `@State var scrollPosition` / `scrollOffsetX` / `pageWidth`
- [ ] **P3.2** 删 `.onScrollGeometryChange` hook
- [ ] **P3.3** 清 `iOSLayout` 里的 `GeometryReader` / `ScrollView` 壳（如果有残留）
- [ ] **P3.4** pageIndicator 从 `iOSLayout` 内挪到 body `.overlay(alignment: .bottom)`，通过 `iOSPage` 显示当前页
  - 保留 `!isKeyboardVisible` 判断
- [ ] **P3.5** `setStickerEditScrollLock` / `setAllScrollViewsEnabled` 保留（垂直 ScrollView 锁仍需要）
- [ ] **P3.6** Edge case 验证：
  - [ ] 屏幕旋转（如果支持 landscape）→ contentSize + 页 frame 自动更新
  - [ ] 键盘弹出 / 收起：chat page 气泡正常，外层 UIScrollView 不被 keyboard hijack
  - [ ] 贴纸编辑时各种翻页尝试（手指拖 / 程序化）全锁
  - [ ] 性能：SwiftUI state 频繁更新（打字、动画）时 frame rate 稳定
- [ ] **P3.7** commit "P3: 清理 Phase 2 v1 残留 state + pageIndicator 挪位置"
- [ ] **P3.8** `git push` 到 GitHub

---

## 2. 关键代码片段（参考骨架，不是最终实现）

### PagingViewController

```swift
@MainActor
final class PagingViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var hostingControllers: [UIHostingController<AnyView>] = []
    private var currentPage: Int
    private var hasLaidOutInitialPage = false
    var onPageChanged: ((Int) -> Void)?

    init(pages: [AnyView], initialPage: Int) {
        self.currentPage = initialPage
        super.init(nibName: nil, bundle: nil)
        for page in pages {
            hostingControllers.append(UIHostingController(rootView: page))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.isPagingEnabled = true
        if #available(iOS 17.4, *) { scrollView.bouncesHorizontally = false }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        view.addSubview(scrollView)
        for hc in hostingControllers {
            addChild(hc)
            scrollView.addSubview(hc.view)
            hc.didMove(toParent: self)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        let w = view.bounds.width
        let h = view.bounds.height
        for (i, hc) in hostingControllers.enumerated() {
            hc.view.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
        scrollView.contentSize = CGSize(width: w * CGFloat(hostingControllers.count), height: h)
        if !hasLaidOutInitialPage, w > 0 {
            scrollView.contentOffset = CGPoint(x: CGFloat(currentPage) * w, y: 0)
            hasLaidOutInitialPage = true
        }
    }

    func scrollToPage(_ page: Int, animated: Bool) {
        guard isViewLoaded, scrollView.bounds.width > 0 else {
            currentPage = page
            return
        }
        let x = CGFloat(page) * scrollView.bounds.width
        scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
        currentPage = page
    }

    func setScrollEnabled(_ enabled: Bool) { scrollView.isScrollEnabled = enabled }
    var programmaticCurrentPage: Int { currentPage }

    func updatePages(_ pages: [AnyView]) {
        for (i, page) in pages.enumerated() where i < hostingControllers.count {
            hostingControllers[i].rootView = page
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        guard page != currentPage else { return }
        currentPage = page
        onPageChanged?(page)
    }
}
```

### PagingContainerView

```swift
struct PagingContainerView: UIViewControllerRepresentable {
    let listPage: AnyView
    let chatPage: AnyView
    let dashPage: AnyView
    @Binding var currentPage: Int
    let disableScroll: Bool
    let initialPage: Int

    func makeUIViewController(context: Context) -> PagingViewController {
        let vc = PagingViewController(
            pages: [listPage, chatPage, dashPage],
            initialPage: initialPage
        )
        vc.onPageChanged = { newPage in
            DispatchQueue.main.async { currentPage = newPage }
        }
        return vc
    }

    func updateUIViewController(_ vc: PagingViewController, context: Context) {
        vc.updatePages([listPage, chatPage, dashPage])
        vc.setScrollEnabled(!disableScroll)
        if vc.programmaticCurrentPage != currentPage {
            vc.scrollToPage(currentPage, animated: true)
        }
    }
}
```

### ContentView.swift iOS 分支最终形态

```swift
@State private var iOSPage: Int = 1

// body
#if os(iOS)
PagingContainerView(
    listPage: AnyView(iOSListPage
        .modelContainer(modelContainer)
        .environmentObject(manager)
        .environmentObject(stickerVM)
    ),
    chatPage: AnyView(iOSChatPage
        .modelContainer(modelContainer)
        .environmentObject(manager)
        .environmentObject(stickerVM)
    ),
    dashPage: AnyView(iOSDashboardPage
        .modelContainer(modelContainer)
        .environmentObject(manager)
        .environmentObject(stickerVM)
    ),
    currentPage: $iOSPage,
    disableScroll: stickerVM.isEditingStickers,
    initialPage: 1
)
.ignoresSafeArea()          // 让 PagingContainerView 占满屏，含 safe area
.sensoryFeedback(.impact(weight: .light), trigger: iOSPage)
.overlay(alignment: .bottom) {
    if !isKeyboardVisible {
        pageIndicator(page: iOSPage)
    }
}
#endif
```

---

## 3. 不做的事

- 不改 macOS 分支
- 不改 `ChatWallpaperBackdrop` / `iOSChatTopBar` / `CardFlowView` / `SidebarView` / 贴纸模块内部
- 不做 lazy load（三页始终 mount）
- 不做 landscape / 旋转适配（iOSLayout 主场景是 portrait）
- 不改主题 / ThemeEditor / ThemeAssetStore
- 不改 macOS debug flag（DebugRenderSettings 等）

---

## 4. 回滚策略

每 phase 独立 commit，失败可单独 revert：

| Phase | 失败回退到 |
|---|---|
| Phase 1 失败（核心假设破灭） | `git reset --hard f7af017` 回 Phase 2 v1，切到 §5 Fallback |
| Phase 2 失败（接真 page 出问题） | `git reset --hard <P1.8 commit>` 保留 Phase 1 空壳 |
| Phase 3 失败（清理打破别的） | `git reset --hard <P2.14 commit>` 保留 Phase 2 全功能 |

---

## 5. Fallback（如果 Phase 1 核心假设破灭）

如果 P1.7 验证发现 wallpaper **仍漏到相邻页 safe area** —— 说明 UIHostingController scope 内的 `.ignoresSafeArea` extension 还是跑到 window level：

**Plan B**：不用 `.ignoresSafeArea`，用 explicit frame + negative offset 显式覆盖 safe area：

```swift
iOSChatPage
    .background {
        GeometryReader { proxy in
            let fullH = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ChatWallpaperBackdrop(...)
                .frame(width: proxy.size.width, height: fullH)
                .offset(y: -proxy.safeAreaInsets.top)
        }
    }
```

让 wallpaper 的 SwiftUI view 用 explicit frame 撑满 page view（含 safe area 区），**完全绕过 `.ignoresSafeArea` 机制**。这样 wallpaper 的 UIView 物理尺寸 = page 全高，UIScrollView translate page view 时整体一起走。

**Plan B 只在 Phase 1 失败时 activate**，不提前做。

---

## 6. Files 改动清单

**新增（Phase 1）**：
- `MemoryPalace/Views/Paging/PagingViewController.swift`
- `MemoryPalace/Views/Paging/PagingContainerView.swift`

**修改（Phase 2 + 3）**：
- `MemoryPalace/Views/ContentView.swift`
  - iOSLayout 换 PagingContainerView
  - 清 body.background / body.overlay 的 offset trick
  - 清 scrollPosition / scrollOffsetX / pageWidth state
  - 清 onScrollGeometryChange
  - iOSChatPage 加 wallpaper + topBar
  - iOSListPage / iOSDashboardPage 加自己的 background
  - pageIndicator 挪 body overlay

**不改**：
- `ChatWallpaperBackdrop.swift`
- `CardFlowView.swift`
- `SidebarView.swift`
- 贴纸模块
- macOS 分支
- Theme 模块

---

## 7. 等粟粟批注确认

- [ ] **dashboardBg 用什么色**？默认 `Theme.sidebarBg`（和列表页一致），还是 `Theme.mainBg`（暖奶白），还是新定义一个？
- [ ] **Environment 透传**：AnyView 方案（简单，SwiftUI diff 负责重算，可能有性能开销）vs 具体类型 HC（`UIHostingController<iOSChatPageView>`，类型安全，代码量多）。**默认 AnyView**，profile 发现问题再换。
- [ ] **initialPage = 1**（chat page）对吧？和 Phase 2 v1 一致。
- [ ] **pageIndicator 位置**：body `.overlay(alignment: .bottom)` + `!isKeyboardVisible` 判断，没问题吧？
- [ ] **Phase 1 测试 wallpaper 是用粟粟当前那张图**（有图案、对比强），还是另找一张？我倾向用当前那张 —— 和 Phase 2 v1 对比效果最直接。

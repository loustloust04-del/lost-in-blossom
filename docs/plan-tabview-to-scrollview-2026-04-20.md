# Plan: iOS 聊天页翻页不穿模 — TabView → ScrollView(.horizontal) paging

日期：2026-04-20
分支：`codex/theme-kelivo-settings`
状态：**Draft，等粟粟批注**

研究见 `research-tabview-to-scrollview-2026-04-20.md`。

---

## 1. 实施顺序（小步迭代，每步 build 验证）

### Phase 1: ScrollView 骨架替换 TabView
只做骨架替换，wallpaper 和 top bar 先**维持现状挂在 body**（不做 offset 同步）。先确认 ScrollView + paging 能正常跑三页、触感/键盘/程序切页都 OK，然后再上 offset 同步。

目标：跑起来看着像 TabView 一样。

- [ ] **P1.1** 加 `@State var scrollPosition: ScrollPosition = ScrollPosition(id: 1)` 替换 `@State var iOSPage = 1`
- [ ] **P1.2** `iOSLayout` 的 TabView 换成 ScrollView(.horizontal) + HStack(3 页) + paging 一套
  - 保留 `.ignoresSafeArea(.container, edges: [.top, .bottom])`
  - 保留 `.scrollDisabled(stickerVM.isEditingStickers)`
  - 加 `.scrollBounceBehavior(.basedOnSize)` 替代 `disableTabViewBounce`
  - 加 `.scrollIndicators(.hidden)`
- [ ] **P1.3** 加 computed `iOSPage: Int { scrollPosition.viewID(type: Int.self) ?? 1 }`（其他地方继续用 iOSPage）
- [ ] **P1.4** 程序化切页：`withAnimation { scrollPosition.scrollTo(id: 1) }` 替换 `withAnimation { iOSPage = 1 }`（只有 onChange selectedConversation 那处）
- [ ] **P1.5** 删 `disableTabViewBounce` / `disableBounceInSubviews` / `updateKeyboardBehavior` / `findCollectionView`（4 个函数）
- [ ] **P1.6** `setStickerEditScrollLock` / `setAllScrollViewsEnabled` 保留（竖直 ScrollView 锁死仍需要）
- [ ] **P1.7** build & install，回归测试：
  - 左右翻页正常（手指拖 + 松手 snap）
  - 边界页不 bounce
  - 触感反馈 OK（`sensoryFeedback(trigger: iOSPage)` 需要 iOSPage 变化能触发）
  - 键盘打开时气泡位置正常
  - 贴纸编辑时不能翻页
  - 列表选对话跳到聊天页

### Phase 2: 实时 offset 跟手同步
Phase 1 稳定后，开 offset 同步。

- [ ] **P2.1** 加 `@State var scrollOffsetX: CGFloat = 0`
- [ ] **P2.2** 加 `@State var pageWidth: CGFloat = 0`，在 GeometryReader 里设
- [ ] **P2.3** ScrollView 加 `.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in scrollOffsetX = x }`
- [ ] **P2.4** body wallpaper `.background` 去掉 `if iOSPage == 1` 条件 + 淡入淡出 animation，改永远挂
- [ ] **P2.5** body top bar `.overlay` 去掉 `if iOSPage == 1` 条件，改永远挂
- [ ] **P2.6** wallpaper 和 top bar 加 `.offset(x: pageWidth - scrollOffsetX)`（聊天页 baseline = 1*pageWidth，offset = baseline - currentScroll）
- [ ] **P2.7** build & install，回归测试：
  - 翻页时 wallpaper 跟着聊天页水平滑走 ✓
  - top bar 跟 wallpaper 同步滑走 ✓
  - 滑到列表页/右栏时 wallpaper 彻底消失（不穿模）✓
  - wallpaper 仍漫 safe area（status bar + home indicator）✓
  - 控件位置正常（top bar nav 按钮、ChatInputBar chip 都在 safe area 内）✓

### Phase 3: 收尾
- [ ] **P3.1** 如果 P2 翻页中 wallpaper/top bar 边缘过硬，加 opacity 渐透：`.opacity(max(0, 1 - abs(pageWidth - scrollOffsetX) / pageWidth))`
- [ ] **P3.2** `git commit` + `git push`

---

## 2. 关键代码片段参考

### iOSLayout 新骨架（Phase 1 目标）

```swift
private var iOSLayout: some View {
    GeometryReader { proxy in
        ZStack(alignment: .top) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    iOSListPage
                        .containerRelativeFrame(.horizontal)
                        .id(0)
                    iOSChatPage
                        .containerRelativeFrame(.horizontal)
                        .id(1)
                    iOSDashboardPage
                        .containerRelativeFrame(.horizontal)
                        .id(2)
                }
                .scrollTargetLayout()
            }
            .scrollPosition($scrollPosition)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(stickerVM.isEditingStickers)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.x
            } action: { _, newX in
                scrollOffsetX = newX
                pageWidth = proxy.size.width
            }

            // Page indicator 保留原样
            if !isKeyboardVisible { ... }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sensoryFeedback(.impact(weight: .light), trigger: iOSPage)
    .onChange(of: iOSPage) { _, _ in
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    // 其他 onChange / onReceive 保留不动
}
```

### wallpaper + top bar 跟手（Phase 2 目标）

```swift
.background {
    ZStack {
        Theme.sidebarBg
        ChatWallpaperBackdrop(...)
            .offset(x: pageWidth - scrollOffsetX)
    }
    .ignoresSafeArea()
}
.overlay(alignment: .top) {
    iOSChatTopBar
        .offset(x: pageWidth - scrollOffsetX)
}
```

---

## 3. 不做的事

- 不改 macOS 代码
- 不改 CardFlowView / SidebarView / ChatWallpaperBackdrop / iOSChatTopBar
- 不删 debug 代码（DebugRenderSettings / DebugSettingsTab 等，粟粟说保留到上架前）
- 不动主题 / ThemeEditor / ThemeAssetStore

---

## 4. 回滚策略

每个 Phase 独立 commit：
- Phase 1 commit 后如果 P2 失败，可以 revert P2 保留 Phase 1（至少删掉了 UIKit hack，ScrollView 架构已就位）
- Phase 1 本身失败就 `git reset --hard d38fe6c` 回到当前 HEAD

---

## 5. Checklist 汇总

Phase 1（骨架）:
- [ ] P1.1 scrollPosition state
- [ ] P1.2 TabView → ScrollView + HStack + paging
- [ ] P1.3 iOSPage computed
- [ ] P1.4 程序化切页换 API
- [ ] P1.5 删 UIKit hack 函数
- [ ] P1.6 保留 ScrollLock 竖直部分
- [ ] P1.7 build + 回归

Phase 2（跟手）:
- [ ] P2.1 scrollOffsetX state
- [ ] P2.2 pageWidth state + GeometryReader
- [ ] P2.3 onScrollGeometryChange hook
- [ ] P2.4 wallpaper 永远挂
- [ ] P2.5 top bar 永远挂
- [ ] P2.6 offset 公式
- [ ] P2.7 build + 回归

Phase 3（收尾）:
- [ ] P3.1 可选 opacity 渐透
- [ ] P3.2 commit + push

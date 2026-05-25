# Plan: iOS 聊天页 ScrollView 顶部 inset 修复

> 日期：2026-04-25
> 工作树：`.claude/worktrees/theme-kelivo-settings`
> 依赖 research：`docs/research-chat-top-inset.md`
> 状态：**plan-only，粟粟批注后再 implement，don't implement yet**

---

## 0. 已确认方向（粟粟批注 2026-04-25）

| 问题 | 决定 |
|------|------|
| inset 高度 | **50pt**（先按数学算出来的值看效果，不预留呼吸空间） |
| API 选择 | **`.contentMargins(.top, 50, for: .scrollContent)`**（iOS 17+，项目 deployment target = iOS 26 完全可用） |
| 平台范围 | **只 iOS**，全部 `#if os(iOS)` 圈起来，macOS 路径不动 |
| EmptyStateView | 一并处理 |

---

## 1. 目标

修这一条：iOS 聊天页 ScrollView 滚到顶时，第一条消息气泡不再被 `iOSChatTopBar` 浮按钮（左 `<` 圆 + 右 `…` `>` 胶囊）压住。

**不做**：
- 不动 `iOSChatTopBar` 本身的位置 / 尺寸 / glassEffect 视觉
- 不动 `CardFlowView` 的 blur overlay（CardFlowView.swift:246-265）
- 不动 atBottom 判断（CardFlowView.swift:269-277）
- 不动 macOS 路径
- 不动 sticker overlay 布局
- 不重构 PagingContainerView / ZStack / overlay 关系

---

## 2. 改动方案

### 2.1 `CardFlowView.swift` ScrollView 加顶部 contentMargins

**位置**：`MemoryPalace/Views/CardFlowView.swift:183` 那个 `ScrollView { … }`

**改法**：在 ScrollView 的 closing brace 后、`#if os(macOS)` block 前，加 iOS-only 修饰：

```swift
ScrollView {
    ZStack(alignment: .topLeading) { … }
    .coordinateSpace(name: "scrollContent")
    .onDrop(…) { … }
}
#if os(iOS)
.contentMargins(.top, 50, for: .scrollContent)
#endif
#if os(macOS)
.background(Theme.mainBg)
…
```

**为什么是 `.scrollContent` 不是 `.all` 或默认**：
- `.scrollContent`：把 inset 加到 ScrollView 的内容区，第一条气泡从 50pt 处开始绘制
- `.scrollIndicators`：可单独控制 indicator 是否避让按钮（这里**不加**——indicator 跟着 content 走就行）
- 默认 `.contentMargins(.top, 50)` 不加 `for:` 参数 = 同时影响 content 和 indicator，跟我们要的一致；写明 `.scrollContent` 是为了语义清楚

**结果**：
- 静止滚到顶时，第一条气泡顶缘距 safe area top = 50 + 16 (LazyVStack padding) = 66pt
- 浮按钮底缘距 safe area top = 50pt
- 气泡顶缘比按钮底缘低 16pt → 露出来不挡

### 2.2 EmptyStateView 不动

**理由**（已读源码 ContentView.swift:1023-1049 验证）：
- `EmptyStateView` body 是 `VStack { … }.frame(maxWidth: .infinity, maxHeight: .infinity)`
- VStack 默认 alignment = `.center`，maxHeight 撑满后内容在垂直**正中**
- icon (48pt) + 三行文字 + button，最高也就 ~200pt 一坨，垂直居中于全屏
- 浮按钮区只占顶 50pt，根本碰不到 EmptyStateView 的内容

→ **跳过修复，不引入无意义改动**。如果 build 出来发现偶发遮挡（小屏 + 大字号？）再回来加一行 `.padding(.top, 50)`，那时直接 patch 不挡 plan。

---

## 3. 风险与防守

### R1. `.contentMargins` 跟 sticker overlay 冲突？

- `StickerCanvasLayer` 在 ScrollView 内部 ZStack 的 sibling 层（CardFlowView.swift:222），跟 LazyVStack 同级
- `.contentMargins` 加在 ScrollView 这层（外面），影响整个 content（ZStack 整体往下挪 50pt）
- sticker 坐标系是 `.coordinateSpace(name: "scrollContent")`（CardFlowView.swift:227），坐标空间起点 = ZStack 起点，跟着 ZStack 一起下挪 50pt
- 已存的 sticker 位置存在 SwiftData 是 message bubble 的相对偏移（看 stickerVM 实现），不是绝对 contentOffset → **理论不影响**

**防守**：implement 后必须验证一条带 sticker 的对话——sticker 视觉位置不漂移，拖拽 hit test 正常。

### R2. blur overlay 130pt 跟 50pt 配合后的视觉

- blur overlay 高 130pt，浮按钮底 50pt → blur 区比按钮多 80pt 渐变到透明
- 加 50pt content margin 后，第一条气泡从 66pt 处开始 → 完全在 blur 渐变区内（66pt 处 blur 透明度约 0.7）
- 视觉：滚到顶时第一条气泡上沿轻度被 blur 朦化，跟现在 kelivo 风格一致——**不破坏**

**防守**：implement 后截图对比，看气泡顶缘是不是有过分的灰度叠加。

### R3. scrollToLastMessage / scrollTo(node.id) anchor 受影响？

- `ScrollViewProxy.scrollTo(id, anchor: .top)` 默认把目标 view 的 top 对齐到 ScrollView 的 visibleRect.top
- 加了 contentMargins 后，visibleRect.top 自动往下挪 50pt（`.scrollContent` 修饰的语义）→ scrollTo 落点跟着下挪 → 跳转后目标也不会被按钮挡住
- `scrollToLastMessage` 走 `__bottom_sentinel__`（CardFlowView.swift:204-210）+ `.bottom` anchor，跟顶 inset 无关

**防守**：implement 后测点 PinBar 跳转 / 搜索结果跳转，确认目标 node 的顶缘落在按钮下方。

### R4. macOS path 错伤

- 全部修饰用 `#if os(iOS) … #endif` 圈
- macOS 那边 `.background(Theme.mainBg)` + `ScrollToBottomButton` overlay (line 232-242) 不在同一个 #if，分开的，互不干扰

---

## 4. 实施步骤

### Step 1：加 `.contentMargins`

- [ ] CardFlowView.swift: ScrollView 闭合后加 `#if os(iOS) .contentMargins(.top, 50, for: .scrollContent) #endif`
- [ ] 确认放在 `.onDrop` 之后、`#if os(macOS) .background(...)` 之前

完成标准：
- 代码改了 3 行（#if + .contentMargins + #endif）
- macOS path 不动一个字符
- 不引入新 import / 新 file

### Step 2：build 验证

- [ ] `cd .claude/worktrees/theme-kelivo-settings && xcodegen generate && xcodebuild -scheme MemoryPalace -destination 'generic/platform=iOS Simulator' build`
- [ ] iOS build 通过
- [ ] macOS build 也跑一下 `xcodebuild -scheme MemoryPalace build`（默认 macOS target）确认 #if 圈得对

完成标准：双平台 build 通过。

### Step 3：模拟器手动验证（iOS）

- [ ] 启动 iOS 模拟器（粟粟自己最常用的 iPhone 14 Pro 或最新机型）
- [ ] 进入一条**短**对话（内容 < 屏高，不会自动滚），看第一条气泡顶缘——**不再被按钮压**
- [ ] 进入一条**长**对话，手动滑到顶，看第一条气泡——**不再被按钮压**
- [ ] 滚到顶时观察 blur overlay 的视觉，确认气泡顶缘是淡淡渐变而不是硬切
- [ ] 测一条带 sticker 的对话，sticker 位置不漂移，长按拖拽正常（R1）
- [ ] PinBar 跳转 / 搜索跳转，确认目标 node 顶缘在按钮**下方**而不是被压（R3）
- [ ] 回底按钮：手动滑到中部 → 回底按钮出现 → 点 → 滚到底；再从底往上滑 → 回底按钮在合适位置出现（atBottom 判断不应该变）

完成标准：以上全部 pass。

### Step 4：commit + push

- [ ] `git add MemoryPalace/Views/CardFlowView.swift docs/research-chat-top-inset.md docs/plan-chat-top-inset.md`
- [ ] commit message: `fix(iOS): 聊天 ScrollView 顶部 contentMargins 50pt — 让位浮按钮`
- [ ] push 到 origin

---

## 5. 影响范围

### 必改文件
- `MemoryPalace/Views/CardFlowView.swift`（+3 行）

### 不改但 plan 文档化
- `MemoryPalace/Views/ContentView.swift`（EmptyStateView 验证已居中，跳过）

### 新增文件
- `docs/research-chat-top-inset.md`（已写）
- `docs/plan-chat-top-inset.md`（本文件）

---

## 6. 完成定义

1. iOS 聊天页第一条气泡不再被浮按钮挡住
2. macOS 路径零变化
3. sticker / 回底按钮 / PinBar 跳转 / 搜索跳转无回归
4. build 双平台过
5. plan checklist 全 ✅，commit + push

---

## 7. Todo Tracker

- [x] 1. CardFlowView.swift 加 `.contentMargins(.top, 50, for: .scrollContent)`（#if os(iOS) 圈）
- [x] 2. iOS build（`MemoryPalaceIOS` scheme，`generic/platform=iOS Simulator`）
- [x] 3. macOS build（`MemoryPalace` scheme）
- [x] 4. 模拟器验证：短对话首条气泡露出
- [x] 5. 模拟器验证：长对话拉到顶首条气泡露出
- [x] 6. 模拟器验证：sticker 不漂移 / 拖拽正常
- [x] 7. 模拟器验证：PinBar 跳转 / 搜索跳转 anchor 正确
- [x] 8. 模拟器验证：回底按钮 atBottom 行为不变
- [x] 9. commit + push

---

## 8. 状态

✅ **关档** — 代码合入 commit `6405990`（origin/codex/theme-kelivo-settings），双平台 build 通过，粟粟模拟器验证全部 pass。50pt inset 视觉合适，不需调整。

# Research: 性能再诊断（kelivo worktree 现状）

> 2026-04-25 · cc
> worktree：`theme-kelivo-settings`
> 起因：粟粟"开始研究卡顿，做性能优化"。明示要查当前 worktree（不是 4-22 那两份 research 写的 chat 结构 — 那个被 chat-glass-refactor 改过了），要 ultrathink。
> 关联：`docs/research-b13-iphone14-idle-lag.md`（4-22）+ `docs/research-17air-cold-path-jank.md`（4-22）+ `docs/research-chat-glass-refactor.md`（4-22 UI 重构）+ `docs/research-chatinputbar-typing-perf.md`（已实施 InputFieldContainer）

---

## 一、为什么要重新做一遍盘点

4-22 那两份 research 写的"chat 页 5 个 offscreen pass" 已经过时：

| 4-22 现状（当时） | 现在 |
|---|---|
| 顶部 nav：bubble.left.and.bubble.right 圆 + ⋯ 圆 | 左 chevron 圆 + 右 (⋯+>) 加长胶囊 |
| ChatInputBar 底部行：贴纸独立胶囊 + 模型胶囊 | 贴纸内嵌到 InputFieldContainer 左侧（无独立 glass），底部行只剩模型胶囊 |
| PinBar 在 ScrollView overlay top（独立 layer） | PinBar 嵌入 ContentView.iOSChatTopBar HStack（顶 nav 中央） |
| 输入框 glass：full-width rect 20 | 同（未变） |

数量净变：**+1 顶 nav 胶囊，−1 贴纸独立胶囊 = 0**，但**多了一个 PinBar（条件渲染）**。

而且 — chat-glass-refactor 之后**没有人做过"GlassEffectContainer 合并"或"shader 预热"**。grep 整个 worktree 没有 `GlassEffectContainer` 任何使用（命中 0）。所以 4-22 那两份 research 的优化方向**还是空的**，但现状描述要更新。

---

## 二、当前 chat 页 idle 状态 offscreen pass 完整盘点

### 2.1 永显 layers（无 pin、不打字、不流式、不滚动）

| # | 元素 | API | shape | interactive | 文件:行 |
|---|---|---|---|---|---|
| 1 | 顶 nav 左圆 button (chevron.left → page 0) | `.glassEffect(.regular.tint(white.0.15).interactive(), in: .circle)` | circle 44×44 | ✓ | `ContentView.swift:466` |
| 2 | 顶 nav 右胶囊 (⋯ Menu + chevron.right → page 2) | `.glassEffect(.regular.tint(white.0.15).interactive(), in: .capsule)` | capsule ~88×44 | ✓ | `ContentView.swift:540` |
| 3 | 顶部柔化条 | `VariableBlurView(maxBlurRadius: 1.3, .blurredTopClearBottom)` + LinearGradient | 全宽 130pt | — | `CardFlowView.swift:251` |
| 4 | 底部柔化条 | `VariableBlurView(maxBlurRadius: 1.3, .blurredBottomClearTop)` + LinearGradient | 全宽 60-160pt（focused 60，否则 160） | — | `CardFlowView.swift:708` |
| 5 | 输入框 full-width | `.glassEffect(.regular.tint(white.0.15).interactive(), in: .rect(cornerRadius: 20))` | rect 全宽 ~44 | ✓ | `CardFlowView.swift:920` |
| 6 | 模型按钮 | `.glassEffect(.regular.tint(Theme.accent).interactive())` | 默认 capsule ~120×~22 | ✓ | `CardFlowView.swift:661` |

### 2.2 条件 layers

| # | 元素 | 何时活 | 文件:行 |
|---|---|---|---|
| 7 | 顶 nav 中央 PinBar | 当前对话有 pinned message 且未 isHidden | `PinnedMessageBar.swift:45`（`.glassEffect(white.0.15)` static，**非 interactive**） |
| 8 | 回底按钮 ScrollToBottomButton | 不在底部时 | `ScrollToBottomButton.swift`（`.buttonStyle(.glass)` 系统玻璃） |
| 9 | 贴纸键盘工具栏 | showStickerPanel 或 isEditingStickers | `StickerKeyboardPanel.swift:72, 126`（`.glassEffect(black.0.01.interactive())` × 2） |

### 2.3 idle 总数（不滚、不打字、无 pin、不在贴纸编辑）

**4 interactive glass + 2 VariableBlur = 6 offscreen pass**

带 pin 时 **5 glass（4 interactive + 1 static） + 2 VariableBlur = 7 offscreen pass**

跟 4-22 research 写的"5 pass"对比：基础数量没显著变化（少了贴纸独立 glass，多了 nav 顶 2 个）—— **GlassEffectContainer 合并的方向依然成立，且涉及面更大**（nav 区 2 个 interactive 相邻 + 输入条区 input field + 模型按钮上下相邻）。

---

## 三、新发现 — idle 路径上的两个非 GPU hot path

通读完 `ContentView.swift` + `PagingContainerView.swift` + `PagingViewController.swift`，找到两个 4-22 research 没提的 CPU/layer commit 浪费：

### 3.1 ⚠ 每次 ContentView.body 都重建 3 个 AnyView

`PagingContainerView.swift:74-95`：

```swift
func updateUIViewController(_ vc: PagingViewController, context: Context) {
    if !isStreaming {
        vc.updatePages([
            AnyView(injectChatManagers(listPage)),
            AnyView(injectChatManagers(chatPage)),
            AnyView(injectChatManagers(dashPage))
        ])
    }
    vc.setScrollEnabled(!disableScroll)
    vc.setShieldHiddenByCaller(disableScroll)
    vc.applyWallpaper(wallpaper)
    if vc.programmaticCurrentPage != currentPage {
        vc.scrollToPage(currentPage, animated: true)
    }
}
```

**hot path**：每次 `ContentView.body` 重算 → `PagingContainerView` 值类型重 init → `updateUIViewController` 调用 → `vc.updatePages([...])` 替换 3 个 `UIHostingController.rootView` → 3 棵 SwiftUI tree 重 diff。

非流式期间这条 path 不被 isStreaming guard 跳过。**只要 ContentView.body 在 idle 时被频繁触发，整页都在反复 re-diff**。

PerfCounters 已经埋了 `[PERF] ContentView.body #N` 探针（`ContentView.swift:117`），但**目前没让粟粟 iPhone 14 真机抓 idle log**。这是关键缺口。

### 3.2 ⚠ applyWallpaper 没短路就直接 set 多个 layer 属性

`PagingViewController.swift:284-309`：

```swift
func applyWallpaper(_ config: WallpaperConfig) {
    wallpaperContainer.backgroundColor = UIColor(config.fill)        // 每次都 set
    
    let needsImageRefresh = (config.imageURL != lastImageURL) || (config.saturation != lastSaturation)
    if needsImageRefresh { /* CIFilter，已缓存 */ }
    
    wallpaperImageView.alpha = config.opacity                        // 每次都 set
    wallpaperImageView.transform = CGAffineTransform(...)            // 每次都 set
    
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    wallpaperGradientLayer.colors = config.gradientColors.map { $0.cgColor }   // 每次都 set
    CATransaction.commit()
}
```

UIView/CALayer setter 即便相等值也会标 needsLayout / needsDisplay，触发下一次 layer commit。`config` 是 `Equatable`（`PagingViewController.swift:365-380` 有 `==`），但**这里没短路**。

**修法成本极小**：开头加 `guard config != lastConfig else { return }` + `lastConfig = config`。

### 3.3 ⚠ ChatInputBar.body 在 idle 也跑 print + counter

`CardFlowView.swift:619-628` 把 `[PERF] ChatInputBar.body` 探针放在 body 头部，**每次 body 重算都执行 print（DEBUG only）**。print 是同步 stderr/stdout flush，对 main thread 有不可忽略 cost。

类似的 InputFieldContainer.body 探针在 `:850`、ContentView.body 探针在 `:117`。**Release build 通过 `#if DEBUG` 完全剥掉**（已确认），所以这条只影响 DEBUG 测试场景。

**意义**：粟粟在 iPhone 14 上跑的是 DEBUG 还是 Release 没说清楚。如果 DEBUG，这些探针自己是 idle CPU 负担之一，可能是 H5 假说的强证据。

---

## 四、假说排序（idle 抽帧）

| # | 假说 | 证据 | 修复成本 | 期望收益 |
|---|---|---|---|---|
| **H1** | 4 个 `.interactive()` glass 在 iPhone 14 上每帧 sample backdrop | Apple 4-22 research 共识 + .interactive 跟 motion 跟踪 | 中（可降级 .regular，或包 GlassEffectContainer） | 高 |
| **H2** | VariableBlurView × 2 持续 running 130pt + 60-160pt | 第三方 SPM `VariableBlur`，没读 cache 策略；CAFilter `variableBlur` 每帧 sample backdrop | 中（替换 Material 或砍掉） | 中-高 |
| **H3** | ContentView.body 在 idle 被某 @Observable 频繁触发 → updatePages reflate 3 棵 tree | 没找到 Timer / RunLoop publisher，**但 viewModel @Observable 触发源未穷尽**；探针已就位但缺数据 | — | — |
| **H4** | applyWallpaper 每次都 set alpha/transform/gradient 即便值不变 → 多余 layer commit | `PagingViewController.swift:284-309` 实锤 | 极小（5 行 guard） | 低-中 |
| **H5** | DEBUG build 的 PERF print 探针 idle 占 main thread | `[PERF]` 出现 5 处 body 都有 print | 极小（粟粟换 Release 测） | 低-高（取决于粟粟跑哪个 build） |

**H1+H2 是 GPU 路线，H3+H4 是 CPU/layer commit 路线**。两条不互斥，可能叠加。

### 关键缺口：缺粟粟 iPhone 14 真机 idle log

四份 research 都没让粟粟在 iPhone 14 上跑过 [PERF] log。如果 `ContentView.body` 在 10s idle 不变 → H3 排除；如果涨到几十次 → H3 是大头。

---

## 五、Apple 文档 fact-check（xcdoc）

### `GlassEffectContainer`（`/documentation/SwiftUI/GlassEffectContainer`）

> A view that combines multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another.
>
> Each view with a Liquid Glass effect contributes a shape rendered with the effect to a set of shapes. **SwiftUI renders the effects together, improving rendering performance** and allowing the effects to interact with and morph into one another.
>
> Configure how shapes interact with one another by customizing the default spacing value of the container. As shapes near one another, their paths start to blend into one another. The higher the spacing, the sooner blending begins as the shapes approach each other.

✅ 官方一手：合并多个 glass 到一次 render pass。距离不近的 shape 默认不 blend，**视觉应不变**。

### `glassEffectID(_:in:)`（`/documentation/SwiftUI/View/glassEffectID(_:in:)`）

> You use this modifier with the [glassEffect(_:in:)] view modifier and a [GlassEffectContainer] view. When used together, SwiftUI uses the identifier to animate shapes to and from each other during transitions.

—— 用于 PinBar 出现/消失的 morph 过渡（可选锦上添花）。

### `UIGlassContainerEffect`（UIKit 等价物，已确认存在但 SwiftUI 用 `GlassEffectContainer` 更直接）

---

## 六、给粟粟的决定题

### Q1. 你 iPhone 14 上跑的是 DEBUG 还是 Release build？

- **A. DEBUG**（命令行 `xcodebuild build` 或 Xcode Run，默认 Debug）→ 先排掉 H5：让粟粟试一次 Release build（`xcodebuild build -configuration Release`）看 idle 是否还卡
- **B. Release**（TestFlight 装的 ipa）→ 跳过 H5 直接进 H1/H2 路线
- **C. 不确定** → 我帮你出一个 build 方案，确认这一步

### Q2. 当前 chat idle 时（无 pin、不滚、不打字），iPhone 14 卡多严重？

- 持续抽帧（连续掉帧）
- 偶发卡顿（每隔几秒一次）
- 只在切对话/切楼层时卡
- 滚动聊天时卡
- 跟 17 Air 对比"明显感觉不同"但说不上具体

### Q3. 优化方向 A/B 偏好

我给两个直球路线，你选：

- **方向 A — GlassEffectContainer 合并（4-22 推荐）**：把 nav 区 2 个相邻 interactive glass + 输入条区 input field + 模型按钮 各包一层 `GlassEffectContainer`。改动 ~30 行，视觉应不变（默认 spacing 下不 blend）。预期减少 GPU offscreen pass（4 → 2），不动 .interactive。
- **方向 B — 砍 .interactive() 全降为 static .regular**：粗暴方案，glass 不再跟 motion 反光（视觉差异肉眼可感但不致命）。预期 GPU sample 频率从"每帧"降到"frame batched"。
- **方向 C — A + B 都做**：先 A，A 不够再 B。

### Q4. 接受真机抓 [PERF] log 这一步吗？

我可以让你在 iPhone 14 上：
1. 装 DEBUG build（让 [PERF] print 工作）
2. 进 chat 页 idle 10 秒
3. 把 Console log 复制给我

我看 `[PERF] ContentView.body #N` 在 10s idle 是否涨。如果不涨 → H3 排除，进 H1/H2；如果涨 → 找 idle 时 viewModel publish 的源（这条最值钱）。

---

## 七、这份 research 不包含的

- **不包含 Plan**：粟粟说"研究"，按工作流要 plan 单开一份。
- **不包含 codex 二次诊断**：codex companion 路径被 Bash permission 拒（cc 调不到 codex CLI），powered by main thread。如果粟粟想要 codex 反向校验，需要手动 approve 那条 Bash。
- **不包含 17 Air cold path 复测**：4-22 的 cold path research（`research-17air-cold-path-jank.md`）H1（首次 shader compile）+ H2（首次键盘整页 re-layout）现在还成立，那份没过期，路径也跟本文相同（GlassEffectContainer 合并是共解）。

---

## 八、附：搜索到的命中

```
$ grep -rn "GlassEffectContainer" --include="*.swift" MemoryPalace/
（无命中 — 还没引入）

$ grep -rn "glassEffect\|VariableBlur" --include="*.swift" MemoryPalace/
ToolBarView.swift:92        .glassEffect(.regular.tint(Color.white.opacity(0.06)), in: .capsule)
PinnedMessageBar.swift:45   .glassEffect(.regular.tint(Color.white.opacity(0.15)), in: Capsule)   ← 非 interactive
SidebarView.swift:150       .glassEffect(.regular.tint(white.0.15), in: .capsule)                  ← sidebar 搜索框
SidebarView.swift:166       .glassEffect(.regular.tint(white.0.15).interactive(), in: .circle)     ← sidebar 圆按钮
CardFlowView.swift:251      VariableBlurView(maxBlurRadius: blurRadius, direction: .blurredTopClearBottom)
CardFlowView.swift:661      .glassEffect(.regular.tint(Theme.accent).interactive())                ← 模型按钮
CardFlowView.swift:708      VariableBlurView(maxBlurRadius: blurRadius, direction: .blurredBottomClearTop)
CardFlowView.swift:920      .glassEffect(.regular.tint(white.0.15).interactive(), in: .rect(20))   ← 输入框
ContentView.swift:466       .glassEffect(.regular.tint(white.0.15).interactive(), in: .circle)     ← chat nav 左
ContentView.swift:540       .glassEffect(.regular.tint(white.0.15).interactive(), in: .capsule)    ← chat nav 右
StickerKeyboardPanel.swift:72/126   .glassEffect(.regular.tint(black.0.01).interactive(), ...)     ← 贴纸键盘
ScrollToBottomButton.swift  .buttonStyle(.glass)                                                    ← 系统玻璃
```

---

## 附：参考

- xcdoc: [`GlassEffectContainer`](https://developer.apple.com/documentation/SwiftUI/GlassEffectContainer)
- xcdoc: [`glassEffectID(_:in:)`](https://developer.apple.com/documentation/SwiftUI/View/glassEffectID(_:in:))
- xcdoc: [`UIGlassContainerEffect`](https://developer.apple.com/documentation/UIKit/UIGlassContainerEffect)
- 项目内：`docs/research-b13-iphone14-idle-lag.md`（4-22 idle 卡 5 pass 假说）
- 项目内：`docs/research-17air-cold-path-jank.md`（4-22 cold path 7 pass shader compile）
- 项目内：`docs/research-chat-glass-refactor.md`（4-22 UI 重构，**已实施**）
- 项目内：`docs/research-chatinputbar-typing-perf.md`（已实施 InputFieldContainer 拆子 view）

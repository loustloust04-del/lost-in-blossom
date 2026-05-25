# Research: B13 — iPhone 14（A15）整体卡顿 "什么都不开也卡"

日期：2026-04-22
机型：iPhone 14（A15 Bionic）/ iPhone 17 Air（A19 Pro）对照
现象：粟粟真机反馈 **"什么都不开也卡"，抽帧**；17 Air 无此问题
历史：2026-04-19 从 B7 剥离，roadmap 标 🟡 中，未开始。

> 先不动代码，定位 **"卡在哪儿、卡什么时候"**，然后再决定策略。

---

## 一、先把问题拆开问

"什么都不开也卡" 字面是：**app 在屏、不操作也能感知掉帧**。

但这句话自身有歧义——"什么都不开"指哪一屏？iOS app 进去默认在 chat 页（`initialPage=1`），所以 chat 页 idle 是最可能的场景，但也要排除以下几个场景：

| 场景 | 描述 |
|---|---|
| S1. chat 页 idle | 打开 app 默认停这里，对话加载完不滚动不打字 |
| S2. 列表（sidebar）页 idle | 左滑到 list 页静止 |
| S3. 切页 | sidebar ↔ chat 横滑（PagingViewController 动画期） |
| S4. 滚动聊天记录 | 上下滑 LazyVStack，大量 bubble / MarkdownUI 入出可视区 |
| S5. 打开楼层切换 / 设置 | 弹出 sheet 过程 |

B13 roadmap 原话 "什么都不开" 倾向 S1（chat idle），但需要粟粟确认。

---

## 二、已排除的问题（历史）

看 git log 2026-04-19 前后已经定位并修掉的几处：

- ✅ **R1 revert**：ContentView 过度订阅 `ProfileManager / scenePhase` 让 body 每次 profile notification 重算整个三页 TabView。已改成 chat→sidebar flush + refresh + 3s 覆盖 flush 语义。粟粟真机当天反馈 "直接变顺滑"。
- ✅ **ChatInputBar.equatable()**：止血 326 次 body 放大（commit `4529d76`）
- ✅ **PagingContainerView.updatePages skip on isStreaming**：流式响应时不刷 3 个 HC rootView（commit `9be9ac6`）
- ✅ **Wallpaper 挪 UIKit 层**：绕开 SwiftUI `.background` 在 child HC + keyboard safeArea 下 frame 响应的坑（commit `97d11d3`）
- ✅ **Provider / Profile / PresetManager 订阅 scope 从 ContentView 收敛到 PagingContainerView**（commit `aade0a5`）

这些都是 2026-04-19 当天粟粟从 17 Air 角度验过的。但那天没抓 iPhone 14 的 log。

---

## 三、静态分析：chat 页 idle 时在持续耗什么

读 `MemoryPalace/Views/CardFlowView.swift` + `MemoryPalace/Views/Paging/*.swift` 后，chat 页在屏时**每帧系统都要做的 GPU 工作**：

### 3.1 顶部柔化条（`CardFlowView.swift:254-273`）

```swift
.overlay(alignment: .top) {
    ZStack {
        VariableBlurView(maxBlurRadius: 1.3, direction: .blurredTopClearBottom)   // ← blur pass 1
        LinearGradient(stops: [6 stops], ...)
    }
    .frame(height: 130)
    .ignoresSafeArea(.all, edges: .top)
}
```

130pt × screen width 的 **variable blur**（每像素按 gradient mask 不同半径采样 backdrop）。

### 3.2 底部输入条背景（`CardFlowView.swift:753-775`）

```swift
.background(alignment: .bottom) {
    ZStack {
        VariableBlurView(maxBlurRadius: 1.3, direction: .blurredBottomClearTop)   // ← blur pass 2
        LinearGradient(stops: [6 stops], ...)
    }
    .frame(height: isFocused ? 60 : 160)
}
```

60-160pt × screen width 的另一个 variable blur。

### 3.3 输入框玻璃（`CardFlowView.swift:951`）

```swift
HStack { TextField + Send Button }
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(),
                 in: .rect(cornerRadius: 20))   // ← glass pass 1 (full-width, interactive)
```

**full-width 输入框**（接近整屏宽度 × 约 44pt）+ `.interactive()`。

### 3.4 贴纸按钮玻璃（`CardFlowView.swift:692`）

```swift
HStack { 星星 + "贴纸" }
    .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive())
```

### 3.5 模型按钮玻璃（`CardFlowView.swift:713`）

```swift
HStack { 圆点 + 模型名 + chevron }
    .glassEffect(.regular.tint(Theme.accent).interactive())
```

### 3.6 wallpaper UIKit 层

已经在 `PagingViewController.swift:46-56, 206-246` 优化过：
- UIImageView + 缓存 saturation filter（同 URL / 同 saturation skip）
- CAGradientLayer + `CATransaction.setDisableActions(true)` 关 implicit animation

静态合成层，idle 时几乎零耗。不怀疑。

### 3.7 bubble（LazyVStack 内）

- assistant 气泡：MarkdownUI v2.4.1 渲染
- RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius) × 多个
- 不滚动时这些是 static layer（compositor 缓存 bitmap）。idle 时不怀疑 CPU，但 scroll 时新入可视区的气泡会现算。

---

## 四、强嫌疑 H1 — Liquid Glass + VariableBlur 叠加 offscreen pass

### 4.1 证据

**Apple 官方 + 社区一致信号**（`WebSearch` on "glassEffect interactive performance iPhone 14 A15"）：

> "Each glass layer needs to sample the content below it, and stacking multiple glass elements on top of each other forces the GPU to do extra passes."
>
> "Use GlassEffectContainer. Keeping the offscreen rendering count as low as possible is crucial to achieve high performance."
>
> "Keep elements compact: A full-width glass banner takes more GPU work than a small floating button."

— [Liquid Glass in Swift: Official Best Practices for iOS 26 & macOS Tahoe](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo) 以及 [Understanding GlassEffectContainer in iOS 26](https://dev.to/arshtechpro/understanding-glasseffectcontainer-in-ios-26-2n8p)

我们当前 chat 页踩了**三个雷**：

1. **3 个 glassEffect 彼此独立**，不在同一个 `GlassEffectContainer` 里 → GPU 做 3 次独立 offscreen pass
2. **输入框那个 glass 是 full-width**（"full-width glass banner"，一条横贯全屏）→ 最贵
3. **.interactive()** 每个都打开 → 相比 static `.regular`，shader 复杂度高，且响应手势 / motion 持续

加上 2 个 **VariableBlur**（backdrop CAFilter `variableBlur`，每帧真 sample + blur）共约 **5 个 offscreen pass** 每帧。

### 4.2 为什么 iPhone 14 卡 / 17 Air 不卡

- iPhone 14：A15 Bionic，5-core GPU，~2.5 TFLOPs，6GB RAM，60Hz 屏（每帧预算 16.6ms）
- iPhone 17 Air：A19 Pro 代，6+-core GPU + 新 shader 单元，120Hz ProMotion（每帧 8.3ms，但 GPU headroom 多）

同一条 render 路径，A15 每帧可能花 14-18ms（接近或超过 16.6ms 预算 → 掉帧），A19 Pro 可能只花 4-6ms。差距在 GPU 带宽 + shader 单元数 + Metal 优化。

Apple 的"A15 以上性能影响可忽略"对**单个**玻璃成立，对**多个叠加 + full-width + interactive + 双 backdrop blur**不成立。

### 4.3 待验证点

静态分析有说服力但没测过。需要两件事之一：

- **A. runtime 测帧率**：粟粟 iPhone 14 装 debug build → 切到 chat idle → 抓 Instruments > Core Animation > FPS（或肉眼看卡顿频率）
- **B. A/B ablation**：临时做一个 build 把这 5 个 pass 砍掉（降 glass 到 non-interactive / 或直接撤 glass 改 Material / 或撤 VariableBlur），粟粟 iPhone 14 对比

B 比 A 快（不需要 Instruments 操作），我倾向先做 B。

---

## 五、次嫌疑 H2-H5（static 不能排除，需要数据）

### H2. 某 @Observable 在 idle 时持续 publish → body 循环重算

已看过的 @Observable 类：

- `ProviderManager`, `ProfileManager`, `PresetManager`, `ThemeManager`, `GlobalWorldBook`, `RightPanelNavigator`, `ConversationViewModel`, `ChatService`, `StickerViewModel`

**没找到明显的 idle 时 publish 源**（没有 Timer、没有 `.repeat`，没有 scheduledTimer）。但 Swift `@Observable` macro 会对所有 property mutation 自动通知，不易搜全。

**验证**：粟粟 chat idle 10 秒 → 看 `[PERF] ContentView.body` / `ChatInputBar.body` / `InputFieldContainer.body` 计数有没有涨。

预期：
- 如果涨 → H2 存在，要找 publish 源
- 如果不涨 → 排除 H2

### H3. CALayer 爆炸 / 合成开销

chat 页 LazyVStack 里每个 bubble 至少：
- RoundedRectangle bg + 可能的 stroke
- MarkdownUI block structure（段落 / 列表 / 代码块 各自 layer）
- 可能 shadow

一般 200 条消息 = 几百个 CALayer。A15 compositor 走 Metal 肯定能处理，但叠上 5 个 blur/glass pass 后 layer tree traversal 本身也是额外开销。

**验证**：Instruments > Core Animation > Color Hits Green and Misses Red（看是否大量 offscreen）

### H4. MarkdownUI v2.4.1 渲染重

每个 assistant 气泡进入可视区时解析 + 渲染一次。

idle 时不怀疑（已缓存成 bitmap）。但如果切对话 / 滚动 / body 被反复重算，会反复触发 MarkdownUI 渲染。

**验证**：粟粟切到一个没 assistant 消息的空对话，测是否还卡。如果空对话不卡 → H4 参与。

### H5. AUDN 后台提取 / SwiftData 主线程 contention

AUDN 记忆提取是"每轮异步提取"（见总设计文档），正常在后台。但如果提取结束时在主线程 insert / save，可能偶发主线程 block。

粟粟说"什么都不开" → 应该没有新消息 → AUDN 不在提取。**排除为当前主嫌疑**，但如果 H1 修了还卡再查。

---

## 六、嫌疑排序

| # | 嫌疑 | 证据强度 | 修复成本 | 预期收益 |
|---|---|---|---|---|
| **H1** | Liquid Glass ×3 + VariableBlur ×2 叠加 offscreen pass | 高（Apple 社区共识 + 代码实锤 5 pass） | 小-中 | 高 |
| H2 | @Observable idle publish 链路 | 低（找不到 publish 源，但不能排除） | 小（先加探针） | 中 |
| H3 | CALayer 数量 + compositor 开销 | 中（MarkdownUI 多 block + rounded corner） | 中（砍视觉） | 中 |
| H4 | MarkdownUI v2.4.1 渲染 | 低（idle 时已缓存） | 大（换 lib） | 视 H1 后情况 |
| H5 | AUDN / SwiftData 主线程 | 极低（idle 场景） | — | — |

**H1 首选**，其它顺延到 H1 测完再决。

---

## 七、建议下一步（给粟粟选）

> 走 3 步工作流，Research → Plan → Implement。这份是 Research。

写 plan 前需要粟粟回答两件事：

### Q1. "什么都不开也卡" 具体指哪一屏？

- **a. chat 页 idle**（默认就停这里，对话加载完，手不动）
- **b. sidebar 列表页 idle**
- **c. 切页 / 滑动翻页动画过程**
- **d. 滚动聊天历史**
- **e. a+b+c+d 全都卡，没有明显差别**

（我最怀疑 a，但要确认——a/e 走 H1 验证，b 不一定走 H1 因为 sidebar 不带 glass，d 可能要 H3/H4）

### Q2. 你能做 A/B 测试吗？

我可以出一个 "关掉 glass + blur" 的 debug-only 开关（仿 `DebugRenderSettings` 模式），粟粟在 iPhone 14 上切换对比：

- **ON**（当前）= 5 个 offscreen pass
- **OFF** = 撤 `.interactive()` 降为 static `.regular`，或全拆 glass 改 Material，或撤 VariableBlur

如果 OFF 明显变顺 → H1 坐实 → 进 Plan 阶段（正式方案：用 `GlassEffectContainer` 合并 glass + compact 输入框 glass + 可能降 VariableBlur）

### Q3. 接受"视觉微降级"换流畅吗（预案）

如果 H1 坐实但 `GlassEffectContainer` 合并后还是卡（A15 天花板），最极端方案是：

- **Plan A**：保留完整视觉，给 A15 机型做 device-tier fallback（`ProcessInfo.thermalState` / UIDevice 推断 → 动态降级）
- **Plan B**：全局降 glass 到非 interactive（视觉变轻微，但所有机型一致）

这轮不决定。先看 A/B 测试结果。

---

## 八、这份 research 不包含的

- **没有跑 runtime log**：目前现场在 17 Air 上顺，iPhone 14 上卡，log 要粟粟抓
- **没有跑 Instruments**：我不能直接在真机跑 Profile，需要粟粟 Xcode 连 iPhone 14 跑一次
- **没查 AUDN / SwiftData 主线程 contention**：排了 H5 优先级，后续如果需要再查

---

## 附：这轮参考的文档

- [Liquid Glass in Swift: Official Best Practices for iOS 26 & macOS Tahoe](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [Understanding GlassEffectContainer in iOS 26](https://dev.to/arshtechpro/understanding-glasseffectcontainer-in-ios-26-2n8p)
- [Adopting Liquid Glass: Experiences and Pitfalls](https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences)
- [Apple: glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [Apple: UIGlassEffect.isInteractive](https://developer.apple.com/documentation/UIKit/UIGlassEffect/isInteractive)
- 项目内已有：`docs/research-chatinputbar-typing-perf.md`（ChatInputBar 打字 perf，相关但侧重打字 frame 不是 idle）
- 项目内已有：`docs/research-prompt-simple-ios-jank-caret-2026-04-16.md`（prompt 页面双滚动容器，设置页问题，与 B13 不同场景）

Sources:
- [Liquid Glass in Swift: Official Best Practices for iOS 26 & macOS Tahoe](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [Understanding GlassEffectContainer in iOS 26](https://dev.to/arshtechpro/understanding-glasseffectcontainer-in-ios-26-2n8p)
- [Adopting Liquid Glass: Experiences and Pitfalls](https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences)

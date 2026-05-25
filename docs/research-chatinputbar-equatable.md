# Research: ChatInputBar EquatableView 止血 body 放大（B3 / 路线 C 性能收尾）

> 2026-04-21 · 接手前任 cc
> 分支：`codex/theme-kelivo-settings`
> 前文：`docs/postmortem-kelivo-keyboard-wallpaper.md`, `handoff-chatinputbar-perf.md`

## 目标

把流式响应期间 **ChatInputBar.body 从 326 次降到 20 次以内**（ContentView.body 已 R1+方案 A 收敛到 19 次）。

## 证据

### 真机 log（粟粟 iPhone 17 Air · 流式响应期间）

```
[PERF] ContentView.body #19           ← 已收敛
[PERF] ChatInputBar.body #326         ← 灾难，放大 17×
[PERF] InputFieldContainer.body #328  ← 同步放大
```

`focused=N len=0` 状态下 ChatInputBar 每 ~50ms body 一次 = LLM token 间隔。视觉上"跟 token 无关"的底部输入框被强制每 token 重算。

### 放大链（抄自 handoff，已验证）

```
LLM 吐 token
 → viewModel.providerRouter.streamingText 更新（@Observable）
 → CardFlowView.body 重算（读了 streamingText）
 → iOSChatPage computed 重算（包含 CardFlowView）
 → ContentView.iOSLayout 重算（chatPage 变 AnyView 新 instance）
 → PagingContainerView 参数变 → updateUIViewController 触发
 → vc.updatePages([AnyView, AnyView, AnyView]) 无条件大锤
 → 每个 child HC.rootView = 新 AnyView（AnyView 不可结构 diff）
 → ChatInputBar 整棵 body 重算
```

**关键放大点**：`PagingContainerView.updateUIViewController:37-44` 里 `vc.updatePages(...)` **无条件**每次都调、不做 diff；AnyView 擦除类型 SwiftUI 做不了结构 diff。

### 为什么方案 A 只治了 ContentView 没治 ChatInputBar

方案 A（`aade0a5`）把 Provider/Profile/PresetManager 的 @Environment 从 ContentView 挪到 PagingContainerView 内部——解决了 **ContentView body 订阅太多 @Observable** 的订阅放大，把 ContentView.body 从 17 降到 19（稳住）。

但方案 A 没动 `updatePages` 这个"大锤"。流式期间 CardFlowView 因为读 streamingText 重算 → 只要 iOSChatPage 是 ContentView 的 computed property 引用（从 ContentView.body 里返回），iOSChatPage 每次都是 SwiftUI 意义上的"新 instance" → 包 AnyView 传进 updatePages → hc.rootView 被替换 → 整棵重 diff。

## SwiftUI 权威语义（xcdoc + @Observable 迁移指南查证过）

### 1. `.equatable()` 语义

xcdoc `developer.apple.com/documentation/swiftui/view/equatable()`：

> **"Prevents the view from updating its child view when its new value is the same as its old value."**

返回 `EquatableView<Self>`（要求 `Self: Equatable`）。SwiftUI 在 diff 树时如果 `==` 为 true，**skip 子树的 update**（不重算 body）。

### 2. `@Observable` 属性追踪机制

xcdoc `managing-model-data-in-your-app`：

> **"a view forms a dependency on an observable data model object when the view's `body` property reads a property of the object. ... When a tracked property changes, SwiftUI updates the view."**

依赖是 **body 读属性时建立的**，跟 Equatable 路径正交。即：

- **Parent 重算 → Equatable 可以拦**
- **body 里读的 @Observable 属性变化 → 直接通知该 view，绕过 Equatable 拦截**

正好是 B3 要的效果：**屏蔽"父重建传来的无变化 instance"的噪声，保留"自己订阅的 viewModel / providerManager 属性变化"的响应性**。

### 3. `@State` / `@FocusState` / `@AppStorage` 与 `==` 的交互

关键点：这三种 property wrapper 的**字段类型**（`State<T>` / `FocusState<T>` / `AppStorage<T>`）**都不是 Equatable**。

后果：Swift 编译器**无法为 ChatInputBar 自动合成 `Equatable`**。必须**手写 `static func == (lhs, rhs) -> Bool`**，只比较 **init 参数**，wrapper 字段整个跳过（`==` 函数里不读它们）。

这反而是我们想要的：
- `@State`：SwiftUI 的 storage 本身由 view identity 管理，不参与 == 比较，behave 正常
- `@FocusState`：同理
- `@AppStorage`：其 wrapped value 变化会让 view 脏掉（xcdoc: "invalidates a view on a change in value"），通路独立于 Equatable

**结论**：手写 `==` 只比 init 参数 + 不比 wrapper，SwiftUI 三种 wrapper 的状态响应性**不受影响**。

### 4. 闭包参数的比较

`onStickerTap: (() -> Void)?` 是闭包，**Swift 不允许直接比较闭包**（没有 Equatable）。

当前 parent（`CardFlowView.swift:357-371`）iOS 路径的 onStickerTap closure 捕获了 `showStickerPanel` / `stickerVM.isEditingStickers`：

```swift
onStickerTap: {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    withAnimation(.easeInOut(duration: 0.25)) {
        showStickerPanel = true
        stickerVM.isEditingStickers = true
    }
}
```

父 body 每次重算都产生**新的 closure instance**，但 **行为完全等价**（无条件赋值，没有基于 captured local/conditional 的分支，调用时仍然操作正确的 binding storage）。

安全的比较策略：**闭包作为 nil / 非 nil 的二值比较，不比较 identity**。即：
- 两边都 nil → true
- 两边都 non-nil → true（假定 behavior 稳定）
- 一边 nil 一边非 nil → false

此策略在当前代码下安全。如果将来 onStickerTap 变成有条件分支的 closure，需要补 explicit invalidation signal。

### 5. `var viewModel: ConversationViewModel` 等 class ref 的比较

所有 5 个非闭包参数（`viewModel`、`modelContext`、`profileManager`、`providerManager`、`presetManager`）都是 **class 引用**。SwiftUI view 生命周期里，这些 class 基本是全局/会话级单例：

- `viewModel` 由 `ContentView` `@State var viewModel = ConversationViewModel()` 持有，跨 body 稳定
- `modelContext` 由 `.modelContext` environment 注入，跨 body 稳定
- `profileManager` / `providerManager` / `presetManager` 由 App 根注入，稳定
- 切楼层时 `ContentView.id(profile.id)` 重建整棵 → class ref 全换 → `==` 为 false → 重算 ✓

用 `===`（ObjectIdentifier 等价）比较即可。稳定期间永远 true → body 跳过；切楼层时才变 → body 重算。

## B3 实现思路

### `extension ChatInputBar: Equatable`

```swift
extension ChatInputBar: Equatable {
    static func == (lhs: ChatInputBar, rhs: ChatInputBar) -> Bool {
        lhs.viewModel === rhs.viewModel
            && lhs.modelContext === rhs.modelContext
            && lhs.profileManager === rhs.profileManager
            && lhs.providerManager === rhs.providerManager
            && lhs.presetManager === rhs.presetManager
            && (lhs.onStickerTap == nil) == (rhs.onStickerTap == nil)
    }
}
```

（optional class 的 `===` 也合法，`nil === nil` 为 true、`nil === someObj` 为 false。）

### Parent 侧

`CardFlowView.swift:357-371` 和 `:384`（macOS）的 ChatInputBar instance 后面挂 `.equatable()`：

```swift
ChatInputBar(
    viewModel: viewModel, modelContext: modelContext,
    profileManager: profileManager, providerManager: pm, presetManager: presetManager,
    onStickerTap: { ... }
)
.equatable()
```

修改面：`extension` 加 8~12 行、两处调用加 `.equatable()` 共 2 行。

## 预期效果

### body 次数对比

| 操作场景 | ChatInputBar.body 改动前 | 改动后期望 |
|---|---|---|
| 启动 → 聊天页首次 render | ~5 | ~3 |
| 点输入框弹键盘（focused Y） | +3~5 | +1（focused 变，通过 wrapper） |
| 打一个字（len 变） | 不受影响（InputFieldContainer 子 view） | 同 |
| 流式响应（token 50ms） | ~每 token +1（= handoff 的 326 放大） | **0**（class ref 稳定，Equatable 为 true） |
| 切对话（convId 变） | +1~3 | +1~3（viewModel 本体不变，Equatable 仍 true；但内部 @Observable 属性变化触发，合理） |
| 切楼层 | +N（ContentView 重建） | +N（class ref 全换，Equatable false，合理） |

### 总目标

流式响应期间 ChatInputBar.body 从 **300+ 降到 20 以内**（handoff 的期望值）。

## 风险与 rollback

### 风险 1：onStickerTap closure 行为将来变成条件性

当前是无条件赋值，安全。若未来加条件分支（如 "if streaming, do X else Y"），nil/nil 比较会跳过 body，但 closure 本身调用仍然执行最新代码（因为 SwiftUI 下次 render 时拿到的 closure instance 是最新的）—— 严格说仍然安全，但**如果 closure 需要根据 caller 的 local state 产生不同效果**，则 body 跳过会让 downstream UI 看不到最新 closure bind。

**缓解**：若未来变更，parent 侧可以把"closure 签名"抽成一个 `@State var stickerTapSignature: UUID`，closure 签名变时递增 UUID，Equatable 比 UUID 而非 nil/non-nil。

### 风险 2：漏比真正会变的参数

检查清单（每个都已分析）：
- [x] `viewModel` — ContentView 持有 `@State`，仅切楼层重建，稳定 → `===` 安全
- [x] `modelContext` — environment 注入，同 ContentView 生命周期 → `===` 安全
- [x] `profileManager?` / `providerManager` / `presetManager?` — App 单例 → `===` 安全

body 内部读的属性（`viewModel.providerRouter.isStreaming`、`viewModel.budgetBlockedMessage`、`providerManager.availableModels`、`profileManager?.currentProfile.systemPrompt` 等）由 `@Observable` 属性级追踪直接通知 view 脏掉，**不走 Equatable 路径**，安全。

### 风险 3：SwiftUI diff 时机的潜在 edge case

EquatableView 是 SwiftUI 官方机制（xcdoc 列为 **Category: Identity**，跟 `.id(...)` 同级），不是 hack。社区多年案例、Apple sample code 都用过。不预期踩机制坑。

### Rollback

单行回退：移除两处 `.equatable()` 调用，保留 `Equatable` extension 无副作用（`Equatable` extension 只在被 `.equatable()` 消费时生效）。完整回退：`git revert` 该 commit。

## 真机验证方案

按 handoff `真机验证 how-to` 执行。核心 checklist：

- [ ] 启动 → 聊天页初次 render，记录 ContentView.body / ChatInputBar.body 初始次数
- [ ] 点输入框弹键盘，记录增量
- [ ] 打 5 个字 → 记录增量（主要看 InputFieldContainer，ChatInputBar 不应增加）
- [ ] 发送消息 → LLM 流式响应（至少 30 token）→ 记录 ChatInputBar.body 增量
- [ ] 切对话（sidebar 点另一条）→ 记录增量
- [ ] 切楼层 → 记录增量

成功判定：**流式响应 30+ token 期间 ChatInputBar.body 增量 < 5**（理想 = 0）。

失败判定：流式响应期间 ChatInputBar.body 仍线性增长 → Equatable `==` 有 bug（大概率是某个 class ref 实际不稳定），打开 [PROBE] 在 `==` 里 print 差异字段定位。

## 相关文件

- `MemoryPalace/Views/CardFlowView.swift:607-819` ChatInputBar struct + body + modifiers
- `MemoryPalace/Views/CardFlowView.swift:357-371` iOS 调用点（带 onStickerTap）
- `MemoryPalace/Views/CardFlowView.swift:384` macOS 调用点（无 onStickerTap）
- `MemoryPalace/Views/Paging/PagingContainerView.swift:37-44` updateUIViewController 的大锤（本 PR 不动）

## 粟粟过目指引

请在这个 doc 里批注以下几点，我再写 plan：

- [ ] 5 个 class ref 的稳定性假设对不对？有没有我漏掉的 scenario 会让它们 mid-session 换引用？
- [ ] `onStickerTap` 闭包的 "nil/non-nil 二值比较" 你能接受吗？（当前代码安全，未来有风险）
- [ ] 要不要在这一轮顺手把 InputFieldContainer 也 Equatable 化？（看 postmortem 它也放大到 328，但它是 ChatInputBar 的 direct child；如果 ChatInputBar 跳过 body，InputFieldContainer 自然不重建。先不动，等真机数据。）
- [ ] 真机验证成功判定阈值（流式 30+ token 增量 < 5）合理吗？
- [ ] 有没有"等我手头别的事情先"—— commit 时机？

批注完我就写 plan。

# Research: 聊天页玻璃按钮布局精修

> 2026-04-22 · 接手 cc
> 分支：`codex/theme-kelivo-settings`
> 起因：粟粟反馈"玻璃按钮太多了大小不一"，给出 5 点改动 + mockup 截图

## 目标

把 iOS 聊天页的玻璃层数和尺寸统一，具体 5 件事（来自粟粟 mockup）：

1. **配色统一** — 除模型选择器保紫色 `Theme.accent`，其他玻璃 tint 一律 `white.0.15`
2. **贴纸按钮内嵌输入框左侧** — 学 Tg，取消底部独立胶囊，放进 `InputFieldContainer` 内左边
3. **顶部两个按钮 → 左右箭头** — 替换"两气泡"和"⋯"，语义仍是 `page0 ←→ page2` 滑页
4. **右侧加长胶囊容两个按钮** — 右箭头 `>`（滑 page2） + `⋯`（点开菜单）
5. **Pin Bar 挪到顶部 nav 正中间** — 原标题位置；当前对话标题挪进 `⋯` 菜单顶部展示

---

## 当前状态清点（玻璃元素完整清单）

### ① 顶部 nav（iOSChatTopBar）

`MemoryPalace/Views/ContentView.swift:426-465`

```
HStack {
  Button(bubble.left.and.bubble.right) → iOSPage = 0
    .frame(44x44).glassEffect(tint white.0.15, .circle)
  Spacer()
  Text(selectedConversation.title)      ← 粟粟要删掉（挪进菜单）
  Spacer()
  Button(ellipsis.circle) → iOSPage = 2
    .frame(44x44).glassEffect(tint white.0.15, .circle)
}
.padding(.horizontal, 16).padding(.top, 6)
```

两个圆形玻璃按钮 + 中间居中标题，.padding(.top, 6)。

### ② 顶部 Pin Bar

`MemoryPalace/Views/PinnedMessageBar.swift` + 挂在 `CardFlowView.swift:275-291` 的 top overlay。

```swift
.glassEffect(.regular.tint(Color.white.opacity(0.15)), in: Capsule)
.padding(.horizontal, 14).padding(.vertical, 8)
.frame(maxWidth: .infinity)   // 全宽胶囊
.padding(.horizontal, 20)     // 外围 20 留白
.padding(.top, 55)            // ← 下到 nav 下方 55pt
```

内容：竖线 + 标题 + 预览 + pin icon。当前独占一行，位置在 nav 下方 55pt。

### ③ 输入框（InputFieldContainer）

`MemoryPalace/Views/CardFlowView.swift:879-978`

```swift
HStack {
  TextField(...)
  Button(send) { Image(arrow.up) }
    .frame(44x44)
    .background(Circle().fill(accent))
}
.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: rect(cornerRadius: 20))
```

rect 圆角 20 玻璃，tint white.0.15。TextField + 44×44 发送按钮。

### ④ 输入框下方工具行（ChatInputBar bottom）

`MemoryPalace/Views/CardFlowView.swift:673-719`

```swift
HStack {
  Button("贴纸") {
    HStack {
      Image(star.circle.fill) font 13
      Text("贴纸") font 10
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(Capsule().fill(Theme.branchIndicator.opacity(0.12)))  ← 内层彩色胶囊
  }
  .padding(.horizontal, 8).padding(.vertical, 3)                      ← 外层 padding
  .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive())  ← 外层玻璃

  Spacer()

  Button(modelPicker) {
    HStack {
      Circle().frame(5×5)
      Text(currentModel.name) font 10
      Image(chevron.up.chevron.down) font 7
    }
    .padding(.horizontal, 8).padding(.vertical, 3)
    .glassEffect(.regular.tint(Theme.accent).interactive())           ← 紫色玻璃
  }
}
.padding(.horizontal, 4)
.frame(height: isFocused ? 0 : nil, alignment: .top)
.opacity(isFocused ? 0 : 1)
```

`isFocused` 时整行 height=0 + opacity=0 收起。

**不一致点集中发生在这里**：
- 贴纸按钮**双层背景**（内 Capsule fill + 外 glassEffect）
- 贴纸按钮 vertical padding 8/4 内 + 8/3 外 = 实际 11pt → 比模型按钮 3pt 高 8pt
- 贴纸图标 13 vs 模型图标 5×5 + chevron 7
- 贴纸 tint `white.0.15`，模型 tint `Theme.accent` — 明显色差

### ⑤ 贴纸键盘工具栏（StickerKeyboardPanel）

`MemoryPalace/Views/StickerKeyboardPanel.swift:30-73`

```swift
HStack {
  Button(keyboard) .frame(44x44)
  toolButton(star.circle.fill, isActive)
  toolButton(note.text.badge.plus)
  toolButton(paintbrush.pointed)
  Spacer()
  if isEditing { Button("完成") .background(Capsule().fill(Theme.branchIndicator)) }
}
.glassEffect(.regular.tint(Color.black.opacity(0.01)).interactive(), in: rect(cornerRadius: 20))
```

**第三种 tint 颜色** `black.0.01`（几乎无色）。跟输入框和其他玻璃不一致。

### ⑥ 回底按钮（ScrollToBottomButton）

`MemoryPalace/Views/ScrollToBottomButton.swift`

```swift
Button { Image(chevron.down) font 17 }
  .buttonStyle(.glass)   ← 官方 GlassButtonStyle，无自定义 tint
```

iOS 26 官方样式，不带 tint 控制（系统自动玻璃灰）。这个用的是另一套 API，和 `.glassEffect(...)` 不同路线。

---

## 粟粟的 5 点 × 涉及文件映射

### ① 配色统一 `white.0.15`

涉及改动：
- `ContentView.swift:438, 459` — nav 两按钮已经是 white.0.15 ✓（保持）
- `PinnedMessageBar.swift:45` — 已经是 white.0.15 ✓（保持）
- `CardFlowView.swift:692` — 贴纸按钮会被删掉（换成内嵌图标，见 ②）
- `CardFlowView.swift:713` — 模型选择器 tint `Theme.accent` **保紫**（粟粟明确说"除了模型选择器"）
- `CardFlowView.swift:951` — InputFieldContainer 已经是 white.0.15 ✓（保持）
- `StickerKeyboardPanel.swift:72, 126` — `black.0.01` **改成 white.0.15**（跟其他统一）
- `ScrollToBottomButton.swift` — `.buttonStyle(.glass)` 系统玻璃，不归 tint 管，可能跟 white.0.15 对不上

**风险**：`.buttonStyle(.glass)` 的灰色和 `white.0.15` 手动 tint 的白色视觉不完全一致。粟粟 mockup 里回底按钮没出现（在聊天界面底部右），可能感知不到差异，但要确认是否也要改成 `.glassEffect(white.0.15)` 手动版。

### ② 贴纸按钮内嵌输入框左侧

删除：
- `CardFlowView.swift:676-693` — 底部工具行里的贴纸按钮整个 Button block
- `CardFlowView.swift:717-719` 行里 `.frame(height: isFocused ? 0 : nil)` 逻辑要跟着改（现在整行 focused 时收起，没了贴纸后单独剩模型按钮，布局可调整）

新增：
- `CardFlowView.swift:901-948` (InputFieldContainer.body HStack) 在 TextField **左侧**加一个贴纸按钮：
  ```swift
  Button { onStickerTap?() } label: {
    Image(systemName: "star.circle.fill")
      .font(.system(size: 18))   ← 参考 Tg 输入框图标尺寸
      .foregroundColor(Theme.textMuted)
      .frame(width: 32, height: 32)
  }
  .buttonStyle(.plain)
  .padding(.leading, 6)
  TextField(...)                 ← 原 TextField 向右偏移
  Button(send) ...
  ```

**但是**：`InputFieldContainer` 当前签名没有 `onStickerTap`，需要把 `ChatInputBar.onStickerTap` 从外层传下来到 `InputFieldContainer`：
- 改 `InputFieldContainer.init` 签名加 `let onStickerTap: (() -> Void)?`
- 改 `ChatInputBar.body:664-670` 调用处传 `onStickerTap: onStickerTap`

**Equatable 副作用**：`ChatInputBar: Equatable`（`CardFlowView.swift:862-871`）判断 `(lhs.onStickerTap == nil) == (rhs.onStickerTap == nil)`。只要 iOS 永远 non-nil / macOS 永远 nil，加到 `InputFieldContainer` 不影响 ChatInputBar 相等性判断。**无风险**。

**isFocused 时贴纸图标是否保持可见？**
- Tg 默认贴纸 icon 在输入框里永远可见（焦点态也在）。粟粟没明说，建议跟 Tg — Plan 里确认。
- 如果保持可见：InputFieldContainer 逻辑简单
- 如果 focused 时隐藏：需要在 HStack 里根据 `isFocused` 控制 opacity/frame

### ③ 顶部左右箭头替换"两气泡 + ⋯"

涉及：
- `ContentView.swift:434` — `Image("bubble.left.and.bubble.right")` → `Image("chevron.left")`
- `ContentView.swift:455` — `Image("ellipsis.circle")` → `Image("chevron.right")`
- Icon 视觉大小保持 `font(.system(size: 15, weight: .medium))`（或视觉调整到箭头看起来和原图标一样大）

单纯换图标，行为不变（仍是 iOSPage 切换）。

### ④ 右侧加长胶囊容 ⋯ + `>`

改造 `iOSChatTopBar` 右侧：

```swift
// 从单个圆形玻璃按钮 → 一个加长胶囊含两个按钮
HStack(spacing: 0) {
  Button(ellipsis) { showMenu = true }
    .frame(width: 44, height: 44)
  Button(chevron.right) { iOSPage = 2 }
    .frame(width: 44, height: 44)
}
.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: Capsule)
```

宽度：~88pt 胶囊。

**`⋯` 菜单内容**（按 mockup）：
1. **顶部展示**：当前对话标题 `Text(selectedConversation.title)` — 非可点（或 disabled Button）
2. **Change project** — 改标签（mockup 翻译，对应 app 里的"加标签"）
3. **Star** — 收藏（toggle `conversation.isFavorite`）
4. **Rename** — 改标题名（当前已有 SidebarView 行内重命名逻辑，对话内改名需要新做 sheet / alert）
5. **Delete** — 删除（softDelete，执行后跳转 page0）

**数据关系**：
- `Conversation.isFavorite: Bool` — Star toggle 直接改这个 ✓
- `ConversationTag` + `FavoriteItem` join — Change project 需要子菜单显示所有 tag、多选 toggle
- `Conversation.title: String` — Rename 需要 sheet/alert 输入框
- `viewModel.softDeleteConversation(conv)` 已存在 ✓

**"Change project" 语义尚不明确**：
- 选项 A：单选（替换当前 tag）—— 但数据模型是多对多，选项 A 会丢信息
- 选项 B：多选（子菜单里每项带 checkmark，点击 toggle） —— 和 SidebarView 的"加标签"Menu 行为一致
- 选项 C：新开 sheet 显示 tag 列表 + 多选 checkbox —— 更丰富但更重
- 粟粟截图菜单里 Change project 是单项（没有嵌套）。Plan 阶段确认走 B 还是 C。

**Rename 实现方式**：
- SidebarView 原地把 row 变成 TextField 的方式在聊天页 nav bar 里不合适
- 用 `.alert("重命名", text: $newTitle)` 原生弹框，最简
- 或 sheet — 太重

**菜单弹出方式**：
- SwiftUI 的 `Menu { ... } label: { ... }` — 原生 dropdown，但样式不好控制（mockup 是下拉卡片）
- `.popover(isPresented: ...)` — 可自定义样式，但 iPhone 会自动变 sheet
- 粟粟 mockup 看起来是**下拉卡片 + 圆角**，像 iOS 原生 Menu 的 Liquid Glass 样式。建议用 SwiftUI Menu，让系统处理样式（iOS 26 系统 Menu 已经是玻璃风）

### ⑤ Pin Bar 挪到顶部 nav 正中间

当前：
- PinBar 作为 `ScrollView.overlay(alignment: .top)` 在 CardFlowView 里（`CardFlowView.swift:275-291`）
- 自带 `.padding(.top, 55)` 让它落在 nav 下方

目标：
- PinBar 落在 nav **同一 Y 层**，左箭头和右胶囊中间
- 原标题 `Text(conv.title)` 删除（标题挪进菜单）

两种布局路线：

**路线 A：PinBar 嵌入 iOSChatTopBar HStack**
```swift
HStack {
  leftArrowButton                 // fixed 44
  Spacer(minLength: 8)
  PinnedMessageBar(...)           // flex, 让它 maxWidth: .infinity
    .layoutPriority(1)            // 让它和 Spacer 竞争空间
  Spacer(minLength: 8)
  rightCapsule                    // fixed ~88
}
```
- 优点：布局天然协调，不需要手算宽度
- 缺点：PinBar 的 state (`pinCurrentIndex`, `pinBarHidden`) 目前在 CardFlowView 里，要挪到 ContentView（或者用 `@Bindable viewModel` 存，或者 CardFlowView 暴露 binding）

**路线 B：PinBar 留在 CardFlowView overlay，调整 Y 和宽度**
```swift
PinnedMessageBar(...)
  .padding(.top, 6)                // 和 nav 同 Y
  .frame(maxWidth: iPhone宽 - 60 - 116)
  .frame(maxWidth: .infinity, alignment: .center)
```
- 优点：最小改动，state 不挪
- 缺点：宽度要手算（nav 按钮位置写死），不同 iPhone 宽可能出错；和 nav 按钮同 overlay 不同层，z 调不好可能互相遮挡

**推荐路线 A**。pinCurrentIndex/pinBarHidden state 挪到 ContentView 或存到 viewModel，三个元素用 HStack 原生竞争空间。

**z 层数**：
- 现有 CardFlowView overlay layer 1 = blur + gradient 130pt（allowsHitTesting false）
- 现有 CardFlowView overlay layer 2 = PinBar
- 现有 ContentView iOSChatTopBar overlay = nav buttons（挂在 `iOSChatPage.overlay(.top)`）

路线 A 下 layer 2 空出来（PinBar 挪走），nav 和 PinBar 合体成一层。不影响 blur 层。

**空对话 / 无 pins 的行为**：
- 当 `pinnedNodes.isEmpty || isHidden` 时，中间什么都不显示（粟粟 mockup 右图顶部中间就是空的，没有标题了）
- 但对话未选中（`selectedConversation == nil`）时，nav 还应该显示吗？当前代码下 `iOSChatPage` 会显示 `EmptyStateView`，nav 仍然 overlay 在上面，但 `if let conv = ...Text(conv.title)` guard 里已经判了（删标题后这个 if 也可以顺手删）

---

## 改动文件一览

| 文件 | 涉及行 | 改动类型 |
|---|---|---|
| `ContentView.swift` | 426-465 (iOSChatTopBar) | 大改：删标题、换图标、右侧改胶囊、挂菜单、插 PinBar |
| `ContentView.swift` | 可能新增：pinCurrentIndex / pinBarHidden state | 新增状态（或用 viewModel） |
| `CardFlowView.swift` | 23 (pinBarHidden state)、22 (pinCurrentIndex) | 删或保留供 ContentView 读 |
| `CardFlowView.swift` | 275-291 (PinBar overlay) | 删掉（PinBar 挪到 ContentView） |
| `CardFlowView.swift` | 251-253 (safeAreaInset 让位 PinBar 高) | 删或改（PinBar 不占 ScrollView 顶部空间了） |
| `CardFlowView.swift` | 437-438 (pinBarHidden reset on convId change) | 跟随 state 挪动 |
| `CardFlowView.swift` | 673-719 (输入框下方工具行) | 删贴纸按钮，模型按钮保留 |
| `CardFlowView.swift` | 879-978 (InputFieldContainer) | 加 onStickerTap 参数、加左侧贴纸图标 |
| `CardFlowView.swift` | 357-367 (调用 ChatInputBar 处) | onStickerTap 不变（ChatInputBar 层已有） |
| `StickerKeyboardPanel.swift` | 72, 126 (glass tint) | `black.0.01` → `white.0.15` |
| `ScrollToBottomButton.swift` | — | 待定（tint 对齐 or 不动） |
| `PinnedMessageBar.swift` | 71 (.padding(.horizontal, 20))、72-76 (.padding(.top, 55)) | 删外围 padding（由 ContentView HStack 管布局） |

---

## 开放问题（Plan 阶段确认）

**粟粟 review 时请答 1-8：**

### 1. 回底按钮 tint
`ScrollToBottomButton` 现在用 `.buttonStyle(.glass)`（系统官方玻璃灰），和其他手动 `white.0.15` 玻璃有细微色差。
- A. 不动，接受细微色差（系统玻璃是官方做法）
- B. 改成 `.glassEffect(white.0.15)` 手动 tint 强行统一（但要回头踩回底按钮 tap-through 那个坑）

### 2. 贴纸键盘工具栏（StickerKeyboardPanel） tint
现在 `black.0.01`（基本透明），粟粟说"除模型选择器外统一"是否包含这个？
- A. 改成 `white.0.15`（和输入框一致）
- B. 保持 `black.0.01`（贴纸键盘弹出时在黑色键盘底 background 上，和聊天页玻璃语境不同）

### 3. 输入框内贴纸图标在 focused（键盘升起）时是否保持可见？
- A. 永远可见（学 Tg）
- B. focused 时隐藏（和当前底部工具行行为一致）

### 4. 贴纸图标样式
mockup 里是个小贴纸 icon。
- A. 沿用 `star.circle.fill`（当前贴纸按钮的图标）
- B. 换成 `face.smiling` / `photo.circle` / 其他更像 Tg 的
- C. 粟粟自己指定 SF Symbol 名字

### 5. 左右箭头图标
- A. `chevron.left` / `chevron.right`（细箭头）
- B. `arrow.left` / `arrow.right`（粗箭头）
- C. `chevron.backward` / `chevron.forward`（语义箭头，RTL 会翻转）

### 6. "Change project" 菜单行为
- A. 子菜单显示所有 tag、多选 toggle（和 SidebarView 里"加标签"一致）
- B. 点击打开一个 sheet 显示 tag 列表 + 多选
- C. 粟粟自己定义（比如单选替换，或做得更花哨）

### 7. Rename 交互
- A. `.alert("重命名", text: $newTitle)` — 最简，原生 iOS 输入框
- B. 打开 sheet 带完整 editor（支持 emoji 选择等）
- C. 顶部标题原地变 TextField（和 SidebarView 里做法一致）

### 8. Menu 样式
- A. SwiftUI 原生 `Menu { ... } label: { ⋯ }` — 系统 iOS 26 玻璃 dropdown，mockup 风格其实就是这个
- B. 自定义 `.popover` 弹出 VStack
- C. 自定义浮层 + 手写背景动画

---

## 下一步

开 `docs/plan-chat-glass-refactor.md`，按粟粟答的 8 个开放问题写 task checklist。

# Plan: 聊天页玻璃按钮布局精修

> 2026-04-22 · cc
> 分支：`codex/theme-kelivo-settings`
> Research：`docs/research-chat-glass-refactor.md`

## 目标

按粟粟 mockup 精修聊天页玻璃元素，5 件事：
1. 配色统一（除模型选择器紫）
2. 贴纸按钮内嵌输入框左侧
3. 顶部 chevron.left / chevron.right 替换抽象图标
4. 右侧加长胶囊容 ⋯ Menu + >
5. Pin Bar 挪到顶部 nav 正中间，标题挪进 ⋯ 菜单

## 8 个开放问题最终答案

| # | 答案 |
|---|---|
| a | 回底按钮 `.buttonStyle(.glass)` **不动**（系统官方玻璃） |
| b | 贴纸键盘工具栏 tint **不动**（保持 `black.0.01`） |
| c | 输入框贴纸图标 **永远可见**（focused 时也在，学 Tg） |
| d | 贴纸图标 = **`square.fill.on.circle.fill`**（填充版，匹配当前视觉重量） |
| e | 左右箭头 = **`chevron.left`** / **`chevron.right`** |
| f | Change project = **sheet**（`presentationDetents([.medium])` + drag indicator，学 ModelPickerPopover） |
| g | Rename = **`.alert`** + TextField |
| h | Menu 样式 = **SwiftUI 原生 `Menu { ... } label: { ⋯ }`**（iOS 26 系统自带玻璃 dropdown） |

## 改后长啥样（verbal mockup）

```
┌──────────────────────────────────────────────────┐
│   [<]     [ Pinned #1/2 · 你能看见...  📌 ]    [⋯│>] │  ← nav bar
├──────────────────────────────────────────────────┤
│                                                    │
│  （对话消息流）                                     │
│                                                    │
│                                    [回底 glass]    │
├──────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐     │
│  │ [🎨]  输入消息...              [↑send]  │     │  ← 输入框（贴纸内嵌左侧）
│  └─────────────────────────────────────────┘     │
│                        [ ● Claude Sonnet 4 ⇅ ]    │  ← 模型选择（紫玻璃）
└──────────────────────────────────────────────────┘
```

- 顶部 HStack 三段：左箭头(44×44 圆玻璃) + PinBar(flex，无 pin 时空) + 加长胶囊(⋯+>)
- 输入框内最左是贴纸 icon（`square.fill.on.circle.fill` 填充），右侧是原发送按钮
- 底部工具行**只剩模型选择器**（贴纸按钮已挪进输入框）

## ⋯ 菜单内容（SwiftUI Menu）

```swift
Menu {
    Section {
        Text(viewModel.selectedConversation?.title ?? "")  // header 展示，非可点
    }
    Divider()
    Button("改标签", systemImage: "tag") { showChangeProjectSheet = true }
    Button(conv.isFavorite ? "取消收藏" : "收藏", systemImage: conv.isFavorite ? "star.slash" : "star") {
        conv.isFavorite.toggle()
    }
    Button("重命名", systemImage: "pencil") { renameText = conv.title; showRenameAlert = true }
    Divider()
    Button("删除", systemImage: "trash", role: .destructive) {
        viewModel.softDeleteConversation(conv)
    }
} label: {
    Image(systemName: "ellipsis")
        .frame(width: 44, height: 44)
}
```

## ChangeProject sheet（学 ModelPickerPopover）

新增 view：`TagPickerPopover`（放在 `CardFlowView.swift` 或新文件均可）
- `@Query` ConversationTag + FavoriteItem（profileId + conversationId filter）
- List 展示所有 tag（name + emoji），每项右侧 checkmark 表示 conv 是否在此 tag
- tap 切换：已在则 delete FavoriteItem，未在则 insert FavoriteItem
- 底部"新建标签…"按钮（打开 `showNewTagSheet`，复用 SidebarView 已有逻辑 or 简化版）

## 任务清单（按执行顺序）

### Phase 1 · 输入框贴纸内嵌（②）

- [ ] **P1.1** `InputFieldContainer` 加 `onStickerTap: (() -> Void)?` 参数
- [ ] **P1.2** `InputFieldContainer.body` HStack 左侧插入贴纸 Button：
  ```swift
  if let onStickerTap = onStickerTap {
      Button(action: onStickerTap) {
          Image(systemName: "square.fill.on.circle.fill")
              .font(.system(size: 18))
              .foregroundColor(Theme.branchIndicator)
              .frame(width: 32, height: 32)
      }
      .buttonStyle(.plain)
      .padding(.leading, 6)
  }
  ```
- [ ] **P1.3** 调整 TextField `.padding(.leading, 14)` → `8`（贴纸已占左边空间）
- [ ] **P1.4** `ChatInputBar.body:664-670` 调用 `InputFieldContainer` 时传 `onStickerTap: onStickerTap`
- [ ] **P1.5** 验证 `ChatInputBar: Equatable`（CardFlowView.swift:862-871）不破坏——onStickerTap 参数 nil/non-nil 二值判定不变
- [ ] **P1.6** 删除 `CardFlowView.swift:673-693`（底部工具行贴纸按钮）
- [ ] **P1.7** 删除后，底部工具行 HStack 只剩模型按钮 + Spacer，检查 layout：`HStack { Spacer(); Button(modelPicker) ... }` 让它右对齐
- [ ] **P1.8** `build verify` — `xcodegen generate && xcodebuild -scheme MemoryPalace -sdk iphonesimulator build` 通过

**验证点**：iPhone 模拟器看输入框左边有贴纸图标，底部工具行只剩右侧模型按钮，打字时贴纸图标保持可见。

### Phase 2 · 顶部 nav 改造（③④⑤ 的一部分）

- [ ] **P2.1** `ContentView.swift:434` — `bubble.left.and.bubble.right` → `chevron.left`
- [ ] **P2.2** `ContentView.swift:455-459` — 单个 `ellipsis.circle` 按钮 → 改成加长胶囊包两个按钮：
  ```swift
  HStack(spacing: 0) {
      Menu { ... } label: {
          Image(systemName: "ellipsis")
              .font(.system(size: 15, weight: .medium))
              .foregroundColor(Theme.textSecondary)
              .frame(width: 44, height: 44)
      }
      Button { withAnimation { iOSPage = 2 } } label: {
          Image(systemName: "chevron.right")
              .font(.system(size: 15, weight: .medium))
              .foregroundColor(Theme.textSecondary)
              .frame(width: 44, height: 44)
      }
  }
  .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .capsule)
  ```
- [ ] **P2.3** 删除 `ContentView.swift:443-448`（中间 `Text(conv.title)` + 两个 Spacer）—— 标题挪进 Menu 里了
- [ ] **P2.4** Menu 实现：
  - Section header：`Text(conv.title)` 展示当前标题
  - Button "改标签" → 设 `showChangeProjectSheet = true`
  - Button 收藏 toggle → `conv.isFavorite.toggle()`
  - Button "重命名" → 设 `renameText = conv.title; showRenameAlert = true`
  - Button "删除" role `.destructive` → `viewModel.softDeleteConversation(conv)`
- [ ] **P2.5** 新增 `@State private var showRenameAlert = false`, `@State private var renameText = ""`, `@State private var showChangeProjectSheet = false` 在 `ContentView`
- [ ] **P2.6** Rename alert：
  ```swift
  .alert("重命名", isPresented: $showRenameAlert) {
      TextField("对话名称", text: $renameText)
      Button("取消", role: .cancel) { }
      Button("确认") {
          let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty, let conv = viewModel.selectedConversation {
              conv.title = trimmed
              conv.updateTime = Date()
              viewModel.markConversationDirty()
          }
      }
  }
  ```
- [ ] **P2.7** ChangeProject sheet：
  ```swift
  .sheet(isPresented: $showChangeProjectSheet) {
      TagPickerPopover(conversationId: viewModel.selectedConversation?.id ?? "",
                       profileId: profileManager?.currentProfile.id ?? "")
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
      .presentationBackground(Theme.sidebarBg)
  }
  ```
- [ ] **P2.8** 新增 `TagPickerPopover` view（参考 `ModelPickerPopover` 结构）：
  - `@Query` ConversationTag（filter profileId）
  - `@Query` FavoriteItem（filter profileId + conversationId + nodeId == nil）
  - List：每个 tag 一行 `Button { toggle } label: { emoji + name + checkmark }`
  - toggle 逻辑：FavoriteItem exists → delete / not exists → insert new
  - 底部 Divider + "新建标签…" Button（可选：用 `.alert` 输入标签名 + emoji）
- [ ] **P2.9** `build verify`

**验证点**：
- 顶部 nav 变成 [←] ... [⋯ >] 布局
- ⋯ 点开显示 Menu，顶部看到当前标题
- 重命名弹 alert
- 改标签弹 sheet 能多选 tag
- 删除后 selectedConversation = nil，跳 EmptyStateView

### Phase 3 · Pin Bar 挪到 nav 中间（⑤）

- [ ] **P3.1** State 搬家：
  - `CardFlowView.swift:22` `@State pinCurrentIndex` 删除
  - `CardFlowView.swift:23` `@State pinBarHidden` 删除
  - `ContentView` 加 `@State private var pinCurrentIndex: Int = 0`
  - `ContentView` 加 `@State private var pinBarHidden: Bool = false`
- [ ] **P3.2** handler 搬家：
  - `handlePinBarTap` / `handleUnpinCurrent` 从 CardFlowView 挪到 ContentView（依赖 viewModel 仍可访问）
- [ ] **P3.3** `CardFlowView.swift:275-291` — 删除 PinBar top overlay 整段
- [ ] **P3.4** `CardFlowView.swift:251-253` — 删除 `.safeAreaInset(edge: .top)` 让位 PinBar 高度的逻辑（PinBar 不在 ScrollView 顶部占位了；但 nav 按钮仍需要让位，检查 nav 按钮高度是否已由别处兜底）
- [ ] **P3.5** `CardFlowView.swift:437-438` — 删除 `pinBarHidden = false` 这句（state 挪到 ContentView，在 ContentView 里对 `viewModel.selectedConversation?.id` 加 onChange 处理）
- [ ] **P3.6** ContentView 加 onChange：
  ```swift
  .onChange(of: viewModel.selectedConversation?.id) { _, _ in
      pinCurrentIndex = 0
      pinBarHidden = false
  }
  ```
- [ ] **P3.7** `PinnedMessageBar.swift:71` 删除 `.padding(.horizontal, 20)`（由 HStack 管）
- [ ] **P3.8** `PinnedMessageBar.swift:72-76` 删除 iOS/macOS 的 `.padding(.top, 55/6)` 和 `.padding(.bottom, 4)`（对齐 nav 高度由 HStack + ContentView padding.top 控制）
- [ ] **P3.9** `iOSChatTopBar` HStack 结构改成三段：
  ```swift
  HStack(spacing: 8) {
      // 左箭头
      Button { withAnimation { iOSPage = 0 } } label: {
          Image(systemName: "chevron.left") ...
          .frame(width: 44, height: 44)
          .glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .circle)
      }

      // PinBar（flex，无 pin 时零宽）
      if !viewModel.pinnedNodes.isEmpty, !pinBarHidden {
          PinnedMessageBar(
              pinnedNodes: viewModel.pinnedNodes,
              currentIndex: $pinCurrentIndex,
              isHidden: $pinBarHidden,
              onTap: handlePinBarTap,
              onUnpinCurrent: handleUnpinCurrent,
              onUnpinAll: { viewModel.unpinAll(); pinCurrentIndex = 0 }
          )
          .frame(maxWidth: .infinity)
          .layoutPriority(1)
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
      } else {
          Spacer(minLength: 0)
      }

      // 右侧加长胶囊（P2.2 里做的）
      ...
  }
  .padding(.horizontal, 16)
  .padding(.top, 6)
  .animation(.easeInOut(duration: 0.25), value: viewModel.pinnedNodes.map(\.id))
  .animation(.easeInOut(duration: 0.25), value: pinBarHidden)
  ```
- [ ] **P3.10** `build verify`

**验证点**：
- 无 pin 时顶部中间是空的，左箭头和右胶囊固定两侧
- 有 pin 时中间出现 Pin Bar 胶囊，长按/右键弹"取消钉住"菜单
- 切对话时 pinCurrentIndex 重置
- iPhone 小屏（17 Air 或 SE）pin 内容被截断不爆出边界

### Phase 4 · 配色统一收尾（①）

- [ ] **P4.1** 全局 grep：`grep -n "glassEffect" MemoryPalace/Views/*.swift` 确认剩下的 tint：
  - `ContentView.swift` nav 两按钮 = `white.0.15` ✓
  - `PinnedMessageBar.swift` = `white.0.15` ✓
  - `CardFlowView.swift:951` InputFieldContainer = `white.0.15` ✓
  - `CardFlowView.swift:713` 模型选择器 = `Theme.accent` **保持紫色** ✓
  - `StickerKeyboardPanel.swift:72, 126` = `black.0.01` **不动**（粟粟 b 答案）
  - `ScrollToBottomButton.swift` = `.buttonStyle(.glass)` **不动**（粟粟 a 答案）
- [ ] **P4.2** 不需要改动，只做核对确认

### Phase 5 · 验收

- [ ] **P5.1** `xcodegen generate && xcodebuild -scheme MemoryPalace -sdk iphonesimulator build` 全绿
- [ ] **P5.2** 模拟器跑：验证 5 点都按 mockup 落地
- [ ] **P5.3** `git add -A && git commit -m "feat(iOS): 聊天页玻璃按钮布局精修 — nav 左右箭头 + PinBar 居中 + 贴纸内嵌 + Menu 菜单"`
- [ ] **P5.4** `git push`

## 风险 / 回退

1. **InputFieldContainer @State text 是否会因 `onStickerTap` 参数变化而重置？**
   - SwiftUI view identity 不看闭包，看位置+类型。加一个 closure 参数不影响 state 保留
   - 若真有问题，回退方案：将 `onStickerTap` 上提到 `InputFieldContainer` 外层，用 `ZStack` 叠加贴纸按钮到输入框左侧（不改 InputFieldContainer 签名）
2. **Pin Bar 在 nav HStack 里和左箭头、右胶囊抢宽度**
   - layoutPriority(1) + Spacer(minLength: 0) 基本可解
   - 极窄屏（SE 320pt）若 Pin Bar 内容被压到零宽，退路是整个 Pin Bar text `lineLimit(1)` + `.minimumScaleFactor(0.8)`
3. **`Menu` 里 Section header 样式可控性**
   - iOS 26 原生 Menu 不保证 `Text` 在 Section 里就长成 "猫想吃东西" 那种加粗大字
   - 如果系统渲染不符合预期，回退方案 B：用 `Button { } label: { Text(conv.title).bold() }.disabled(true)` 顶一个伪 header
4. **pinCurrentIndex 从 CardFlowView 挪到 ContentView 引入新订阅？**
   - ContentView 本来就 @Bindable viewModel，多两个 @State 不增加订阅成本
5. **路线 C Paging 下 ContentView.body 每次流式都重算**
   - P3.9 里 `if !viewModel.pinnedNodes.isEmpty` 会在流式期间被读，理论上无影响（pinnedNodes 在流式期间不变）

## 提醒（给粟粟）

- 本 plan 未提前实现，所有 task 都在上面 checklist 里
- 动手前请批注：有异议的 task 打 ✗ 或写注释，我会对齐后再动
- 批准信号：你直接说"开工"或"按 plan 走"
- 每完成一个 Phase 会 `build verify` + 更新 checklist 勾选

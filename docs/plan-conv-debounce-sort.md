# Plan: 对话列表"延迟置顶"（点击不排、内容改 debounce 3s）

> 2026-04-19
> 依赖：`docs/research-conv-debounce-sort.md`

## 目标

按粟粟确认版新语义：
- 点击对话**不影响排序**（纯浏览不打乱）
- 内容改动（消息 / rename / 贴纸加删）→ 标记 pending，**3 秒 debounce 后重排**
- Pull-to-refresh / 切楼层 / 进后台 / **从聊天页切回 sidebar** → **立刻 flush**
- toggleFavorite **不算**改动；气泡软删除**保留立即刷新**

## 原则

- 不改 Conversation schema（无 SwiftData migration 风险）
- `updateTime` 写入仍**同步**进 SwiftData（数据安全，崩溃不丢）
- 只延迟 **UI re-fetch**（通过 `sidebarRefreshTrigger`）
- Debounce 是 **reset on new dirty**（连续改动持续推迟到用户停下）
- 单 Task，取消-重启语义

---

## Phase 1：核心 debounce 机制

### 1. ConversationViewModel 加 debounce 逻辑

文件：`MemoryPalace/ViewModels/ConversationViewModel.swift`

在 class 内加两个 property + 两个方法：

```swift
// MARK: - Sidebar 重排 debounce
private var pendingRefreshTask: Task<Void, Never>?
private let refreshDebounceSeconds: UInt64 = 3_000_000_000  // 3s

/// 标记有对话需要重排（sendMessage / rename / 贴纸 mutation 后调）。
/// 连续标记会取消旧 task 重启 → 一直推迟到用户停下 3 秒。
func markConversationDirty() {
    pendingRefreshTask?.cancel()
    pendingRefreshTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }
        self?.flushPendingRefresh()
    }
}

/// 立刻触发 sidebar re-fetch，取消挂起的 debounce task。
/// Pull-to-refresh / 切楼层 / 后台 / 切回 sidebar 时调。
func flushPendingRefresh() {
    pendingRefreshTask?.cancel()
    pendingRefreshTask = nil
    sidebarRefreshTrigger += 1
}
```

**注意**：3_000_000_000 硬编码在两处（property 和 Task.sleep）—— 用同一个常量。

#### Checklist
- [ ] 1a. 在 `ConversationViewModel` 里加 `pendingRefreshTask` + `refreshDebounceSeconds`
- [ ] 1b. 加 `markConversationDirty()` 方法（debounce 入口）
- [ ] 1c. 加 `flushPendingRefresh()` 方法（立即触发）

---

## Phase 2：去掉"点击即置顶" + 改排序键

### 2. 去掉 `lastOpenedAt` 主排序键

**SidebarView.swift**（3 处排序）：
- :1284（trash mode）
- :1329（selected tag mode）
- :1341（default sort）

每处把：
```swift
[SortDescriptor(\Conversation.lastOpenedAt, order: .reverse),
 SortDescriptor(\Conversation.updateTime,   order: .reverse)]
```
改成：
```swift
[SortDescriptor(\Conversation.updateTime, order: .reverse)]
```

**WorldBookPanelView.swift**（:683, :702）保持 `lastOpenedAt DESC` **不动**（语义是"最近打开的对话"，用来给用户挑选绑定世界书，和主列表排序分离）。

#### Checklist
- [ ] 2a. `SidebarView.swift:1284` trash 排序
- [ ] 2b. `SidebarView.swift:1329` tag 排序
- [ ] 2c. `SidebarView.swift:1341` default 排序
- [ ] 2d. 确认 `WorldBookPanelView.swift:683/702` 没动

### 3. 去掉 `loadConversation` 里的点击副作用

**ConversationViewModel.swift:50-79** `loadConversation()`：
- Line 56 `conversation.lastOpenedAt = Date()` → **删除**（点击不再刷这个字段）
- Line 57 `sidebarRefreshTrigger += 1` → **删除**（点击不再触发列表 re-fetch）

保留：`selectedConversation = conversation`、加载 tree 等所有正常逻辑。

**副作用考虑**：
- `lastOpenedAt` 字段保留（import undo / WorldBookPanelView 还在用），只是**点击时不再写**
- `sidebarRefreshTrigger += 1` 去掉后：SidebarView 里 "当前选中高亮" 依赖 `viewModel.selectedConversation?.id`，@Observable 自动更新，不需要 manual trigger —— **不会回归**
- 搜索状态不受影响（搜索刷新有独立路径）

#### Checklist
- [ ] 3a. 删 `loadConversation` 里 `conversation.lastOpenedAt = Date()`
- [ ] 3b. 删 `loadConversation` 里 `sidebarRefreshTrigger += 1`
- [ ] 3c. build 验证后跑一次回归：点对话进入 + 返回 → 列表位置不变，选中高亮仍然生效

---

## Phase 3：调用 markConversationDirty 的 hook 点

### 4. `sendMessage` 末尾

**ConversationViewModel.swift:735** 附近 —— `conversation.updateTime = Date()` 后加 `markConversationDirty()`。

注意：sendMessage 里还有两处需要 markDirty：
- Line 735 设置 updateTime 后（发出时）—— 加
- Line 762-767 自动命名分支：**把 `sidebarRefreshTrigger += 1` 换成 `markConversationDirty()`**（不再立即刷，走 debounce）

#### Checklist
- [ ] 4a. `sendMessage` :735 加 `markConversationDirty()`
- [ ] 4b. `sendMessage` :767 `sidebarRefreshTrigger += 1` → `markConversationDirty()`

### 5. `editAndResend` + `regenerate` 末尾

- `editAndResend` :888 `updateTime = Date()` 后 → `markConversationDirty()`
- `regenerate` :984 `updateTime = Date()` 后 → `markConversationDirty()`

#### Checklist
- [ ] 5a. `editAndResend` :888 加 `markConversationDirty()`
- [ ] 5b. `regenerate` :984 加 `markConversationDirty()`

### 6. Rename

**SidebarView.swift:350-356** rename TextField `.onSubmit`：
```swift
.onSubmit {
    let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !newTitle.isEmpty {
        conversation.title = newTitle
        conversation.updateTime = Date()   // ← 新增
        viewModel.markConversationDirty()  // ← 新增
    }
    renamingConversationId = nil
}
```

（`viewModel` 在 SidebarView 里已经是 public property，直接调）

#### Checklist
- [ ] 6a. SidebarView rename onSubmit 加 `conversation.updateTime = Date()`
- [ ] 6b. 加 `viewModel.markConversationDirty()`
- [ ] 6c. 检查有没有 macOS 专属的 rename 入口（按 grep 看）漏掉

### 7. 贴纸 mutation（加/改/删）

**最干净方案**：给 StickerViewModel 加回调，由 CardFlowView 注入 → 转调 viewModel.markDirty + 更新 Conversation.updateTime

**StickerViewModel.swift** 加 property：
```swift
/// 贴纸变动后的回调。由 CardFlowView 注入，通常做 conversation.updateTime = Date()
/// + ConversationViewModel.markConversationDirty()
var onConversationMutated: ((_ conversationId: String) -> Void)?
```

在**每个会改变某 conversation 贴纸状态的方法末尾**调用：
- `placeSticker`（:196-）
- `placeNote`（:220-）
- 粘贴贴纸 `pasteSticker`（:338-）
- 删除贴纸（如果有单独方法——grep 确认）
- 更新贴纸位置/缩放/旋转/文本？—— **不算改动**（粟粟未明确，但"移动位置"属于微操作，不应推对话到顶。只在**增加/删除**时 markDirty）

```swift
onConversationMutated?(conversationId)
```

**CardFlowView.swift**：在 `ChatInputBar` 或者顶层处给 stickerVM 注入 callback（stickerVM 创建时一次即可）。最稳在 `ContentView.swift` 里 stickerVM 构造时注入，或在 CardFlowView.onAppear / body 顶层：

```swift
.onAppear {
    stickerVM.onConversationMutated = { [viewModel] convId in
        // 找到 conversation 并更新 updateTime
        if let conv = viewModel.selectedConversation, conv.id == convId {
            conv.updateTime = Date()
            viewModel.markConversationDirty()
        }
    }
}
```

但 stickerVM 在 ContentView 里创建（`@State var stickerVM = StickerViewModel()`）→ 更合适在 ContentView 的 `.onAppear`。**最终位置 implement 阶段再定**，视代码结构最小侵入。

#### Checklist
- [ ] 7a. StickerViewModel 加 `onConversationMutated: ((String) -> Void)?` property
- [ ] 7b. 在 `placeSticker` / `placeNote` / `pasteSticker` 末尾调用 callback
- [ ] 7c. grep 贴纸删除方法（"remove" / "delete" 相关），同样加调用
- [ ] 7d. 在 ContentView 或 CardFlowView 合适位置注入 callback 实现：查 selectedConversation + 写 updateTime + markDirty
- [ ] 7e. 确认贴纸 drag / resize / rotate / text edit **不** trigger callback（只增删才算）

---

## Phase 4：生命周期 flush

### 8. Pull-to-refresh flush

**SidebarView.swift** 4 处 `.refreshable { try? await Task.sleep(nanoseconds: 400_000_000) }`：

```swift
.refreshable {
    viewModel.flushPendingRefresh()
    try? await Task.sleep(nanoseconds: 400_000_000)
}
```

flush 立即触发 sidebar refresh，然后短 sleep 给视觉反馈。

#### Checklist
- [ ] 8a. 4 处 refreshable 闭包改成先 flush 再 sleep
- [ ] 8b. 确认 flush 和 sleep 顺序不会导致 UI 抖动

### 9. 切楼层 flush

**ContentView.swift** 监听 profile change：

```swift
// 已有 onChange(of: iOSPage) 等，加一个
.onChange(of: profileManager?.currentProfile.id) { _, _ in
    viewModel.flushPendingRefresh()
}
```

位置：在 `iOSLayout` 的 onChange 链里，或者 normalLayout 里都加（macOS/iOS 都要）。

#### Checklist
- [ ] 9a. grep profileManager.currentProfile 切换的 observer 位置
- [ ] 9b. 在合适位置加 `viewModel.flushPendingRefresh()`（iOS + macOS）

### 10. 进后台 flush

**ContentView.swift** 用 `@Environment(\.scenePhase)`：

```swift
@Environment(\.scenePhase) private var scenePhase
// ...
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .background || newPhase == .inactive {
        viewModel.flushPendingRefresh()
    }
}
```

#### Checklist
- [ ] 10a. ContentView 加 `@Environment(\.scenePhase)`
- [ ] 10b. 加 onChange flush

### 11. 从 chat 页切回 sidebar flush（iOS）

**ContentView.swift** 已有 `.onChange(of: iOSPage)`：

```swift
.onChange(of: iOSPage) { oldPage, newPage in
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    if oldPage == 1 && newPage == 0 {  // ← 新增：chat → sidebar
        viewModel.flushPendingRefresh()
    }
}
```

这让用户从聊天页切回列表时列表立刻是最新的，几乎看不到 3s 等待。

#### Checklist
- [ ] 11a. 修改 `.onChange(of: iOSPage)` closure 签名为 `(oldPage, newPage)`
- [ ] 11b. chat → sidebar 方向调 flush

---

## Phase 5：验证

### Build 验证
- [ ] 12a. `xcodegen generate && xcodebuild -scheme MemoryPalaceIOS -destination "platform=iOS Simulator,name=iPhone 17" build`
- [ ] 12b. `xcodebuild -scheme MemoryPalace -configuration Debug build` (macOS)
- [ ] 12c. 模拟器装上自测点击不置顶 + 发消息 3s 后置顶

### 粟粟真机验证（按 research §六的 S-01 ~ S-09）

- [ ] **S-01 点击不置顶**：随便点列表里一条对话 → 返回 → 位置不变
- [ ] **S-02 发消息 3s 后置顶**：中间位置对话发消息 → 等 3s → 到顶
- [ ] **S-03 连续互动不抖动**：3s 内连发 3 条消息 → 前 3s 不动 → 最后一条 + 3s 到顶
- [ ] **S-04 下拉立即触发**：发消息后 1s 下拉 → 立刻到顶
- [ ] **S-05 rename 3s 后到顶**
- [ ] **S-06 贴纸加/删 3s 后到顶**（贴纸移动不触发）
- [ ] **S-07 切楼层 flush**
- [ ] **S-08 后台 flush**
- [ ] **S-09 从 chat 切回 sidebar 立即 flush**
- [ ] **S-10 toggleFavorite 不影响排序**（列表位置不变）
- [ ] **S-11 气泡软删除仍然立即刷新**（看得见气泡消失，不用等 3s）

---

## 文件改动总览

| 文件 | 改动 | 估计行数 |
|------|------|---------|
| `MemoryPalace/ViewModels/ConversationViewModel.swift` | +debounce 逻辑 / -点击副作用 / +5 处 markDirty | +20 / -2 |
| `MemoryPalace/Views/SidebarView.swift` | 3 处排序键简化 / rename 加 markDirty / 4 处 refreshable flush | +8 / -3 |
| `MemoryPalace/ViewModels/StickerViewModel.swift` | +callback property / 3-5 处调用 | +10 |
| `MemoryPalace/Views/CardFlowView.swift` | 注入 sticker callback | +5 |
| `MemoryPalace/Views/ContentView.swift` | +scenePhase / +切楼层 flush / +iOSPage 1→0 flush | +10 |

总计：**约 50-60 行改动**，不改 schema。

---

## Commit 策略

- **commit 1**: `feat: ConversationViewModel 加 markConversationDirty / flushPendingRefresh（debounce 骨架）`
- **commit 2**: `refactor: 去掉点击即置顶 — loadConversation 不刷 lastOpenedAt / 排序键只用 updateTime`
- **commit 3**: `feat: sendMessage / editAndResend / regenerate / rename 走 debounce 重排`
- **commit 4**: `feat: 贴纸加/删触发对话重排（StickerViewModel callback）`
- **commit 5**: `feat: 生命周期 flush — refreshable / 切楼层 / 后台 / chat→sidebar`

每个 commit 后 build + push。

---

## 风险与回撤

| 风险 | 处理 |
|------|------|
| `loadConversation` 去掉 `sidebarRefreshTrigger++` 后发现有隐含副作用（比如某个 UI 依赖） | 真机验证 S-01，若有回归再单独 trigger 需要的 UI 部分 |
| Rename 写 updateTime 导致旧导入数据的时间被覆盖 | Rename 是用户主动行为，覆盖语义正确 |
| 贴纸移动触发 callback 导致排序抖动 | Phase 7e checklist 明确只增删触发 |
| Timer 在 ViewModel dealloc 时没 cancel 导致泄漏 | `Task { [weak self] ... }` 已经 weak 持有，cancel-on-nil 自动处理 |
| 3s 太短仍有抖动 | 常量 `refreshDebounceSeconds` 集中在一处，好改 |

---

## 粟粟批注完、点头后我再动码。

# Research: 对话列表"延迟置顶"（点击不排、内容改 debounce 5s）

> 2026-04-19
> 对应 Roadmap 新项（粟粟刚提）

## 一、新诉求（粟粟确认版）

| 事件 | 旧行为 | 新行为 |
|------|--------|--------|
| 点击对话（进入） | 立刻置顶 | **不影响排序**（纯浏览不打乱列表） |
| 发消息 / 编辑 / 重生成 | `updateTime` 改了但列表要等下次刷新才能看到 | 标记 "pending 置顶"，**5 秒 debounce 后自动重排** |
| 改对话名 | title 改了但列表没刷 | 同上（5 秒后重排） |
| 加/改/删贴纸 | 完全不影响排序 | 同上（5 秒后重排） |
| 用户下拉刷新 | — | **立刻** flush 所有 pending 重排 |

核心约束：
- **debounce**（连续互动时 timer 重置，一直推迟到用户停下），不是 throttle
- app 后台/切楼层/关闭应用 → 保险起见**立刻 flush**（避免丢失 pending）
- 不能引入 schema 变更（成本高、SwiftData migration 风险）

## 二、现状架构拆解

### 2.1 `Conversation` 模型（`MemoryPalace/Models/Conversation.swift`）

```swift
var createTime: Date
var updateTime: Date      // ← 业务"最近更新"时间
var lastOpenedAt: Date?   // ← 业务"最近打开"时间
var title: String
...
```

### 2.2 列表排序（`SidebarView.swift`）

**3 处用相同排序键**（:1284, :1329, :1341）：
```swift
[SortDescriptor(\Conversation.lastOpenedAt, order: .reverse),
 SortDescriptor(\Conversation.updateTime,   order: .reverse)]
```

→ 主排序键是 `lastOpenedAt`，次键 `updateTime`。

**WorldBookPanelView 里另外 2 处**（:683, :702）也按 `lastOpenedAt DESC`，但那是"最近打开哪些对话"用来给用户挑选绑定世界书的 —— **那里的语义是对的**，不要改。

### 2.3 点击"立刻置顶"的根因

`ConversationViewModel.loadConversation()` (line 50-79)：
```swift
selectedConversation = conversation
conversation.lastOpenedAt = Date()   // ← 刷 lastOpenedAt
sidebarRefreshTrigger += 1            // ← 立刻通知 sidebar refetch
```

Sidebar 监听 `.onChange(of: viewModel.sidebarRefreshTrigger)` 里调 `refreshList()` → 重 fetch → `lastOpenedAt DESC` 排序 → 这个对话跳顶。

**所以"点击立刻置顶" = 上面两行的组合**。

### 2.4 真正内容改动的 mutation 点

| 事件 | 位置 | 现在的行为 |
|------|------|------------|
| 发消息（用户气泡 + AI 气泡） | `ConversationViewModel.sendMessage` :735 | `conversation.updateTime = Date()` — **不** trigger refresh |
| 发消息流结束后自动命名 | :762-767 | 改 title + `sidebarRefreshTrigger++` |
| 编辑用户消息重发 | `editAndResend` :888 | `updateTime = Date()` — **不** trigger refresh |
| 重生成 AI 回复 | `regenerate` :984 | `updateTime = Date()` — **不** trigger refresh |
| 重命名对话 | `SidebarView.swift:350-356`（rename TextField onSubmit） | **只改 title**，`updateTime` 不动、refresh 不触发 |
| 软删除气泡 | `softDelete` :485 | `node.isDeleted = true` + `sidebarRefreshTrigger++`（不改 updateTime）|
| 导入时 | `ImportSupport.swift:119-121` | `title + updateTime` 都从源文件取 |
| 贴纸 placement / note placement / 删贴纸 | `StickerViewModel` | **完全不碰 Conversation** |
| 收藏（favorite） | BubbleView.onToggleFavorite → viewModel | 只改 `node.isFavorite` |

关键发现：
1. **sendMessage / editAndResend / regenerate 本来就不触发 sidebar refresh**，所以"发完消息列表也不立刻动" —— 旧行为其实已经有一半的"延迟"了。粟粟看到的"立刻置顶"是**点击时 lastOpenedAt 冲顶**，不是发消息时冲顶。
2. **rename 根本没改 updateTime**，是纯 title 变动 —— 新逻辑要求 rename 也算内容改动，**需要加写 updateTime**。
3. **贴纸 placement 目前对排序毫无影响** —— 新诉求"贴纸变动影响排序"需要新增 hook。
4. **title 自动命名时已经有 `sidebarRefreshTrigger++`**（:767）—— 这是个"立刻 refresh"的 case，和 debounce 逻辑冲突，需要考虑是否保留。

### 2.5 `sidebarRefreshTrigger` 驱动的 refresh 流

- `ConversationViewModel.sidebarRefreshTrigger: Int`
- SidebarView `.onChange(of: viewModel.sidebarRefreshTrigger) { _, _ in refreshList() }`
- `refreshList()` → `loadConversations(offset: 0)` → `modelContext.fetch(descriptor)` → 赋给 `@State conversations` → SwiftUI 重新渲染列表

所以"刷新列表 = sidebarRefreshTrigger++"。这是我们 debounce 机制的唯一触发点。

### 2.6 现有 Pull-to-refresh

昨天我加的 `.refreshable { try? await Task.sleep(nanoseconds: 400_000_000) }`（4 个 ScrollView）——闭包现在只 sleep 给视觉反馈，**不 flush 任何状态**。要改成"flush pending → sleep"。

### 2.7 `lastOpenedAt` 的其它用途

全项目 grep：
- 排序（SidebarView 3 处 + WorldBookPanelView 2 处）
- `ImportConversationChange.swift`（import undo 的字段 snapshot）
- **没有 UI 直接显示** `lastOpenedAt`

所以：**从 SidebarView 的排序键里去掉它是安全的**（WorldBookPanelView 那俩保留，语义不同）。字段本身保留（import undo 需要）。

---

## 三、方案评估

### 方案 A：干掉 `lastOpenedAt` 排序键 + 手动 debounce Timer

**改动**：
1. `ConversationViewModel.loadConversation()` 去掉 line 56 `lastOpenedAt = Date()` + line 57 `sidebarRefreshTrigger++`（或至少 `sidebarRefreshTrigger++`，`lastOpenedAt` 本身可保留不影响排序）
2. `SidebarView` 3 处排序键改成只有 `updateTime DESC`
3. 新增 `ConversationViewModel.markConversationDirty(_ convId: String)`：
   - 把 convId 加入 `pendingDirtyIds: Set<String>`（其实只需要知道"有 dirty"就好，5 秒后一刀切刷新）
   - 取消旧 Task，起新 `Task.sleep(5_000_000_000)` → 到点后 `flushPendingRefresh()`
4. 新增 `flushPendingRefresh()`：`pendingDirtyIds.removeAll()` + `sidebarRefreshTrigger += 1` + `try? context.save()`
5. 调用点：
   - `sendMessage` / `editAndResend` / `regenerate` —— 在 `updateTime = Date()` 后加 `markConversationDirty(conversation.id)`
   - 自动命名（:762-767）—— 把 `sidebarRefreshTrigger += 1` 改成 `markConversationDirty(conversation.id)`（走同一个 debounce）
   - Rename（SidebarView:350-356）—— 加 `conversation.updateTime = Date()` + 回调 viewModel.markConversationDirty(conv.id)
   - StickerViewModel 的 placement/remove —— 查到 Conversation 后设 updateTime + markDirty
6. `.refreshable` 闭包：`viewModel.flushPendingRefresh(context:)` + 短 sleep 给视觉反馈
7. `scenePhase` .background / .inactive：flush
8. `ContentView.onChange(of: profileManager?.currentProfile.id)` 切楼层：flush

**影响面**：
- 5 个文件：`ConversationViewModel.swift` / `SidebarView.swift` / `StickerViewModel.swift` / `CardFlowView.swift`（refreshable 闭包）/ 可能 `ContentView.swift`（scenePhase）
- ~50-80 行改动

**风险**：
- 如果 app 崩溃、Timer 没 fire，pending 的 updateTime **没丢**（我们同步写 updateTime，只是 UI 没立刻刷）。下次启动 fetch 时就会按新 updateTime 排。✅ 数据安全
- Rename 加写 updateTime 是**行为变更**——用户以后看"最近对话"时 rename 会影响顺序。这是粟粟要的语义，✅。
- 贴纸加写 updateTime 是**行为变更**——贴个贴纸也会把对话往顶推。粟粟明确要的，✅。
- 自动命名走 debounce 后：首次发消息 5 秒才排到顶。用户发完消息等回复的时间通常 > 5s，体感无感。✅

**优点**：
- 改动相对集中（几个 hook 点）
- 不改 schema
- debounce 的意图清晰

### 方案 B：schema 加 `pendingDisplayOrderTime` 字段

每次改动先写 pending 字段，5 秒后才把 pending 合并到 `updateTime`。UI sort by `updateTime`（保持现状）。

**不推荐**：
- 需要 schema migration（风险）
- 20 万 node store 迁移慢
- 没增加太多 robustness（方案 A 已够）

### 方案 C：跨启动持久化 pending

用 UserDefaults 存 pending ids + 时间。用不到 —— 方案 A 的"同步写 updateTime，只延迟 UI refresh"已经无数据丢失风险。

**不推荐**：过度工程。

**选 A**。

---

## 四、方案 A 的设计细节

### 4.1 Debounce Timer 实现

```swift
// ConversationViewModel.swift
private var pendingRefreshTask: Task<Void, Never>?
private let debounceSeconds: UInt64 = 5_000_000_000  // 5s

func markConversationDirty() {
    pendingRefreshTask?.cancel()
    pendingRefreshTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if Task.isCancelled { return }
        await MainActor.run {
            self?.flushPendingRefresh()
        }
    }
}

func flushPendingRefresh() {
    pendingRefreshTask?.cancel()
    pendingRefreshTask = nil
    sidebarRefreshTrigger += 1
}
```

不需要存 "哪些对话 dirty" 的 Set —— 一次 refresh 就会按新的 `updateTime` 全量重排，非 dirty 的对话位置自然不变。

### 4.2 调用点

**ConversationViewModel 内**（同一 class，直接调）：
- `sendMessage` 末尾（已设 updateTime）→ `markConversationDirty()`
- 自动命名（:762-767）：删掉立即 trigger，换成 markDirty
- `editAndResend`、`regenerate` 末尾 → markDirty

**ConversationViewModel 外（需要 viewModel 引用）**：
- SidebarView rename（:350-356）→ viewModel.markDirty（需要 conversation + updateTime 改写；这里 SidebarView 已持有 viewModel：`var viewModel: ConversationViewModel`）
- StickerViewModel.placeSticker / placeNote / remove：
  - 选项 A：给 StickerViewModel 加 `onConversationDirty: ((String) -> Void)?` callback，由 CardFlowView 注入 → 转调 viewModel.markDirty
  - 选项 B：直接在 StickerViewModel 里拿到 conversation（要 inject modelContext）改 updateTime + send NotificationCenter
  - **选 A**更干净
  
### 4.3 自动命名的例外处理

自动命名（sendMessage 流完成后首条消息自动产生 title）当前是 `sidebarRefreshTrigger += 1` 立即 refresh。按新语义应该走 debounce（和其它改动一样），因为：
- 用户发消息后 5s 内列表不动，标题变化也等 5s 一起出现
- 若立刻 refresh，视觉上"我刚发的消息这个对话就跑到顶"，和"点击不置顶"的诉求冲突

→ 自动命名也用 `markConversationDirty()`。

### 4.4 App 生命周期 flush

**需要 flush 的场景**：
- Pull-to-refresh：已列入
- App 进后台（scenePhase == .background）
- App 切非活跃（scenePhase == .inactive）
- 切楼层（profileManager.currentProfile.id change）—— 楼层切换会切整个 store，pending timer 在旧 store 的 context 里无意义
- 退出前（app termination）—— iOS 不保证有时间执行，但 .background 时触发已覆盖

**不需要 flush 的场景**：
- 切 iOS tab（page 切换）：仍在同一 context，没必要
- 进入对话页：不需要（正好是"点击不排"的场景）

### 4.5 何时不启动 debounce

导入对话时：`ImportSupport.swift:121` 设 `conversation.updateTime = incoming.updateTime`（原始时间）。这不应该被 debounce（也不应 markDirty —— 一次导入可能涉及几百条对话，都标 dirty 会触发多次 sidebarRefreshTrigger 吗？我们的实现是单 Task 取消重启，最后只 fire 一次）。

但更干净的做法：**导入不走 markDirty**。导入完成后 ImportView 本身会 trigger refresh（SidebarView 有 `.onChange(of: showImporter) { if !showing { refreshList() } }`，:644）。

→ **只在 user-initiated 的 mutation 后 markDirty**。

---

## 五、风险 / 边界 case

| 场景 | 处理 |
|------|------|
| 用户 5 秒内连发多条消息 | Task 每次被取消重启，debounce 推迟到最后一条 + 5s |
| 用户 debounce 期间下拉刷新 | flush 立刻触发，cancel 挂起的 task |
| App 崩溃 | `updateTime` 已同步写入，下次启动 fetch 按新排序。Timer 丢失只影响"本次运行内是否已重 render"|
| Timer fire 时 SidebarView 已被释放（navigation 离开）| `sidebarRefreshTrigger += 1` 对 unobserved ViewModel 无副作用，SidebarView 重新 appear 时自动 fetch |
| 并发两个对话同时 dirty | debounce 取消-重建，一次刷新覆盖全部 |
| rename 和贴纸同时发生 | 同上 |
| 楼层切换期间 dirty 未 flush | 切楼层 onChange 里先 flush（旧 context）再切 |

---

## 六、验证计划

1. **S-01 点击不置顶**：随便点列表里一条对话 → 回列表 → 位置不变。
2. **S-02 发消息 5 秒后置顶**：在一条中间位置的对话发一条消息 → 等 5s → 列表里这条到顶。
3. **S-03 连续互动不抖动**：5 秒内连发 3 条消息 → 前 5s 列表不动 → 第 3 条发出 5s 后一次性到顶。
4. **S-04 下拉立即触发**：发消息后 2 秒下拉刷新 → 立刻到顶（不等剩余 3s）。
5. **S-05 rename 5 秒后到顶**：rename 一条对话 → 等 5s → 到顶。
6. **S-06 贴纸到顶**：在一条对话里贴一张贴纸 → 等 5s → 到顶。
7. **S-07 切楼层 flush**：在 pending 状态下切楼层 → 回原楼层 → 重排已生效。
8. **S-08 后台 flush**：发消息后 2 秒 app 切后台 → 重新激活 → 列表已排好。
9. **S-09 自动命名不立即乱序**：新对话首次发消息 → 5s 内标题虽变但位置不动（因为位置变化和标题合并在同一次 refresh 里）。

---

## 七、不决定 / 问粟粟

1. **收藏对话（toggleFavorite）是否算"内容改动"？** 我倾向**不算**（收藏是元数据，不是内容）。但粟粟可能觉得"我收藏了说明我刚在用它，应该往上提"。待确认。
2. **软删除气泡** 是"内容改动"吗？当前 `softDelete` 已经立刻 `sidebarRefreshTrigger += 1`（可能是为了从列表把气泡移走）—— 是否也走 debounce？我倾向**保留立刻刷新**（因为显示/隐藏逻辑，不是排序逻辑）。
3. **5 秒** 合适吗？粟粟已明确 5 秒。
4. **贴纸 remove** 也算内容改动吗？我倾向**算**（加和删都是变动）。待确认。
5. **pull-to-refresh 闭包里** 除了 flush 还要做啥？当前 400ms sleep 只给视觉反馈。flush 后要不要加额外 400ms 让转圈圈显示完整？建议保留 400ms。

---

## 八、下一步

粟粟审 research，回答问题 1-5。我写 `docs/plan-conv-debounce-sort.md`，拆 checklist 到 commit 级。然后再开工。

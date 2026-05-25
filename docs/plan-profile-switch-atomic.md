# Plan: 切楼层 VM 主动清旧 ref（回到 master 基准）

> 2026-04-22 凌晨 · 粟粟反馈："你至少得做到master那样功能正常吧？！"
> master 切楼层正常 = race 是**路线 C 重构引入的**：UIKit PagingViewController 里
> UIHostingController 持有 SwiftUI view tree，生命周期比 SwiftUI 原生 TabView 延迟，
> 旧 view.body 有机会在 SwiftData reset 后跑一次读到已 destroy 实例 → crash。
> 修法只需**让旧 VM 在切楼层前主动 nil out 旧 SwiftData 实例的 ref**，旧 body 即使
> 再跑也读到 nil，绕开 crash。最小改动，不动架构。

## 昨晚的两次 crash 证据（根因同源）

```
Crash A（无 race fix，B3 状态）:
  SwiftDataMemoryStore.listAll ← MemoryPanelView.refreshMemories ← onAppear

Crash B（race fix 后）:
  Conversation.id.getter ← CardFlowView.body ← SwiftUI pipeline
```

共通：切楼层瞬间 SwiftUI 让**旧 view tree 的某个路径跑最后一次 body**，该路径读了已被 `ModelContext.reset` 的 SwiftData 实例。打单点无效，必须从源头切断。

## 设计

### 核心时序

```
当前（有 race）：
  ProfileManager.switchTo {
      currentProfile = newProfile   ┐ 同一 run loop
      container = newContainer      ┘ 同步触发 SwiftUI 重建
  }
  → SwiftUI 在 .id() 变化后让旧 view 跑最后一次 body
  → 旧 view 读 viewModel.selectedConversation.id（或 fetch Memory）
  → 旧 Conversation 已被新 container 替换导致 reset
  → fatal

修完：
  ProfileManager.switchTo {
      // Step 1（同步）：通知所有持有旧 SwiftData 实例的对象主动清空引用
      NotificationCenter.post(profileWillSwitch)
      // Step 2（同步）：flip currentProfile，SwiftUI 开始重建 ContentView
      currentProfile = newProfile
      // Step 3（下一 run loop）：替换 container，旧 view 已 dismount 完毕
      DispatchQueue.main.async { container = newContainer }
  }
```

### 关键保证

- **Step 1** → VM 主动 `selectedConversation = nil` / `currentPath = []` / `memories = []` → 旧 Conversation 实例失去 VM retain → view.body 再读 `viewModel.selectedConversation?.id` 拿到 nil，**不触及已 destroy 实例**
- **Step 2** → ContentView.id(profile.id) 变，ContentView 整棵进入 dismount phase
- **Step 3** → 下一 run loop 时，SwiftUI dismount + SwiftData reset 顺序可控：旧 view 先 dismount 释放 env retain，再换 container 触发 reset，避开"旧 view + 已 reset 实例"中间态

中间有一 tick 的"新 ContentView 用旧 container 读新 profile.id" — 此时旧 store 没有新 profile 的 Memory → 返回空数组，**不 crash**。下一 tick container 换成新的，SwiftUI 再刷一次即正确数据。

## 改动清单

### 1. 新增通知 + ProfileManager 异步化

**`MemoryPalaceApp.swift`**（单文件改动）：

```swift
extension Notification.Name {
    /// ProfileManager.switchTo 即将切换前发出。订阅者应立即清空对旧 SwiftData
    /// 实例的所有 retain（例如 ConversationViewModel.selectedConversation = nil），
    /// 避免切楼层瞬间 SwiftUI dismount phase 的旧 view.body 访问已 reset 的实例。
    static let profileWillSwitch = Notification.Name("MemoryPalaceProfileWillSwitch")
}

func switchTo(_ profile: Profile) {
    guard profile.id != currentProfile.id else { return }
    UserDefaults.standard.set(profile.id, forKey: "lastProfileId")
    UserDefaults.standard.set(profile.userName, forKey: "userName")
    UserDefaults.standard.set(profile.assistantName, forKey: "assistantName")

    // Step 1: 通知订阅者清空旧 SwiftData 实例引用
    NotificationCenter.default.post(name: .profileWillSwitch, object: nil)

    // Step 2: flip currentProfile，触发 ContentView.id(profile.id) 重建
    currentProfile = profile

    // Step 3: 下一个 run loop 再换 container，让旧 ContentView 先 dismount 完毕
    DispatchQueue.main.async { [weak self] in
        self?.container = Self.makeContainer(for: profile)
    }
}
```

### 2. ConversationViewModel 订阅 + 清空

**`ConversationViewModel.swift`**：

```swift
init() {
    NotificationCenter.default.addObserver(
        forName: .profileWillSwitch, object: nil, queue: .main
    ) { [weak self] _ in
        guard let self else { return }
        self.selectedConversation = nil
        self.currentPath = []
        self.branchChoices.removeAll()
        self.bubbledBranches.removeAll()
        self.nodeMap.removeAll()
        self.effectiveChildrenMap.removeAll()
        self.branchInfoMap.removeAll()
        self.cachedRootId = nil
        self.pinnedNodes = []  // 如果有
        self.pendingRefreshTask?.cancel()
        self.pendingRefreshTask = nil
    }
}

deinit {
    NotificationCenter.default.removeObserver(self)
}
```

### 3. StickerViewModel 订阅 + 清空

**`StickerViewModel.swift`**：

```swift
init() {
    NotificationCenter.default.addObserver(
        forName: .profileWillSwitch, object: nil, queue: .main
    ) { [weak self] _ in
        guard let self else { return }
        self.placedStickers = []
        self.stickerAssets = []
        self.bubblePositions.removeAll()
        self.selectedPlacedStickerId = nil
        self.isEditingStickers = false
    }
}

deinit {
    NotificationCenter.default.removeObserver(self)
}
```

### 4. MemoryPanelView / MemorySettingsTab 订阅 + 清空 @State

View 里的 @State 由 SwiftUI 管，VM 那套 observer 方式不适用。改用 `.onReceive`：

```swift
.onReceive(NotificationCenter.default.publisher(for: .profileWillSwitch)) { _ in
    memories = []
}
```

位置：MemoryPanelView.swift:180（挂在 `.onAppear` 附近）、MemorySettingsTab.swift:219 和 544 同样补上。

### 5. 不动

- 不改 `.onAppear { refreshMemories() }` → `.task(id:)`（昨晚被证伪）
- 不动 `MemoryPalaceApp.body` 里 `.modelContainer()` + `.id()` 顺序
- 不动 CardFlowView / ContentView / PagingContainerView 任何内容

## 实施 checklist

- [ ] **Step 1**: 在 `MemoryPalaceApp.swift` 加 `Notification.Name.profileWillSwitch` 定义
- [ ] **Step 2**: 改 `ProfileManager.switchTo` 为 3 步异步
- [ ] **Step 3**: `ConversationViewModel.init` 加 observer + deinit remove
- [ ] **Step 4**: `StickerViewModel.init` 加 observer + deinit remove
- [ ] **Step 5**: `MemoryPanelView` + `MemorySettingsTab ×2` 加 `.onReceive` 清 memories
- [ ] **Step 6**: xcodebuild pass + 0 error
- [ ] **Step 7**: commit + push
- [ ] **Step 8**: 粟粟真机验证

## 真机验证

**核心**：
- [ ] 聊天页 → 切楼层 → **不 crash** ✓（根治）
- [ ] 切楼层后 chat page 显示新楼层（内容正确，没有旧楼层残留）
- [ ] memory panel / sticker library 显示新楼层的数据
- [ ] 切楼层期间有没有"空白一瞬间" — 可接受的轻微中间态 vs 明显闪屏

**回归**：
- [ ] 启动速度正常（不像昨晚 10+ 秒）
- [ ] 流式响应 ChatInputBar.body ~1（B3 不 break）
- [ ] `[PERF] updatePages skip (streaming)` 流式期间打印（B2 窄不 break）
- [ ] 切对话、发消息、翻页、键盘都正常

## 失败兜底

如果切楼层还 crash，stack trace 发过来。可能：
- observer 时机不对 → notification 在 currentProfile flip 之前 fire 但 VM 没来得及处理
- 某处持有旧 SwiftData 实例但没订阅 notification
- 中间 tick 的"新 ContentView 用旧 container" 触发别的 race

**最坏兜底**：Notification 改成 `NotificationCenter.default.post + DispatchQueue.main.sync` 确保订阅者处理完才继续；或者在 currentProfile flip 之前插 `try? await Task.sleep(nanoseconds: 1_000_000)` 让 notification 真正 dispatch 完。

## 过目点

- [ ] 3 步时序（notify → flip currentProfile → async flip container）你 OK 吗？
- [ ] `.onReceive` 清 @State memories 的写法 OK？还是觉得 View 层应该干净点、只让 VM 清？
- [ ] 启动慢 10+ 秒的猜测（`.task(id:)` 初始 nil profileManager 跑多次）合理吗？这个方案不用 `.task(id:)`，启动应该恢复正常
- [ ] 一个 commit 带 plan + 代码 + 真机测（B3 pattern）

批注完动手。

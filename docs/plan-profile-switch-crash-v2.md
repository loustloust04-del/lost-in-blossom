# Plan: 切楼层 crash 路线 A —— 补齐 plan-v1 漏的三步

> 基于 `docs/research-profile-switch-crash-v2.md`
> 路线 A：不动路线 C 架构，只补齐 commit `7cb7601` 相对 `plan-profile-switch-atomic.md` 漏的**3 个**关键点。
> 如果路线 A 修完粟粟真机还 crash，再上路线 B（研究里的 @Model ref 扫盲）。

## 0. xcdoc 事实校准（为什么 plan-v1 → 7cb7601 fix 有漏）

### ✅ `addObserver(forName:object:queue:using:)` 的 `queue` 参数语义

[xcdoc 原文](/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:))：

> **queue**: The operation queue where the `block` runs.
> **When `nil`, the block runs synchronously on the posting thread.**

plan-v1 写"Notification 同步 dispatch，observer 处理完才返回"—— 语义上对应 `queue: nil`。
**但** 7cb7601 的 3 个 observer（ConversationViewModel / PagingViewController / MemoryPanelView onReceive / MemorySettingsTab onReceive）全用 `queue: .main` 或 Combine publisher —— 是**异步**（操作排队到 `OperationQueue.main`，下一拍 run loop 才 drain）。

结果：`switchTo` 里 `post(.profileWillSwitch)` 立即返回，observer 块没跑，随后 `currentProfile` + `container` 已 flip → observer 才在下一拍跑 → **clear 跑在 container flip 之后**，旧 body 在 container reset 时已经是 race 窗口中段了。

### ✅ 7cb7601 `switchTo` 同步 flip container（plan-v1 step 2 偏差）

plan-v1：
```swift
// Step 3（下一 run loop）：替换 container
DispatchQueue.main.async { [weak self] in
    self?.container = Self.makeContainer(for: profile)
}
```

7cb7601 实际（MemoryPalaceApp.swift:139-142）：
```swift
NotificationCenter.default.post(name: .profileWillSwitch, object: nil)
currentProfile = profile
container = Self.makeContainer(for: profile)   // 同一 run loop 同步
```

`body #5` 和 `body #6` 相差 1ms 就是同一 run loop 两次 SwiftUI 重算的证据。

### ✅ `StickerViewModel` observer 整步漏（plan-v1 step 4）

plan-v1 step 4 写要在 `StickerViewModel.init` 加 observer 清 `placedStickers` / `stickerAssets` 等。**7cb7601 没做**。

`StickerViewModel.placedStickers: [PlacedSticker]` / `stickerAssets: [StickerAsset]` 都是 **@Model**。切楼层时旧 `StickerCanvasLayer.body` 在 dismount 最后一拍 `ForEach(stickerVM.placedStickers, id: \.id)` → 读已 destroy 的 `sticker.id` → **fatal 候选**（路径和 plan-v1 "Crash B: Conversation.id ← CardFlowView.body" 同构）。

## 1. 修法（3 个小改动）

### Step A：所有 observer 改 `queue: nil` 实现真同步

**文件**：`MemoryPalace/ViewModels/ConversationViewModel.swift:43-44`

```diff
-        NotificationCenter.default.addObserver(
-            forName: .profileWillSwitch, object: nil, queue: .main
-        ) { [weak self] _ in
+        NotificationCenter.default.addObserver(
+            forName: .profileWillSwitch, object: nil, queue: nil
+        ) { [weak self] _ in
```

原因：`queue: nil` 让 observer block 同步在 posting 线程（也就是 main）跑。post() 返回时清理已完成。

注：`.onReceive(NotificationCenter.default.publisher(for:))` 这种 Combine 形式**不能改 queue**（Combine 的 publisher 默认 receive(on: runLoop.main) 类似异步）。但 `.onReceive` 的 block 修改 `@State` 会由 SwiftUI 正确调度——次要的 async 时序对 @State 清 Memory 不致命（Memory panel 切楼层时不一定在 active 的 sub-tree 里）。重点看 ConversationViewModel 和 StickerViewModel 同步。

**文件**：`MemoryPalace/Views/Paging/PagingViewController.swift:122-124`

```diff
         NotificationCenter.default.addObserver(
             self, selector: #selector(handleProfileWillSwitch),
-            name: .profileWillSwitch, object: nil)
+            name: .profileWillSwitch, object: nil)
```

这个用的是 `addObserver(_:selector:name:object:)` 老式 API，**默认就是同步在 post 线程跑**（xcdoc 确认：`addObserver(_:selector:name:object:)` 不接收 queue 参数，block 在 post 线程同步 deliver）。✅ 这个已经是 sync 的。

### Step B：`ProfileManager.switchTo` container swap 挂 `DispatchQueue.main.async`

**文件**：`MemoryPalace/MemoryPalaceApp.swift:127-143`

```diff
     func switchTo(_ profile: Profile) {
         guard profile.id != currentProfile.id else { return }
         UserDefaults.standard.set(profile.id, forKey: "lastProfileId")
         UserDefaults.standard.set(profile.userName, forKey: "userName")
         UserDefaults.standard.set(profile.assistantName, forKey: "assistantName")

-        // 切楼层前通知所有持有旧 SwiftData 实例的对象（ConversationViewModel /
-        // PagingViewController / MemoryPanelView 等）主动清空引用。...
-        NotificationCenter.default.post(name: .profileWillSwitch, object: nil)
-
-        currentProfile = profile
-        container = Self.makeContainer(for: profile)
+        // Step 1 (sync): notify 订阅者清旧 SwiftData ref（queue:nil 确保同步）
+        NotificationCenter.default.post(name: .profileWillSwitch, object: nil)
+
+        // Step 2 (sync): flip currentProfile → ContentView.id(profile.id) 变，SwiftUI
+        // 在下一拍 dismount 整棵旧 ContentView
+        currentProfile = profile
+
+        // Step 3 (async): 下一 run loop 才 flip container，让旧 view tree 先 dismount 完
+        // 完毕后再 reset SwiftData store。避开"旧 view + 新 container（或正在 reset）"中间态。
+        DispatchQueue.main.async { [weak self] in
+            self?.container = Self.makeContainer(for: profile)
+        }
     }
```

中间态后果：下一拍 run loop 之前，有大约 1 tick（~16ms @60fps）的"新 profile.id + 旧 container"状态。此时：
- 新 ContentView 用旧 container 渲染，body 里 `@Query(...)` 读旧 store 数据 → 显示**旧楼层** Conversation 列表 **1 帧**。
- 接着 container = newContainer，ContentView 再 rebuild 一次，显示新楼层。

视觉上可能看到一瞬间"旧对话列表 → 空/新对话列表"闪烁。acceptable：plan-v1 原文承认了这个 trade-off："下一 tick container 换成新的，SwiftUI 再刷一次即正确数据"。

### Step C：`StickerViewModel.init` 加 observer 清 @Model ref

**文件**：`MemoryPalace/ViewModels/StickerViewModel.swift`

在 class 顶部（`@ObservationIgnored var undoStack` 之后）加：

```swift
// MARK: - Profile Switch Race Defense
//
// 切楼层（ProfileManager.switchTo）会 reset modelContainer → 旧 PlacedSticker /
// StickerAsset @Model 实例 destroy。路线 C 下旧 StickerCanvasLayer.body 在 dismount
// 最后一拍会 iterate placedStickers / stickerAssets → 读 `.id` → fatal。
//
// 修法：post .profileWillSwitch 时同步清所有 @Model ref。queue:nil 确保同步在
// posting（main）线程跑，observer 返回后 currentProfile/container 才 flip。
// Plan: docs/plan-profile-switch-crash-v2.md
private var profileSwitchObserver: NSObjectProtocol?

init() {
    profileSwitchObserver = NotificationCenter.default.addObserver(
        forName: .profileWillSwitch, object: nil, queue: nil
    ) { [weak self] _ in
        guard let self else { return }
        self.placedStickers = []
        self.stickerAssets = []
        self.selectedPlacedStickerId = nil
        self.renamingStickerId = nil
        self.editingNoteStickerId = nil
        self.copiedSnapshot = nil
        self.undoStack.removeAll()
        self.stickerSizes.removeAll()
        self.bubblePositions.removeAll()
    }
}

deinit {
    if let observer = profileSwitchObserver {
        NotificationCenter.default.removeObserver(observer)
    }
}
```

**注意**：`StickerUndoSnapshot` 是 struct（value type，只含 UUID + Double ×4），清 `undoStack` 不是 @Model 防御目的，是"切楼层语义上 undo 栈应该清"的正确性。

**注意**：现有 `onConversationMutated` 回调是 `@ObservationIgnored` 的 closure，切楼层时 CardFlowView 重 mount 后会重新设，这里不清。

### Step D（辅助）：也把 `ConversationViewModel` 的 observer token 存起来显式 `removeObserver`

现行代码 `ConversationViewModel.deinit { NotificationCenter.default.removeObserver(self) }` 但 `addObserver(forName:object:queue:using:)` **返回**的是 token（不是 self）—— `removeObserver(self)` 在这种 block-based observer 上**不生效**（只对 `addObserver(_:selector:name:object:)` 生效）。

xcdoc 原文（[addObserver(forName:object:queue:using:)](/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:))）：

> Return Value: An opaque object to act as the observer. Notification center strongly holds this return value until you remove the observer registration.

意思是 Notification center **强持有** 这个返回的 token，除非显式 removeObserver(token)。现行代码漏存 token，observer 跟着 VM deinit 被泄漏（但由于 `[weak self]` 不会 keep VM alive，实际效果是 observer block 里 self=nil，guard let self 直接 return —— **泄漏但不 crash**，可接受但不干净）。

**修法**（顺手修干净）：

```diff
+    private var profileSwitchObserver: NSObjectProtocol?
+
     init() {
-        NotificationCenter.default.addObserver(
-            forName: .profileWillSwitch, object: nil, queue: .main
+        profileSwitchObserver = NotificationCenter.default.addObserver(
+            forName: .profileWillSwitch, object: nil, queue: nil
         ) { [weak self] _ in
             guard let self else { return }
             ...
         }
     }

     deinit {
-        NotificationCenter.default.removeObserver(self)
+        if let observer = profileSwitchObserver {
+            NotificationCenter.default.removeObserver(observer)
+        }
     }
```

### Step E：加 [PROBE] 探针跟踪时序

只是为了验证修法对 —— 如果 log 里顺序不对（比如 VM clear 在 container flip 之后），可以立刻看出来。全修完再 revert 探针。

**`MemoryPalaceApp.swift switchTo`**：

```swift
func switchTo(_ profile: Profile) {
    guard profile.id != currentProfile.id else { return }
    print("[PROBE switch] enter t=\(CFAbsoluteTimeGetCurrent()) from=\(currentProfile.id) to=\(profile.id)")
    UserDefaults.standard.set(profile.id, forKey: "lastProfileId")
    // ... userName / assistantName
    print("[PROBE switch] before post")
    NotificationCenter.default.post(name: .profileWillSwitch, object: nil)
    print("[PROBE switch] after post (observers done if sync)")
    currentProfile = profile
    print("[PROBE switch] after flip currentProfile")
    DispatchQueue.main.async { [weak self] in
        print("[PROBE switch] async: before flip container")
        self?.container = Self.makeContainer(for: profile)
        print("[PROBE switch] async: after flip container")
    }
}
```

**`ConversationViewModel.init` observer**：

```swift
NotificationCenter.default.addObserver(forName: .profileWillSwitch, object: nil, queue: nil) { [weak self] _ in
    print("[PROBE vm-clear] enter")
    guard let self else { print("[PROBE vm-clear] self nil"); return }
    self.selectedConversation = nil
    // ...
    print("[PROBE vm-clear] done")
}
```

**`StickerViewModel.init` observer**：

```swift
NotificationCenter.default.addObserver(forName: .profileWillSwitch, object: nil, queue: nil) { [weak self] _ in
    print("[PROBE sticker-clear] enter")
    guard let self else { print("[PROBE sticker-clear] self nil"); return }
    // ...
    print("[PROBE sticker-clear] done")
}
```

**`PagingViewController.handleProfileWillSwitch`**：

```swift
@objc private func handleProfileWillSwitch() {
    print("[PROBE paging-clear] enter")
    for hc in hostingControllers {
        hc.rootView = AnyView(Color.clear)
    }
    print("[PROBE paging-clear] done hcs=\(hostingControllers.count)")
}
```

**预期 log 顺序**（修对了应该这样）：

```
[PROBE switch] enter t=... from=X to=Y
[PROBE switch] before post
[PROBE vm-clear] enter        ← sync observer 先
[PROBE vm-clear] done
[PROBE sticker-clear] enter   ← 多 observer 顺序可能变
[PROBE sticker-clear] done
[PROBE paging-clear] enter
[PROBE paging-clear] done hcs=3
[PROBE switch] after post (observers done if sync)
[PROBE switch] after flip currentProfile
[PERF] ContentView.body #N    ← SwiftUI reconcile，用新 profile.id
[PROBE switch] async: before flip container
[PROBE switch] async: after flip container
[PERF] ContentView.body #N+1  ← 用新 container 再刷
```

**不对的征兆**：
- `[PROBE switch] after post` 先于 `[PROBE vm-clear] enter` → queue:nil 没生效 or async 了
- body 在 `[PROBE vm-clear] done` 之前跑 → SwiftUI 用旧 VM 状态渲染
- fatal error 打出来 → 看 fatal 在哪一行，hypothesis 要 revise

## 2. 实施 checklist（按顺序做，每步 build 验证）

- [ ] **E1**：加探针（5 个 probe 点），先跑一次看现行行为（revalidate hypothesis）
- [ ] **E2**：build 验证探针无语法错
- [ ] **A**：ConversationViewModel observer `queue: .main` → `queue: nil` + 存 token + 清干净 removeObserver
- [ ] **B**：ProfileManager.switchTo container swap 挂 `DispatchQueue.main.async`
- [ ] **C**：StickerViewModel.init 加 observer + deinit removeObserver
- [ ] **build**：xcodebuild iOS sim 通过
- [ ] **install+launch 模拟器**：log 抓满
- [ ] **verify probe 顺序**：符合预期（见上）
- [ ] **verify no fatal**：模拟器切楼层不 crash（我尝试用 cliclick 触发，不通就挂 probe 让粟粟真机复现）
- [ ] **revert 探针**：全通后撤 [PROBE] prints
- [ ] **final build + commit + push**

## 3. 路线 B（兜底）—— 若 A 修完还 crash

按 research 里未盘的 @Model ref：

- [ ] `WorldBookPanelView.worldBooks: @State [WorldBook]` + `renamingBook` / `deletingBook` 加 `.onReceive(...)` 清
- [ ] `CharacterCardManager.cards: [UserCard]` 若是 @Observable → 加 observer（或让 CardLibraryPanelView onReceive 清 @State 缓存）
- [ ] 其他 fetch 缓存扫盲

## 4. 备注

- 若修完再 crash，stack trace 得抓（粟粟真机跑带探针版本，crash 后 Xcode Debug Navigator 截图给我）
- 自动化在模拟器上 tap 跑不通（cliclick / osascript 权限问题），但 build + install + launch 没问题。探针 log 能看到完整时序，比真手动点更能定位
- 不动路线 C 架构（重构风险太大，上一个 postmortem 证明路线 C 的键盘 / 壁纸 / 环境已经很脆）

动手。

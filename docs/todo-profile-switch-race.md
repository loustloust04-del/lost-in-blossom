# TODO: 切楼层时 SwiftData fatal race

> 2026-04-22 观察
> 优先级：TestFlight 后处理（非 block）
> 触发分支：`codex/theme-kelivo-settings`，但 race 可能 master 也有只是窗口窄

## 现象

粟粟真机切楼层时日志炸：

```
SwiftData/BackingData.swift:835: Fatal error: This model instance was destroyed
by calling ModelContext.reset and is no longer usable.
PersistentIdentifier(id: SwiftData.PersistentIdentifier.ID(backing:
  SwiftData.PersistentIdentifier.PersistentIdentifierBacking.managedObjectID(
    0x950f69efbf4ab5be <x-coredata://91F689CF-7965-4425-9A76-2503D91B7A65/Conversation/p2>)))
```

伴随：
```
Adding '_UIReparentingView' as a subview of UIHostingController.view is not supported
and may result in a broken view hierarchy.
```
（3 条，典型 UIKit 视图层 reparent 抱怨）

## 触发链路（假设）

1. 粟粟切楼层 → `ProfileManager.currentProfile = newProfile` (@Observable)
2. `MemoryPalaceApp` 的 body 重算，给 ContentView 注入新的 `modelContext`（新 profile 独立 store）
3. `.id(profile.id)` 触发 ContentView 销毁 + 重建
4. **销毁前的最后一次 ContentView.body** 里，旧 `viewModel.selectedConversation` 的 `PersistentIdentifier` 属于**旧 store**，但此时 environment 的 `modelContext` 已经是**新 store**
5. `updateUIViewController` 被调 → `updatePages` 构造新的 `chatPage: AnyView` → AnyView 里访问 `viewModel.selectedConversation` → 用新 modelContext 访问旧 PersistentIdentifier → fatal error

## 为什么 B3 没炸 B2a 炸了？

推测：
- **B3**：updatePages 每次 parent body 都刷，race 窗口很窄，SwiftUI 可能借每次重刷把 root 换成新状态来"重置" graph 依赖
- **B2a**：skip 了很多中间 update，让某次 body 正好落在"modelContext 已换但 viewModel 还在旧 store"的中间态时间被拉长 → 触发
- master 分支（无路线 C / 无 UIHostingController 嵌套）可能也有这个潜在 race，只是 TabView 下 SwiftUI 结构 diff 能自愈

## 修法方向（待调研）

**方向 A**：切楼层前先 `viewModel.selectedConversation = nil` + `viewModel.currentPath = []`，断开对旧 store 的引用，再 flip profile
- 侵入点：ProfileManager 切换逻辑
- 风险：时机难把握，多 state 要按序清

**方向 B**：`MemoryPalaceApp` 给 ContentView 挂 `.id(profile.id)` 的位置再加一层"safe unmount wrapper"，销毁时强制清 viewModel
- SwiftUI 原生没有"销毁前 hook"，得靠 `.onDisappear` 或容器
- 不确定能否根治 race window

**方向 C**：每个 profile 独立 ConversationViewModel，通过 `.task(id: profile.id)` 启动新 VM，而不是让同一个 VM 跨 profile
- 架构级改动
- 最干净，但牵涉广

## 复现步骤

1. 打开 app 到 `5969260F-B55A-4589-83D0-D7B215752098` 对话
2. 随便操作几下（打字 / 发消息 / 放贴纸）
3. sidebar 切楼层（或 settings 切 profile）
4. crash

## 相关日志片段

参见 2026-04-22 凌晨 B2a 真机测试日志（commit `0bc1e24` 已 revert）。

## 关联 commit

- `0bc1e24` perf(iOS): PagingContainerView signature bump（引发 race 暴露）
- `56e38a0` Revert B2a

## 下一步

TestFlight 后专门开一个 research + plan，从 MemoryPalaceApp 的 profile 切换流程开始翻。

# 任务：震动校准 + 滚动节流 + 复制震动反馈

读 CLAUDE.md。不要引入 regression。

## Task 1: 震动反馈校准

文件：`MemoryPalace/ViewModels/ConversationViewModel.swift`

当前代码在思考状态变化时用了 UIImpactFeedbackGenerator(.soft) 和 (.rigid)。需要改为：

### 1a: 思考开始（约第1304行附近）
把 `UIImpactFeedbackGenerator(style: .soft).impactOccurred()` 改为：
```swift
UINotificationFeedbackGenerator().notificationOccurred(.success)
```

### 1b: 思考结束（约第1328行附近）
把 `UIImpactFeedbackGenerator(style: .rigid).impactOccurred()` 改为：
```swift
UINotificationFeedbackGenerator().notificationOccurred(.warning)
```

### 1c: 思考脉搏（新增）
在 AI 思考期间（`isThinking == true` 的整个过程中），每 1.5 秒触发一次轻微震动：
```swift
UISelectionFeedbackGenerator().selectionChanged()
```
用一个 Timer，isThinking 变 true 时启动，变 false 时停止。

## Task 2: 滚动节流

文件：`MemoryPalace/Views/ContentView.swift`

### 2a: streaming 自动滚动节流
找到 AI streaming 时触发 scrollTo 的代码。如果每个 token 都触发 scrollTo，加节流：
- 用一个 `lastScrollTime` 属性记录上次滚动时间
- 只有距离上次滚动超过 0.3 秒才执行新的 scrollTo
- 确保 streaming 结束时执行最后一次 scrollTo（不丢失末尾）

### 2b: scrollToLastMessage 动画
确保 scrollTo 使用平滑动画：
```swift
withAnimation(.easeOut(duration: 0.25)) {
    proxy.scrollTo(targetId, anchor: .bottom)
}
```

## Task 3: 复制震动反馈

当用户通过长按选择并复制消息文本时，触发震动反馈。

在 CardFlowView.swift 中，给 `.textSelection(.enabled)` 的 View 加上 `.onReceive` 监听剪贴板变化：
```swift
.onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}
```
这样每次用户复制文本时都会触发一次震动。

---

一个 commit：`fix: haptic calibration + scroll throttle + copy haptic feedback`

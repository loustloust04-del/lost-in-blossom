# 任务：双模式震动反馈系统

读 CLAUDE.md。不引入 regression。

## 背景

实现两种震动反馈风格，用户在设置里切换。参考 ChatGPT 和 Claude iOS 官方 App 的做法。

## 架构

### 新建 HapticService.swift（放在 Services/ 下）

```swift
import UIKit

enum HapticMode: String, CaseIterable {
    case off = "off"
    case typewriter = "typewriter"  // ChatGPT 风格
    case minimal = "minimal"        // Claude 风格
}

class HapticService {
    static let shared = HapticService()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    
    var mode: HapticMode {
        get { HapticMode(rawValue: UserDefaults.standard.string(forKey: "hapticMode") ?? "typewriter") ?? .typewriter }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hapticMode") }
    }
    
    // 预热 Taptic Engine（在即将触发前调用，减少延迟）
    func prepare() {
        impactLight.prepare()
        selection.prepare()
    }
    
    // ═══ ChatGPT 模式专用 ═══
    
    /// streaming 时每个 token chunk 到达时调用
    /// 需要节流：内部控制最少间隔 50ms，避免过于密集
    private var lastTypewriterTime: TimeInterval = 0
    
    func streamingTick() {
        guard mode == .typewriter else { return }
        let now = CACurrentMediaTime()
        guard now - lastTypewriterTime > 0.05 else { return } // 50ms 节流
        lastTypewriterTime = now
        impactLight.impactOccurred(intensity: 0.4) // 轻，40% 强度
    }
    
    /// streaming 结束时调用
    func streamingComplete() {
        guard mode == .typewriter else { return }
        notification.notificationOccurred(.success)
    }
    
    // ═══ Claude 模式专用 ═══
    
    /// 发送消息时
    func sendMessage() {
        guard mode == .minimal else { return }
        impactMedium.impactOccurred()
    }
    
    // ═══ 两种模式共用 ═══
    
    /// 复制文本时
    func copyText() {
        guard mode != .off else { return }
        notification.notificationOccurred(.success)
    }
    
    /// 删除操作（标签删除、消息删除）
    func deleteAction() {
        guard mode != .off else { return }
        notification.notificationOccurred(.warning)
    }
    
    /// UI 导航（页面切换、侧边栏）
    func navigation() {
        guard mode != .off else { return }
        selection.selectionChanged()
    }
    
    /// 长按菜单出现
    func longPress() {
        guard mode != .off else { return }
        impactRigid.impactOccurred()
    }
}
```

## Task 1: 创建 HapticService

按上面的代码创建 `MemoryPalace/Services/HapticService.swift`。

关键设计：
- `streamingTick()` 有 50ms 内置节流，防止每个字符都震导致手机疯狂抖动
- `impactOccurred(intensity: 0.4)` 用 40% 强度，比默认更轻柔
- ChatGPT 模式只在 streaming 时震 + streaming 结束震一次
- Claude 模式只在用户主动操作时震（发送、导航、复制、删除）
- off 模式全部静默

## Task 2: 接入 streaming 震动

文件：`MemoryPalace/ViewModels/ConversationViewModel.swift`

找到 streaming 的 `onToken` 回调（每个 token 到达时触发的闭包）。在里面加：
```swift
HapticService.shared.streamingTick()
```

找到 streaming 完成的位置（`onComplete` 回调）。在里面加：
```swift
HapticService.shared.streamingComplete()
```

**删除之前的思考状态震动代码**（UIImpactFeedbackGenerator(.soft) 和 (.rigid) 和思考脉搏 Timer）。全部替换为 HapticService 的调用。

## Task 3: 接入操作震动

在以下位置加 HapticService 调用：

- **发送消息**（用户点发送按钮时）：`HapticService.shared.sendMessage()`
- **复制文本**（已有的 UIPasteboard 监听处）：`HapticService.shared.copyText()`
- **删除标签**（swipeActions 的 delete 触发时）：`HapticService.shared.deleteAction()`
- **侧边栏切换**（selectTab 切换时）：`HapticService.shared.navigation()`
- **页面滑动切换**（page 切换时）：`HapticService.shared.navigation()`

## Task 4: 设置页面

文件：`MemoryPalace/Views/AppearanceSettingsTab.swift`（或适合的设置页）

加一个 Section "震动反馈"，包含三个选项的 Picker：
```swift
Section("震动反馈") {
    Picker("模式", selection: Binding(
        get: { HapticService.shared.mode },
        set: { HapticService.shared.mode = $0 }
    )) {
        Text("关闭").tag(HapticMode.off)
        Text("打字机（ChatGPT 风格）").tag(HapticMode.typewriter)
        Text("精简（Claude 风格）").tag(HapticMode.minimal)
    }
    .pickerStyle(.inline)
    
    switch HapticService.shared.mode {
    case .off:
        Text("不触发任何震动反馈")
    case .typewriter:
        Text("AI 回复时随文字输出轻微震动，回复完成时震动提示")
    case .minimal:
        Text("仅在发送消息、复制、删除等操作时提供触觉反馈")
    }
}
```

默认选中 `typewriter`（ChatGPT 风格）。

---

一个 commit：`feat: dual-mode haptic feedback system (typewriter + minimal)`

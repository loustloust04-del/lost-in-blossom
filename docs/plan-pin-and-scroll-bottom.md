# Plan: Pin 消息 + 回底按钮

> 2026-04-20 | 基于 `research-pin-and-scroll-bottom.md`
> 对应 roadmap **E6 快速回顶/回底**

---

## 目标

- `MessageNode` 加 pin 状态
- 顶部 Pin Bar（多 pin 轮换，学 TG）
- 右下玻璃 `↓` 回底按钮
- iOS 长按消息菜单加"钉住"；macOS hover 按钮加 pin

**不做**：回顶按钮；完整 Pin 列表页；跨分支自动切换（pin 节点不在当前 path 时弹 toast）。

---

## 文件改动总览

| 文件 | 类型 | 估计行数 |
|---|---|---|
| `Models/Conversation.swift` | 改（MessageNode 加字段） | +3 |
| `ViewModels/ConversationViewModel.swift` | 改（加 togglePin / pinnedNodes） | +40 |
| `Views/CardFlowView.swift` | 改（contextMenu / HoverButtons / overlay） | +80 |
| `Views/PinnedMessageBar.swift` | **新建** | ~180 |
| `Views/ScrollToBottomButton.swift` | **新建** | ~70 |

**总计：~370 行**

---

## Task Checklist

### Task 1：MessageNode 加 pin 字段（0.5h）

**文件**：`MemoryPalace/Models/Conversation.swift:51`

- [ ] 在 `isFavorite` 行下方加两个字段：

```swift
var isFavorite: Bool = false
var isPinned: Bool = false
var pinnedAt: Date? = nil
var isDeleted: Bool = false
var deletedAt: Date?
```

> SwiftData 自动迁移（Bool 默认 false，Optional Date 默认 nil，老 db 无需写迁移代码）
> `xcodegen generate && xcodebuild -scheme MemoryPalace build` 验证通过

- [ ] 启动 app，打开一个老对话，确认不 crash（迁移无感知）
- [ ] commit：`feat: MessageNode 加 isPinned / pinnedAt 字段`

---

### Task 2：ConversationViewModel 加 pin 能力（1h）

**文件**：`MemoryPalace/ViewModels/ConversationViewModel.swift`

#### 2.1 加 `togglePin` 方法

- [ ] 在 `toggleFavorite`（line 521）下方加：

```swift
func togglePin(_ node: MessageNode) {
    if node.isPinned {
        node.isPinned = false
        node.pinnedAt = nil
    } else {
        node.isPinned = true
        node.pinnedAt = Date()
    }
}

/// 取消当前对话所有 pin
func unpinAll() {
    for node in currentPath where node.isPinned {
        node.isPinned = false
        node.pinnedAt = nil
    }
}
```

#### 2.2 加 `pinnedNodes` computed 属性

- [ ] 在类里加：

```swift
/// 当前对话 pin 的节点，按 pinnedAt 降序（新 → 旧），过滤软删除
var pinnedNodes: [MessageNode] {
    currentPath
        .filter { $0.isPinned && !$0.isDeleted }
        .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
}
```

#### 2.3 build 验证

- [ ] `xcodebuild -scheme MemoryPalace build` 零 warning
- [ ] commit：`feat: ConversationViewModel 加 togglePin / pinnedNodes`

---

### Task 3：Pin 入口（iOS contextMenu + macOS HoverButtons）（1h）

**文件**：`MemoryPalace/Views/CardFlowView.swift`

#### 3.1 contextMenu 加"钉住"项（iOS 长按 + macOS 右键共用）

- [ ] 在 line 1077（收藏按钮下方、"收藏到文件夹"上方）加：

```swift
Button(action: onTogglePin) {
    Label(node.isPinned ? "取消钉住" : "钉住",
          systemImage: node.isPinned ? "pin.slash" : "pin")
}
```

#### 3.2 Bubble struct 加 `onTogglePin` 参数

- [ ] 在 line 889 附近（`let onToggleFavorite: () -> Void` 下方）加：

```swift
let onToggleFavorite: () -> Void
let onTogglePin: () -> Void
```

#### 3.3 HoverButtons 加 pin 按钮（macOS hover）

- [ ] 在 line 1132（HoverButtons 参数）加：

```swift
let onToggleFavorite: () -> Void
let isPinned: Bool
let onTogglePin: () -> Void
```

- [ ] 在 line 1162 收藏按钮**右边**加：

```swift
Button(action: onToggleFavorite) {
    Image(systemName: isFavorite ? "star.fill" : "star")
        .font(.system(size: 13))
        .foregroundColor(isFavorite ? Theme.favorite : .secondary)
}
.buttonStyle(.plain)

// ↓ 新增 pin 按钮
Button(action: onTogglePin) {
    Image(systemName: isPinned ? "pin.fill" : "pin")
        .font(.system(size: 13))
        .foregroundColor(isPinned ? Theme.branchIndicator : .secondary)
}
.buttonStyle(.plain)
```

#### 3.4 把 HoverButtons 调用和 Bubble 调用传新参数

- [ ] line 1109 附近 HoverButtons 调用加 `isPinned: node.isPinned, onTogglePin: onTogglePin,`
- [ ] line 36 附近 CardFlowView 主体里 Bubble 调用加：

```swift
onTogglePin: { viewModel.togglePin(node) },
```

#### 3.5 build + 手测

- [ ] build 通过
- [ ] iOS 模拟器：长按一条消息 → 看到"钉住"选项 → 点击 → 再长按变成"取消钉住"
- [ ] macOS：hover 消息 → 看到 pin 图标 → 点击切换
- [ ] commit：`feat: 消息加 pin 入口 (iOS 长按 + macOS hover)`

---

### Task 4：PinnedMessageBar.swift 静态 UI（1.5h）

**文件**：新建 `MemoryPalace/Views/PinnedMessageBar.swift`

- [ ] 创建文件，内容：

```swift
import SwiftUI

struct PinnedMessageBar: View {
    let pinnedNodes: [MessageNode]
    @Binding var currentIndex: Int           // 当前展示第几条（0 = 最新）
    @Binding var isHidden: Bool              // × 按钮临时隐藏
    let onTap: () -> Void                     // tap bar → 跳转 + 轮换
    let onUnpinCurrent: () -> Void            // 长按菜单：取消此条
    let onUnpinAll: () -> Void                // 长按菜单：取消全部

    var body: some View {
        if !pinnedNodes.isEmpty && !isHidden {
            let current = pinnedNodes[min(currentIndex, pinnedNodes.count - 1)]
            HStack(spacing: 10) {
                // 左侧 accent 竖线
                Rectangle()
                    .fill(Theme.branchIndicator)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                // 文字区
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.branchIndicator)
                    Text(previewText(current))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 右侧 ×
                Button(action: { isHidden = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.mainBg)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .contextMenu {
                Button(role: .destructive, action: onUnpinCurrent) {
                    Label("取消钉住此条", systemImage: "pin.slash")
                }
                Button(role: .destructive, action: onUnpinAll) {
                    Label("取消所有钉住", systemImage: "pin.slash.fill")
                }
                Button(action: { isHidden = true }) {
                    Label("暂时隐藏", systemImage: "eye.slash")
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        }
    }

    private var titleText: String {
        if pinnedNodes.count == 1 {
            return "Pinned Message"
        }
        return "Pinned #\(currentIndex + 1) / \(pinnedNodes.count)"
    }

    private func previewText(_ node: MessageNode) -> String {
        let cleaned = ContentCleaner.clean(node.content, cacheKey: node.id)
        return String(cleaned.prefix(60))
    }
}
```

- [ ] build 通过
- [ ] 暂不接入 CardFlowView，只确认文件编译过
- [ ] commit：`feat: 新建 PinnedMessageBar 静态 UI`

---

### Task 5：PinnedMessageBar 接入 + 轮换状态机（2h）

**文件**：`MemoryPalace/Views/CardFlowView.swift`

#### 5.1 在 CardFlowView 加 state

- [ ] 在 body 外面（`struct CardFlowView: View` 内，其他 @State 附近）加：

```swift
@State private var pinCurrentIndex: Int = 0
@State private var pinBarHidden: Bool = false
```

#### 5.2 VStack 顶部嵌入 Pin Bar

- [ ] 找到 `ScrollViewReader { proxy in` （line 96）的**外层** VStack，在 ScrollView 上方加：

```swift
VStack(spacing: 0) {
    PinnedMessageBar(
        pinnedNodes: viewModel.pinnedNodes,
        currentIndex: $pinCurrentIndex,
        isHidden: $pinBarHidden,
        onTap: handlePinBarTap,
        onUnpinCurrent: handleUnpinCurrent,
        onUnpinAll: {
            viewModel.unpinAll()
            pinCurrentIndex = 0
        }
    )
    .animation(.easeInOut(duration: 0.25), value: viewModel.pinnedNodes.map(\.id))
    .animation(.easeInOut(duration: 0.25), value: pinCurrentIndex)
    .animation(.easeInOut(duration: 0.25), value: pinBarHidden)

    ScrollViewReader { proxy in
        // ... 原有
    }
}
```

#### 5.3 加 tap 跳转 + 轮换 handler

- [ ] 在 CardFlowView 里加私有方法：

```swift
private func handlePinBarTap() {
    let pins = viewModel.pinnedNodes
    guard !pins.isEmpty else { return }
    let idx = min(pinCurrentIndex, pins.count - 1)
    let target = pins[idx]

    // 检查节点是否在 currentPath（最小版：不在就不跳，不做跨分支）
    guard viewModel.currentPath.contains(where: { $0.id == target.id }) else {
        // 仍然轮换 index，避免卡住
        pinCurrentIndex = (idx + 1) % pins.count
        return
    }

    // 跳转 + 高亮
    viewModel.scrollToNodeId = target.id
    viewModel.highlightSource = .pinJump
    viewModel.highlightedNodeId = target.id

    // 轮换到下一条 pin（下次 tap 去下一条）
    pinCurrentIndex = (idx + 1) % pins.count
}

private func handleUnpinCurrent() {
    let pins = viewModel.pinnedNodes
    guard !pins.isEmpty else { return }
    let idx = min(pinCurrentIndex, pins.count - 1)
    let target = pins[idx]
    target.isPinned = false
    target.pinnedAt = nil
    // 轮换 index 校正
    if pinCurrentIndex >= pins.count - 1 {
        pinCurrentIndex = 0
    }
}
```

#### 5.4 切换对话时重置 state

- [ ] 在 CardFlowView 里加：

```swift
.onChange(of: viewModel.selectedConversation?.id) { _, _ in
    pinCurrentIndex = 0
    pinBarHidden = false
}
```

#### 5.5 build + 手测

- [ ] iOS 长按消息 → 钉住 → 顶部出现 Pin Bar，标题 "Pinned Message"
- [ ] 再钉一条 → 标题变 "Pinned #1 / 2"
- [ ] tap bar → 跳到当前 pin + 边框闪烁高亮
- [ ] 再 tap → 跳到下一条 pin，bar 切换显示
- [ ] `×` → bar 淡出
- [ ] 切换到另一个对话 → 再切回来 → bar 恢复显示
- [ ] 长按 bar → 菜单出现 "取消此条 / 取消全部 / 暂时隐藏"
- [ ] commit：`feat: Pin Bar 接入 CardFlowView + 多 pin 轮换`

---

### Task 6：高亮复用（PinJump 用和 search 同款视觉）（0.5h）

**文件**：`MemoryPalace/ViewModels/ConversationViewModel.swift`、`MemoryPalace/Views/CardFlowView.swift`

#### 6.1 ViewModel 加 highlight source 枚举

- [ ] 在 ConversationViewModel 加：

```swift
enum HighlightSource {
    case none, search, pinJump
}

@Published var highlightSource: HighlightSource = .none
@Published var highlightedNodeId: String? = nil
```

> 注意：搜索可能已经有 `inConvMatchIndex` 之类的状态，这里**新增**独立字段不影响原逻辑

#### 6.2 Bubble 监听

- [ ] 在 bubble 里加 `let highlightTrigger: String?`（= `viewModel.highlightedNodeId`）
- [ ] 加：

```swift
.onChange(of: highlightTrigger) { _, id in
    if id == node.id {
        withAnimation(.easeIn(duration: 0.3)) { highlightOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.5)) { highlightOpacity = 0 }
        }
    }
}
```

- [ ] bubble 上的边框/背景已经用 `highlightOpacity` 驱动，无需改。

#### 6.3 build + 手测

- [ ] tap pin bar → 跳转后该气泡边框发光 2s 再淡出
- [ ] commit：`feat: Pin 跳转复用高亮视觉`

---

### Task 7：ScrollToBottomButton.swift（0.5h）

**文件**：新建 `MemoryPalace/Views/ScrollToBottomButton.swift`

- [ ] 创建文件：

```swift
import SwiftUI

struct ScrollToBottomButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 8)
        .animation(.spring(duration: 0.3), value: isVisible)
        .allowsHitTesting(isVisible)
    }
}
```

- [ ] build 通过
- [ ] commit：`feat: 新建 ScrollToBottomButton（玻璃按钮）`

---

### Task 8：isAtBottom 检测 + 显隐联动（0.5h）

**文件**：`MemoryPalace/Views/CardFlowView.swift`

#### 8.1 加 state

- [ ] 在 CardFlowView 加：

```swift
@State private var isAtBottom: Bool = true
```

#### 8.2 最后一条 bubble 打 appear/disappear 标记

- [ ] 找到 ForEach 遍历 currentPath 的地方，在每条 bubble 上加：

```swift
.onAppear {
    if node.id == viewModel.currentPath.last?.id {
        isAtBottom = true
    }
}
.onDisappear {
    if node.id == viewModel.currentPath.last?.id {
        isAtBottom = false
    }
}
```

> 注意：如果已有 onAppear，合并进去

#### 8.3 右下叠加按钮

- [ ] 在 CardFlowView 最外层 ZStack / `.overlay(alignment: .bottomTrailing)` 加：

```swift
.overlay(alignment: .bottomTrailing) {
    ScrollToBottomButton(
        isVisible: !isAtBottom && !viewModel.currentPath.isEmpty,
        action: {
            guard let lastId = viewModel.currentPath.last?.id else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                // 用 scrollToNodeId 触发统一路径
                viewModel.scrollToNodeId = lastId
            }
        }
    )
    .padding(.trailing, 16)
    .padding(.bottom, 80)   // 避开输入框，实际数值按输入框高度调
}
```

> 如果外层已有 overlay，改成 ZStack 或合并

#### 8.4 build + 手测

- [ ] 聊几条消息后往上滚 → 右下出现玻璃 ↓
- [ ] 点击 → 滚到底 → 按钮消失
- [ ] streaming 中，若已在底部，跟随滚动，按钮保持隐藏；离底时按钮出现
- [ ] commit：`feat: 回底玻璃按钮 + isAtBottom 检测`

---

### Task 9：手测清单 + 清理（0.5h）

#### 9.1 iOS 全流程

- [ ] 开一个长对话（20+ 条）
- [ ] 长按消息钉住 3 条
- [ ] 顶部 bar 显示 "Pinned #1 / 3"
- [ ] tap bar → 跳转 + 高亮，bar 变 "#2 / 3"
- [ ] 再 tap → "#3 / 3"，再 tap → "#1 / 3"（循环）
- [ ] 长按 bar → 取消此条 → bar 变 "#1 / 2"
- [ ] 长按 bar → 取消全部 → bar 消失
- [ ] 再钉一条 → bar 回来
- [ ] × → bar 消失；切换对话再回来 → bar 恢复
- [ ] 往上滚 → ↓ 按钮出现；点击回底 → 按钮消失

#### 9.2 macOS 全流程

- [ ] hover 消息 → pin 图标出现；点击切换状态
- [ ] 右键消息 → 菜单含"钉住"
- [ ] 右键 pin bar → 菜单含"取消此条 / 取消全部 / 暂时隐藏"

#### 9.3 边界情况

- [ ] pin 多条（15+ 条也不报错，上限已去掉）
- [ ] pin 一条后软删除该消息 → bar 不再显示它（computed 已过滤）
- [ ] 导入的旧对话（ChatGPT/Claude）→ pin 功能正常
- [ ] 分支切换后 pin 节点不在当前 path → tap bar 无跳转但 index 轮换（不卡住）

#### 9.4 清理 + commit

- [ ] 无 warning
- [ ] 无调试 print
- [ ] commit：`chore: pin + scroll-to-bottom 测试完成`
- [ ] push 到 GitHub

---

## 风险 & 回滚

| 风险 | 缓解 |
|---|---|
| SwiftData 迁移失败 | Task 1 单独做，失败立即 revert |
| Pin bar 动画抖 | Task 4 UI 先静态，Task 5 再接轮换 |
| isAtBottom 检测误判 | 先用方案 B（onAppear），不行再换 GeometryReader |
| `.ultraThinMaterial` 在 macOS 观感差 | 用系统 material 跨平台同款，先实现再看 |
| 分支切换 pin 跳转 | 最小版不做跨分支自动切，弹 toast 提示 |

---

## 验证标准（来自 research）

1. iOS 长按消息 → 菜单出现"钉住" → 点完消息带 pin 标记 ✅
2. macOS hover 消息 → 看到 pin 按钮 → 点完状态切换 ✅
3. Pin 完顶部 bar 出现，显示内容预览 ✅
4. Tap bar 跳到该消息 + 高亮 2 秒 ✅
5. Pin 2+ 条时 tap bar 轮换到下一条 ✅
6. Bar 上 × 临时隐藏（pin 还在，切换对话回来消失再出现）✅
7. 长按 bar / 右键 bar 菜单：取消此条 / 取消全部 / 隐藏 bar ✅
8. 聊天滚到一屏以上时右下出现玻璃 ↓，点击回底 ✅
9. 滚到底时 ↓ 按钮消失 ✅
10. 导入的旧对话 pin 功能正常 ✅
11. build 零 warning ✅

---

*等粟粟批注后按 Task 1 → 9 顺序执行，每完成一个 build 验证 + commit。*

# Plan：分支地图 + 类型 chip FlowLayout 换行

**日期**：2026-05-08
**关联**：B20 part 2 收尾迭代（粟粟反馈 A3 + Bβ）
**预计工作量**：6 个 task，~1.5 小时

---

## 决策定档

| 反馈 | 决策 |
|---|---|
| A3 找分支难 | **顶部"🌿 N 条分支"按钮 → 点开 sheet 显示分支地图**（方案 1） |
| Bβ 类型 chip 塞不下 | **FlowLayout 自动换行**（iOS 16+ Layout protocol） |

---

## 一、A3 分支地图设计

### 入口位置

iOS：在 chat page 顶部 PinBar 那一行的右侧加 `🌿 N` 角标按钮（N = 总分支数）
macOS：同 PinBar 行右侧

> 不放 nav toolbar 是因为 nav 已经满了；放 PinBar 行最显眼又不挤。

按钮外观：
```
┌─────────────────────────┐
│  📌 PinBar 内容        🌿 3 │
└─────────────────────────┘
```

只在当前对话**有分支**时显示（branchInfoMap.count > 0）。

### 点开后的 sheet 内容

```
分支地图  (×)
─────────────────────────
当前对话：金瓶梅话本 🔞
共 251 节点 / 主线 180 条

主线 (当前显示) ✓
─────────────────────────
分支 1  (在第 12 条气泡处)
  → "...他突然站起来..."
  共 28 条
  ─────────────────
分支 2  (在第 47 条气泡处)
  → "...你想吃糖吗..."
  共 50 条
  ─────────────────
分支 3  (在第 89 条气泡处)
  → "...林黛玉冷笑..."
  共 38 条
```

每条分支：
- 显示分支起点（在第 X 条气泡处的哪条 message 预览）
- 显示分支长度（多少 displayable node）
- 点击 → 切到那条分支 + scroll 到分支起点 + 关闭 sheet

主线一项有 ✓ 标识，点了切回主线（用 conversation.currentNodeId 重 build）。

### 数据来源

已有（不需要新数据）：
- `viewModel.currentPath`：主线 path
- `viewModel.branchInfoMap`：每个有分支的 displayed node → BranchInfo
- `BranchInfo.branchChildren`：所有 child 的 (index, node, isMainPath)
- `viewModel.switchBranch(at:to:)`：切分支 API

需要新增：
- 分支长度计算：从某个 child 顺向走到 leaf，数 displayable node 数。helper func
- "在第 X 条气泡处"：用 currentPath.firstIndex(where: { $0.id == displayedNodeId })

---

## 二、Bβ FlowLayout 换行设计

iOS 16 / macOS 13+ 有 `Layout` protocol。实现一个简单的 FlowLayout：

```swift
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // 计算总宽 + 总高
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // 行内放完，超过 bounds.width 换行
    }
}
```

应用：把"类型"那一行的 HStack 换成 FlowLayout：

```swift
FlowLayout(spacing: 12, lineSpacing: 8) {
    typeChip("全部", kind: .conversation)
    typeChip("🌿 分支", kind: .branchContent)
    typeChip("🎨 贴纸", kind: .sticker)
    typeChip("👤 助手模板", kind: .characterCard)
    typeChip("📚 世界书", kind: .worldBook)
    typeChip("🧠 记忆", kind: .memory)
}
```

categoryLabel("类型") 单独放在 FlowLayout 上面或左侧（如果左侧固定，FlowLayout 跟在右边）。

### 决策点

categoryLabel 跟 FlowLayout 怎么布局？

```
A. 上下：
   类型
   [全部] [🌿 分支] [🎨 贴纸] [👤 助手模板]
   [📚 世界书] [🧠 记忆]✅

B. 左右：
   类型  [全部] [🌿 分支] [🎨 贴纸] [👤 助手模板]
         [📚 世界书] [🧠 记忆]

C. label 放进 flow（参与 wrap）：
   [类型] [全部] [🌿 分支] [🎨 贴纸] ...
   （但 label 不是 chip 风格冲突）
```

**推荐 A**——视觉清晰、无对齐问题。其他 categoryLabel（时间/角色/排序）也可以同步改成 A 风格但**不强制**（它们 chip 数少不会塞）。

---

## 三、Task checklist

### [ ] T12. 添加分支长度 helper

`ConversationViewModel` 加 helper：

```swift
/// 给定 child nodeId，顺向走到 leaf（按主选择）数 displayable node 数。
/// 用于分支地图显示"分支 N 共 X 条"。
func branchLength(fromChildId childId: String) -> Int
```

复用 effectiveChildrenMap，跟 buildTreeInBackground 顺向走法保持一致。

---

### [ ] T13. 实现 FlowLayout

新建文件 `MemoryPalace/Views/FlowLayout.swift`：

```swift
@available(iOS 16.0, macOS 13.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 8

    func sizeThatFits(...) -> CGSize { ... }
    func placeSubviews(...) { ... }
}
```

参考 Apple 文档。~40 行。

---

### [ ] T14. 替换类型 chip HStack 为 FlowLayout

`SidebarView.swift` 行 2351-2359：

```swift
// 类型
VStack(alignment: .leading, spacing: 8) {
    categoryLabel("类型")
    FlowLayout(spacing: 8, lineSpacing: 6) {
        typeChip("全部", kind: .conversation)
        typeChip("🌿 分支", kind: .branchContent)
        typeChip("🎨 贴纸", kind: .sticker)
        typeChip("👤 助手模板", kind: .characterCard)
        typeChip("📚 世界书", kind: .worldBook)
        typeChip("🧠 记忆", kind: .memory)
    }
}
```

其他 categoryLabel 行（时间/角色/排序）保持 HStack 不动。

---

### [ ] T15. 实现分支地图 Sheet view

新建文件 `MemoryPalace/Views/BranchMapSheet.swift`：

```swift
struct BranchMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: ConversationViewModel
    let onPickBranch: (String, Int) -> Void   // (branchAnchorNodeId, childIndex)
    let onPickMainPath: () -> Void

    var body: some View {
        // List：主线 row + 每条 branch row
    }
}
```

每条 branch row 显示：
- 分支起点 bubble 在 currentPath 第几条
- 分支起点 message preview（80 字截断）
- 分支长度

数据迭代：
```swift
let branchEntries: [(anchor: String, child: Int, preview: String, length: Int, location: Int)] =
    viewModel.branchInfoMap.flatMap { (displayedId, info) in
        info.branchChildren.compactMap { child in
            if child.isMainPath { return nil }
            let location = viewModel.currentPath.firstIndex(where: { $0.id == displayedId }) ?? -1
            return (info.branchNodeId, child.index, child.node.content, viewModel.branchLength(fromChildId: child.node.id), location)
        }
    }
    .sorted(by: { $0.location < $1.location })
```

---

### [ ] T16. 在 PinBar 行右侧加 🌿 按钮

CardFlowView：找 PinBar 那一段（行 165-180 macOS / iOS 在 nav）。

iOS：当前 PinBar 怎么挂的？需要看一下。
macOS：PinBar 是 VStack 子项，可在它旁边加一个按钮。

按钮逻辑：
- 只在 `viewModel.branchInfoMap.values.contains { info in info.branchChildren.contains { !$0.isMainPath } }` 时显示
- N = 所有 branchInfoMap 里非主线 child 总数
- 点击 `showBranchMap = true`

```swift
Button {
    showBranchMap = true
} label: {
    HStack(spacing: 4) {
        Text("🌿")
        Text("\(branchCount)")
            .font(.system(size: 12, weight: .medium))
    }
}
.sheet(isPresented: $showBranchMap) {
    BranchMapSheet(
        viewModel: viewModel,
        onPickBranch: { anchorId, childIdx in
            viewModel.switchBranch(at: anchorId, to: childIdx)
            showBranchMap = false
        },
        onPickMainPath: {
            // 切回主线：用 conversation.currentNodeId 重 build
            if let conv = viewModel.selectedConversation {
                viewModel.loadConversation(conv, context: modelContext)
            }
            showBranchMap = false
        }
    )
}
```

---

### [ ] T17. 双端 build + 17 Air 真机验证

```bash
xcodebuild -scheme MemoryPalace build           # macOS
xcodebuild -scheme MemoryPalaceIOS -destination 'generic/platform=iOS Simulator' build
```

验证：
- [ ] 类型 chip 一行装不下时自动换行（iPhone 17 Air 屏宽看下）
- [ ] 类型 chip 一行能装下时不换行（iPad / 大屏 macOS）
- [ ] 进金瓶梅对话 → PinBar 行右侧出现 "🌿 N" 按钮
- [ ] 没分支的对话不出现按钮
- [ ] 点 🌿 → sheet 弹出 → 显示主线 + 所有分支
- [ ] 主线 row 有 ✓ 标识
- [ ] 点分支 row → sheet 关闭 + 切到那条分支 + 弹"已切换到分支"toast
- [ ] 在分支模式下点 🌿 sheet 里的"主线" → 切回主线
- [ ] 切回主线后 path 恢复完整 180 条

---

## 四、风险

1. **branchInfoMap 不全**：branchInfoMap 只记当前 currentPath 上的 displayed node 的分支。如果某个分支起点本身在另一条 branch 上（嵌套分支），可能看不到。
   - 应对：先做"当前主线上的所有分支"，嵌套分支以后版本扩展。
2. **FlowLayout 性能**：6 个 chip 极小，no-op。
3. **PinBar 行布局打架**：PinBar 现有布局可能没留位置。
   - 应对：先看代码再决定是 overlay 还是 sibling。

---

## 五、实施顺序

```
T13 (FlowLayout) → T14 (chip 换行) → T17a (验证布局)
T12 (helper) → T15 (Sheet view) → T16 (按钮入口) → T17b (验证分支地图)
```

两条线独立，可以并行 commit。

---

## 六、不在本期范围

- 嵌套分支（branch within branch）的可视化 — 复杂度高，等真有用户需求再加
- 分支命名 / 备注 — 当前分支只有 nodeId，没有用户起的名字
- 分支预览缩略图 / 第一个 assistant 回复的展开 — 现在只显示一行预览

---

## 七、跟之前 b20-2 plan 的关系

本 plan 是 b20-2 的**用户体验增强**，不修任何 b20-2 已修的 bug。
b20-2 的 T11（PROJECT_ROADMAP.md 标 ✅）等本 plan 完成一并标。

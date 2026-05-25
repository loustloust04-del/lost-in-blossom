# Plan：BranchMap v11 — 修 git graph lane 真 bug

**日期**：2026-05-18
**起点**：HEAD = 7b45730（v10 初始 git graph lane assignment）
**研究**：docs/research-branch-map-v11-lane-bugs.md（hermes 验证）

---

## 起点 v10 现状

```swift
fileprivate func layoutGitGraph(root, mainPathIds, centerX, laneSpacing, vSpacing) {
    final class LaneAlloc {
        // ...
        func alloc() -> Int { ... }  // 全局平衡，无 side bias
        func release(_ lane: Int) { ... }
    }
    let alloc = LaneAlloc()
    func isOnMainPath(_ n: TidyNode) -> Bool { mainPathIds.contains(n.id) }

    func dfs(_ n: TidyNode, lane: Int, depth: Int) {
        n.x = centerX + Double(lane) * laneSpacing
        n.y = Double(depth) * vSpacing
        let mainChild = n.children.first(where: isOnMainPath)  // ← v10 只在 mainPath 子树有效
        for c in n.children {
            let cLane = (c === mainChild) ? lane : alloc.alloc()
            dfs(c, lane: cLane, depth: depth + 1)
            if cLane != lane { alloc.release(cLane) }  // ← BUG 1: sibling 间 release
        }
    }
    dfs(root, lane: 0, depth: 0)
}
```

---

## v11 目标改动（3 fix）

### Fix 1：Fork-scope lane release（不是 sibling-local）

dfs 内：先收集所有 non-lineChild sibling 的 lane，所有 children dfs 完才统一 release：

```swift
var siblingLanes: [Int] = []
for c in n.children {
    let cLane: Int
    if c === lineChild {
        cLane = lane
    } else {
        cLane = alloc.alloc(preferredSide: parentSide(lane))
        siblingLanes.append(cLane)
    }
    dfs(c, lane: cLane, depth: depth + 1, parentSide: cSide)
}
// 所有 siblings 都 dfs 完才统一 release
for l in siblingLanes { alloc.release(l) }
```

**效果**：fork 的 3 个 retry siblings 各占独立 lane，不重叠。

### Fix 2：Side stability（子继承父侧）

```swift
enum Side { case left, right }

func parentSide(_ lane: Int) -> Side? {
    if lane < 0 { return .left }
    if lane > 0 { return .right }
    return nil  // mainline → 子用 balance
}

func alloc(preferredSide: Side?) -> Int {
    let side: Side
    if let p = preferredSide {
        side = p   // 父在左 → 子继续左；父在右 → 子继续右
    } else {
        // mainline (lane=0) 子 → 平衡
        side = activeLeft.count <= activeRight.count ? .left : .right
    }
    // 该 side 的 free 池 / 增 max used
    if side == .left {
        let idx = leftFree.isEmpty ? (leftMaxUsed += 1, leftMaxUsed).1 : leftFree.removeFirst()
        activeLeft.insert(idx)
        return -idx
    } else {
        let idx = rightFree.isEmpty ? (rightMaxUsed += 1, rightMaxUsed).1 : rightFree.removeFirst()
        activeRight.insert(idx)
        return idx
    }
}
```

dfs 增加 parentSide 参数：

```swift
func dfs(_ n: TidyNode, lane: Int, depth: Int, parentSide: Side?) {
    n.x = centerX + Double(lane) * laneSpacing
    n.y = Double(depth) * vSpacing

    // lineChild 判定：n 在 mainPath → mainPath child; n 不在 mainPath → children[0]
    let lineChild: TidyNode?
    if isOnMainPath(n) {
        lineChild = n.children.first(where: isOnMainPath)
    } else {
        lineChild = n.children.first
    }

    var siblingLanes: [Int] = []
    for c in n.children {
        let cLane: Int
        let cSide: Side?
        if c === lineChild {
            cLane = lane
            cSide = parentSide
        } else {
            // 子 branch alloc 时继承父侧（lane > 0 → right; lane < 0 → left; lane == 0 → balance）
            cLane = alloc.alloc(preferredSide: parentSide ?? (lane < 0 ? .left : lane > 0 ? .right : nil))
            cSide = cLane < 0 ? .left : .right
            siblingLanes.append(cLane)
        }
        dfs(c, lane: cLane, depth: depth + 1, parentSide: cSide)
    }
    for l in siblingLanes { alloc.release(l) }
}
```

**效果**：左 branch 子分支继续左，不跨主线螺旋。

### Fix 3：mainline 视觉强化

Hermes 推荐："主线 1.25~1.5x 线宽 + 更高对比色 + 节点直径大 10~20%"。

#### drawConnections 改 stroke

```swift
private func drawConnections(ctx: GraphicsContext, layout: TreeLayout) {
    let activeColor = Theme.favorite
    let mainColor = Theme.textPrimary.opacity(0.55)    // 主线骨架色（不被 currentPath 抢色）
    let branchColor = Color.gray.opacity(0.3)           // 分支低对比

    for edge in layout.edges {
        let isOnMain = isEdgeOnMainline(edge: edge, layout: layout)  // 新 helper
        let isOnCurrent = isEdgeOnPath(edge: edge, pathIds: currentPathIds, layout: layout)
        
        var path = Path()
        // ... bezier ...
        
        let strokeColor: Color
        let strokeWidth: CGFloat
        if isOnCurrent {
            strokeColor = activeColor
            strokeWidth = 2.5
        } else if isOnMain {
            strokeColor = mainColor
            strokeWidth = 2.0
        } else {
            strokeColor = branchColor
            strokeWidth = 1.0
        }
        ctx.stroke(path, with: .color(strokeColor),
                   style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
    }
}

func isEdgeOnMainline(edge: TreeEdge, layout: TreeLayout) -> Bool {
    // 两端都在 mainPathIds 内
    let mainIds = mainPathIdsCache
    let fromOn = mainIds.contains(edge.fromNodeId) || isCollapsedFullyOnMain(edge.fromNodeId, layout)
    let toOn = mainIds.contains(edge.toNodeId) || isCollapsedFullyOnMain(edge.toNodeId, layout)
    return fromOn && toOn
}
```

#### nodeView dot 大小区分

```swift
let isOnMain = mainPathIds.contains(vn.id) || vn.collapsedNodeIds.allSatisfy { mainPathIds.contains($0) }
let dotRadius: CGFloat = isOnMain ? 10 : 8  // mainline 大一圈
```

#### currentPathIds + mainPathIds 都需要在 view scope

BranchMapSheet 加 computed property：

```swift
private var mainPathIdsLocal: Set<String> {
    viewModel.branchMapSnapshot()?.mainPathIds ?? []
}
```

或者 cache 在 layout result。简化：drawConnections / nodeView 各自读 snapshot.mainPathIds。

---

## Task checklist

- [ ] T1. LaneAlloc 加 `Side` enum 和 `alloc(preferredSide:)`；删原 `alloc()`
- [ ] T2. dfs 加 `parentSide` 参数 + fork-scope siblingLanes + 统一 release
- [ ] T3. dfs 内 alloc 调用传 preferredSide（基于父 lane 正负）
- [ ] T4. drawConnections 加 mainline edge 检测 + 三层颜色/粗细（current 黄粗 / mainline 灰粗 / branch 灰细）
- [ ] T5. nodeView 加 mainline dot 大一圈（10pt vs 8pt）
- [ ] T6. helper `isOnMainPath(VisibleNode)` 暴露到 view（用 viewModel.branchMapSnapshot mainPathIds）
- [ ] T7. 双端 build
- [ ] T8. commit + push

---

## 关键参数

- centerX = availableW / 2
- laneSpacing = 44pt
- vSpacing = 60pt
- mainline stroke = 2pt
- mainline dot = 10pt
- branch stroke = 1pt
- branch dot = 8pt
- currentPath active stroke = 2.5pt（覆盖 mainline 视觉）

---

## 不做（v12 候选）

- ❌ 两阶段 Reingold-Tilford with contour（hermes 提的 long-term，超工程量）
- ❌ lane spacing 自适应（v11 看效果再说）
- ❌ overflow fallback（lane 数超屏宽时如何处理；先看 max active lane 实际多少）
- ❌ 拖动节点（Phase B）
- ❌ bus / shared stem edge routing

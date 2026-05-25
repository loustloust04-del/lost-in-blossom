# Research：BranchMap v11 — v10 git graph 的真 bug 诊断

**日期**：2026-05-18
**触发**：粟粟反馈 v10/v10.1 蛇形 + 节点重叠；v10.2 整子树折叠又看不到分支内容
**方法**：ultrathink + hermes 验证 + 上网搜 + xcdoc 查
**结论**：v10 lane assignment 有 2 个 critical bug + 1 个视觉不足

---

## v10/v10.1 的 2 个 critical bug

### Bug 1：Sibling lane reuse → 同 fork 兄弟重叠

```swift
for c in n.children {
    let cLane = (c === lineChild) ? lane : alloc.alloc()
    dfs(c, lane: cLane, depth: depth + 1)
    if cLane != lane { alloc.release(cLane) }  // ← release 在 sibling 之间
}
```

**问题**：处理 c0 完 → release lane = 比如 -1 → free pool。处理 c1 时 alloc 从 free pool 拿 → c1 也分到 -1。
**视觉**：c0 和 c1 都在 (lane=-1, depth+1) → **同 x 同 y 完全重叠**。
**症状**：粟粟说"三分支不对" — 3 个 retry 被 alloc 复用同 lane → 视觉上只看到 1 个 dot。

### Bug 2：Cross-mainline alloc → 螺旋穿主线

```swift
func alloc() -> Int {
    if activeLeft.count <= activeRight.count {
        return -leftLane
    } else {
        return rightLane
    }
}
```

**问题**：c0 lane=-1（左侧 branch），dfs(c0) 内部 alloc 看 activeLeft={1} activeRight={} → leftCount > rightCount → alloc 走右 → c0 的子分支跑到 lane=+1（右侧）。
**视觉**：左 branch 的内部子分支跨主线穿到右侧 → bezier 螺旋。
**症状**：v10.1 整树底部蛇形交错。

### Hermes 验证

> 你的两个诊断基本都对，而且它们正是"把 git graph 的列分配硬套到树 DFS"时最常见的两类坏相位。
>
> 标准做法不是"每个 sibling 后释放"，而是"这一组 sibling 的 lane 先全部保留，等这一层/这个 fork 的并列分支都放完再回收"
>
> 无侧别约束的全局 alloc 会让左支内部的子分支跑到右边，视觉上穿过主干。常见实现都会尽量保持 side stability：父分支在左，后代优先继续占左侧新 lane；父分支在右，后代优先继续占右侧。

---

## v11 修法（最小修正）

### Fix 1：Fork-scope lane release（不是 sibling-local）

进入 fork 处理 children 前，先收集所有 non-lineChild sibling 的 lane（暂存）；所有 children dfs 完才统一 release：

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
    dfs(c, lane: cLane, depth: depth + 1)
}
// 所有 siblings dfs 完才统一释放
for l in siblingLanes {
    alloc.release(l)
}
```

### Fix 2：Side stability

LaneAlloc 加 `preferredSide: Side?` 参数。子分支继承父侧别：

```swift
func alloc(preferredSide: Side?) -> Int {
    let side: Side
    if let p = preferredSide {
        side = p  // 父在左 → 子继续左；父在右 → 子继续右
    } else {
        // mainline（lane=0）的子 alloc → 左右平衡
        side = activeLeft.count <= activeRight.count ? .left : .right
    }
    // alloc 该 side 的 free 池 / 增 max used
    ...
}

// dfs 传 preferredSide
func parentSide(_ lane: Int) -> Side? {
    if lane < 0 { return .left }
    if lane > 0 { return .right }
    return nil  // mainline → 子用 balance
}
```

### Fix 3：视觉差异化 mainline / branch（hermes 推荐）

> 最稳的组合是"主线 1.25x~1.5x 线宽 + 更高对比色 + 节点直径大 10%~20%"。

- mainline (lane 0) connecting line：**2.5pt** vs branch **1pt**
- mainline node dot：**12pt** vs branch **8pt**
- mainline color: 高对比（Theme.textPrimary 或现有 favorite 黄）
- branch color: 低对比（gray.opacity(0.4)）

`StrokeStyle(lineWidth: 2.5, lineCap: .round)` 让粗线更好看。

---

## 长期方案（v12 候选，hermes 备注）

> 如果你想做得像成熟图工具，结构上更稳的是两阶段：
> - pass 1 算每个节点子树需要的左右轮廓/宽度；
> - pass 2 根据轮廓定 x。
> 这样 sibling overlap 和跨主线穿越都会从模型层消失，不需要靠 alloc/release 时机硬撑。

= 真 Reingold-Tilford with side contour。但当前 v11 三 fix 应该足够覆盖现有 bug。

---

## v10.2 方案 B 为什么不对

v10.2 把所有非 mainPath subtree 整体折叠成单 ↕N → 分支内部不可见。粟粟反馈"三分支和长分支都不对"——
- 三分支：只看到 1 个 ↕N（其实有 2-3 个 retry siblings 都被折叠成 1 个？等等 — 应该每个 branchHead 各折叠成自己的 ↕N，多个钩子）
- 长分支：分支内 chain 不再可见（被整体折叠）

**v11 走回 git graph 真实展开 + 修 bug**，不再做整子树折叠。

---

## Task plan（v11）

- [ ] T1. LaneAlloc 加 `alloc(preferredSide:)`；side 参数支持 .left/.right/nil
- [ ] T2. dfs 改成「fork-scope lane release」+ 「parent side inheritance」
- [ ] T3. drawConnections / nodeView：mainline 视觉强化（粗线、大 dot）
- [ ] T4. 退回 v10.2 的整子树折叠（恢复 chain folding + 普通节点画 fork children）
- [ ] T5. 双端 build + push

## Sources

- [pvigier — Commit Graph Drawing Algorithms](https://pvigier.github.io/2019/05/06/commit-graph-drawing-algorithms.html)
- [Hermes 咨询答复 — sibling lane reuse + side stability 2 bugs](本地)
- [Apple xcdoc — StrokeStyle](https://developer.apple.com/documentation/swiftui/strokestyle)

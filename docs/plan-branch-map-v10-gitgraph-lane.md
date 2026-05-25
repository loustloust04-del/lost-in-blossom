# Plan：BranchMap v10 — Git Graph Lane Assignment

**日期**：2026-05-18
**前置**：v9.2 banded children 不再上下叠；但 mainPath 沿 children[last] 累积右移导致整树漂右
**目标**：主线一条直线居中（lane 0）+ 分支按 lane 左右散开
**粟粟拍板**：A 方案 — 用 mainPathIds（永久 fixed）作为主线

---

## 算法

```
DFS(node, lane, depth):
    node.x = centerX + lane * laneSpacing
    node.y = depth * vSpacing
    
    mainChild = children.first where id in mainPathIds  # 沿 mainPath 走的那个
    
    for c in children:
        if c === mainChild:
            cLane = lane                # mainPath child 跟父同 lane
        else:
            cLane = alloc.alloc()       # off-path branch alloc 新 lane
        DFS(c, cLane, depth+1)
        if cLane != lane:
            alloc.release(cLane)        # branch 结束 lane 回收
```

## LaneAlloc

```
class LaneAlloc {
    leftFree: [Int]     # 已释放的左 lane abs（升序）
    rightFree: [Int]
    leftMaxUsed: Int
    rightMaxUsed: Int
    activeLeft: Set<Int>
    activeRight: Set<Int>
    
    alloc() -> Int:
        # 左右活跃数平衡：少的那边优先
        if activeLeft.count <= activeRight.count:
            idx = leftFree.isEmpty ? (++leftMaxUsed) : leftFree.removeFirst()
            activeLeft.insert(idx)
            return -idx
        else:
            idx = rightFree.isEmpty ? (++rightMaxUsed) : rightFree.removeFirst()
            activeRight.insert(idx)
            return idx
    
    release(lane):
        if lane == 0: return
        if lane < 0:
            activeLeft.remove(-lane); leftFree.append(-lane); leftFree.sort()
        else:
            activeRight.remove(lane); rightFree.append(lane); rightFree.sort()
}
```

---

## Task

- [ ] T1. BranchMapSnapshot 加 `mainPathIds: Set<String>`
- [ ] T2. ConversationViewModel.branchMapSnapshot() 暴露 mainPathIds
- [ ] T3. 删 layoutBandedTidyTree
- [ ] T4. 加 layoutGitGraph(root, mainPathIds, centerX, laneSpacing, vSpacing) + LaneAlloc class
- [ ] T5. computeLayout 改调用 layoutGitGraph
- [ ] T6. 双端 build + push

## 参数

- centerX = maxWidth / 2
- laneSpacing = 44pt（屏宽 342 / 7.7 lane = 容纳左右各 ~3-4 active lane）
- vSpacing = 60pt

## 不做（暂）

- ❌ laneSpacing 自适应（先固定 44pt 看效果）
- ❌ 同时活跃 lane > 屏宽容量的 fallback（v10 后再看）
- ❌ 拖动

---

## Trade-off

| | v9.2 (banded) | v10 (git graph) |
|---|---|---|
| 主线视觉 | 一会左一会右累积漂 | **一条直线居中** |
| 切 currentPath | layout 不变 | layout 不变（用 mainPathIds 解耦）|
| 分支视觉 | 跟 mainPath 平等 | 左右散开 lane |
| 切 currentPath 后黄色 path | 跟 currentPath | 跟 currentPath（可能跳 lane）|

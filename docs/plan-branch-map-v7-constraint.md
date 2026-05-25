# Plan：BranchMap v7 — Constraint Relaxation Layout

**日期**：2026-05-13
**前置**：v6 Tidy Tree warm start 已有
**目标**：替换 applyOverflowFallback → one-shot constraint relaxation；解决"节点漂出屏外"问题
**研究**：docs/research-branch-map-constraint-layout.md

---

## Phase A 任务（本次）

- [ ] T1. 替换 applyOverflowFallback → `relaxConstraints(root, screenWidth)`
- [ ] T2. 实现 5 个约束 + relaxation loop（50 iter）
- [ ] T3. 双端 build
- [ ] T4. commit + push

## Phase B（看效果再加）— 不在本次

- [ ] 拖动 node：DragGesture + draggedNodeId state
- [ ] 拖动后是否 re-relax / 还是锁死

---

## 算法

```
relaxConstraints(root, screenWidth):
    leftPad=24, rightPad=24
    availableW = screenWidth - leftPad - rightPad
    vSpacing=60, minSpacing=28, iterations=50, centerFactor=0.15

    allNodes = collect(root)

    for _ in 0..<iterations:
        # 1. y 拓扑约束（hard）— BFS 自顶向下；child.y < parent.y+vSpacing 时 shift 子树
        BFSPropagateY(root, vSpacing)

        # 2. x 屏宽 clamp（hard）
        for n in allNodes:
            n.x = clamp(n.x, leftPad, leftPad + availableW)

        # 3. 同父 children 居中（soft）— 父 x 拉向 children avg
        for n in allNodes where n.children:
            avg = mean(n.children.x)
            n.x += (avg - n.x) * centerFactor

        # 4. 同 depth 防重叠 + y jitter（soft）
        byDepth = group by round(n.y / vSpacing)
        for each group:
            sorted by x
            for adjacent pair (prev, curr):
                if curr.x - prev.x < minSpacing:
                    if 两边都贴屏 edge: shiftY(curr, +20)
                    elif prev 贴左 edge: curr.x = prev.x + minSpacing
                    elif curr 贴右 edge: prev.x = curr.x - minSpacing
                    else: 互推 half
```

## 约束总结

| # | 类型 | 描述 |
|---|---|---|
| 1 | Hard | 父 y < 子 y - vSpacing |
| 2 | Hard | 节点 x ∈ [leftPad, screenW - rightPad] |
| 3 | Soft | 父 x 拉向 children avg（centerFactor=0.15）|
| 4 | Soft | 同 depth 兄弟距 ≥ minSpacing；都贴边则 y jitter +20pt |

---

## 不做

- ❌ 持续物理 sim（耗电 + 视觉跳）
- ❌ N² 排斥所有节点对（only same-depth 互推就够）
- ❌ 拖动（Phase B）

# Plan：BranchMap v8 — Banded Tidy Tree（Hermes 推荐方案）

**日期**：2026-05-14
**前置**：v7 constraint relaxation 失败（漂屏外 + 同 edge 堆叠）
**研究**：研究中 Hermes 给的精准方案
**算法名**："tidy tree with bounded-width sibling row packing and curved edge routing"

---

## v7 失败根因

1. warm-start D3-cluster 假设横向无限（每 leaf 32pt 独立 slot）→ 整树宽度可能 1100pt+
2. post-clamp 把超出节点全压到屏边 → 同 edge 上多个节点堆叠
3. relaxation soft 4 同 depth bucket sort 后改 x 不重排 → 收敛错乱
4. soft 3 父向 clamped children avg 拉 → 整树向某半屏漂

**根本错误**：先算 x 再裁边。

## v8 正确做法（4 铁律）

1. **children 必须先分 band 再算 x**（不能算了再 clamp）
2. **parent.x 来自 banded children anchors**（不是原始 ideal x）
3. **每个 parent 的 overflow 只影响局部子树**（不全局 relax）
4. **edge routing 用 shared stem/bus**（先做主算法，bus 可选阶段 B）

---

## 算法（3 阶段纯函数）

### 阶段 1: measureSubtree (bottom-up O(n))

```
measure(n):
    if leaf: n.subtreeWidth = minChildW; return
    for c in children: measure(c)
    sum = sum(c.subtreeWidth) + hSpacing × (n.children.count - 1)
    n.subtreeWidth = max(minChildW, min(sum, maxWidth))  // cap 到屏宽
```

### 阶段 2: packChildrenIntoBands (top-down recursive)

```
place(n) -> subtreeMaxY:
    if leaf: return n.y
    
    # 把 children 分成 bands，每 band 总宽 ≤ maxWidth
    bands = packBands(n.children)
    
    subtreeMaxY = n.y
    nextY = n.y + vSpacing
    for band in bands:
        bw = bandWidth(band)
        startX = n.x - bw/2   # 中心对齐到父
        startX.clamp([0, maxWidth - bw])  # 屏宽限制
        x = startX
        bandMaxY = nextY
        for c in band:
            w = max(minChildW, c.subtreeWidth)
            c.x = x + w/2
            c.y = nextY
            cMaxY = place(c)  # 递归 — 子树自己也可能 banded
            bandMaxY = max(bandMaxY, cMaxY)
            x += w + hSpacing
        subtreeMaxY = max(subtreeMaxY, bandMaxY)
        nextY = bandMaxY + bandRowGap   # 下一 band 起点
    return subtreeMaxY
```

### 阶段 3: collectVisible (已有，不变)

用 n.x/n.y 直接收集。

---

## 关键参数

- maxWidth = geometry.width - 48  (左右 24 padding)
- hSpacing = 32pt
- vSpacing = 60pt
- bandRowGap = 30pt（同 fork 下不同 band 行间额外间距）
- minChildW = 36pt

---

## Task

- [ ] T1. TidyNode 加 `var subtreeWidth: Double = 0`
- [ ] T2. 删 layoutPass + applyOverflowFallback
- [ ] T3. 加 layoutBandedTidyTree(root, maxWidth, ...)
- [ ] T4. computeLayout 调用 layoutBandedTidyTree 替换
- [ ] T5. 双端 build
- [ ] T6. commit + push

## 阶段 B（看 v8 效果后再加）

- bus / shared stem edge routing：overflow child 的 edge 从父出一段 stem 再分叉
- 拖动节点

---

## 不做

- ❌ relaxation iteration（v7 的方向，根本错）
- ❌ 全局 force sim
- ❌ JS / WebView / D3 嵌入
- ❌ ELK / dagre / Sugiyama（重型；不解决屏宽 fit）
- ❌ d3-flextree（横向无限假设，同问题）

---

## 参考

- Hermes 咨询答复（"tidy tree with bounded-width sibling row packing and curved edge routing"）
- pvigier commit graph drawing（lane assignment 思路；不直接套用）
- d3-flextree（O(n) variable width；不解决屏宽 fit）
- van der Ploeg 2013 "Drawing Non-layered Tidy Trees in Linear Time"

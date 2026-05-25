# Plan：BranchMapSheet v6 — Tidy Tree + 保拓扑展开

**日期**：2026-05-10
**前置**：v1 list / v2 mini-rail / v3 git-graph / v4 file-tree / v5 outline 全废
**spec**：粟粟 v2 需求文档（本对话上文）+ Q1-Q8 答案
**核心放弃**：lane × 60、"主线 lane=0"特权、location 概念
**核心采用**：Reingold-Tilford Tidy Tree → 整棵树自由排版；currentPath 只是视觉高亮

---

## Task

- [ ] T1. ConversationViewModel 加 `navigateToNode(_ nodeId:)`：通用"切到该节点 = 重算 currentPath"入口（复用 navigateToSearchResult 内部 buildPath 逻辑）
- [ ] T2. 重写 BranchMapSheet.swift：
    - T2.1 数据结构：`TidyNode`（id, children, isCollapsed, foldedCount, x, y, contentPreview, isOnCurrentPath, isPinned）
    - T2.2 currentPath 折叠预处理：识别 currentPath 上连续 (children==1 && !fork && !branchHead && !pinned) 段 → 一个 collapsed visual node
    - T2.3 Reingold-Tilford 算法：postorder 算 prelim+mod → preorder 累积得 final x
    - T2.4 Overflow fallback：检测 same-depth 总宽 > screen → 超出 children y +20pt 偏移
    - T2.5 Canvas 渲染：连接线 cubic bezier、节点 Circle、currentPath 黄色加粗（2pt）vs 灰色细线（1pt）
    - T2.6 交互：tap = 切 currentPath（动画 0.2s）；long press 0.3s = 展开卡片
    - T2.7 卡片：200×120 ZStack 浮上层，含 preview/timestamp/pin/「切到这条路径」按钮
    - T2.8 FIFO 队列 maxExpanded=4
- [ ] T3. ContentView：BranchMapSheet callback 接口改 → onNavigateToNode(nodeId)
- [ ] T4. 删 v5 outline 残留代码（OutlineRailCanvas / BranchEntryNode / VisibleRow / buildTree / flatten）
- [ ] T5. 双端 build (macOS + iOS Simulator)
- [ ] T6. commit + push

---

## 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 树根 | `cachedRootId`（ChatGPT 导入的根）| spec 明确"根节点 parent=nil" |
| 节点 id 类型 | `String` | 项目现状 |
| 横向 spacing | 24pt（节点直径 8 + 留 16）| 屏宽 ÷ 16 lane = 24pt |
| 纵向 spacing | 60pt | spec 给定 |
| 折叠 affordance | 中点 ↕N 标签 | spec 给定 |
| currentPath 颜色 | 主题黄色（Theme.favorite）| 跟 BranchIndicator 区分（branchIndicator 是绿）|
| Overflow 触发 | depth 总宽 > geometry.width - 32 | spec 给定 |
| Overflow 偏移 | y +20pt 累加 | spec 给定 |
| FIFO 上限 | 4 默认；屏宽自适应 [3,5] | spec 给定 |

---

## Reingold-Tilford 简化版

完整 RT 算法涉及 contour/threading 太重。采用 Walker 简化版：
1. 后序：每个 leaf x=自分配的 slot；internal x = average(children mid)
2. 冲突检测：相邻兄弟子树最右 contour vs 最左 contour，差 < spacing 时把右子树整体右移
3. 前序：累积 modifier 得 final x

实测如有问题再 fallback 到"每 leaf 占 1 unit"的纯 layout。

---

## 不做（spec 排除项）

- ❌ 完整内容查看（卡片只有 80 字 preview）
- ❌ 节点合并/删除/移动
- ❌ 跨对话关联
- ❌ 自动注入上下文
- ❌ lane/depth 持久化（spec 明确删除）
- ❌ 横向 scroll（用 overflow fallback 替代）

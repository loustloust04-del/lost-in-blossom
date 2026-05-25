# Plan：BranchMap v9 — 折叠规则跟 currentPath 解耦

**日期**：2026-05-17
**前置**：v8 banded layout 已搞定屏宽 fit；但切分支节点乱跳/折叠奇怪
**根因**（ultrathink 已诊断）：layout 跟 currentPath 强耦合 — 切 path 时 buildTree 重新决定哪些节点折叠成 chain，TidyNode 数量/拓扑变 → place 算出新 x/y → 整树突变 = 你看到的"乱跳/找不到路"
**粟粟方向**：选 A — 折叠规则跟 currentPath 解耦

---

## 改动核心

折叠条件：去掉「在 currentPath 上」的硬要求，改成「任意 single-child + 非 pinned + 非 branchHead」。
高亮颜色：collapsed 段「整段全在 currentPath 才高亮」（all in path），否则灰色。

切 path 后：
- 树形状（节点 x/y）完全不动 ← 解决"乱跳"
- 只是黄色 path 重新算 ← 视觉清楚"切了哪条"
- 顶部预览卡更新 lastTappedNodeId 节点内容

---

## Task

- [ ] T1. `isFoldable` 删 `guard currentPathSet.contains(id) else { return false }` 这一行
- [ ] T2. `computeLayout` 删 `let currentPathSet = snapshot.currentPathIds`（buildTree 不再用）
- [ ] T3. `isOnVisualPath` 改用 `allSatisfy` 代替 `contains(any)`：collapsed 段整段在 path 才算 on path
- [ ] T4. `isEdgeOnPath` 同步改 `allSatisfy`（fromOn / toOn 用 collapsedNodeIds.allSatisfy）
- [ ] T5. 双端 build
- [ ] T6. commit + push

---

## Trade-off

| 项 | 改前（v8） | 改后（v9）|
|---|---|---|
| 切分支时节点位置 | 乱跳 | 不动 |
| 切分支时颜色 | 重算 | 重算（不变）|
| 非主路径上的 single-child chain | 全画点（5 个 dot 一长串）| 折叠成 ↕5 一个点（可点开看）|
| 跟 v2 spec "非 currentPath 节点都画点" | 一致 | 偏离（但点开能看，且整树稳定）|

---

## 视觉补充

切 path 后 collapsed chain 可能：
- 整段全在新 path → 黄色 ↕N
- 整段全不在新 path → 灰色 ↕N
- 部分在 path（chain 头/尾在）→ **灰色 ↕N**（用 `allSatisfy` 而非 `any`，否则视觉误导）

边 edge 同理：fromNode / toNode 都「整段在 path」 → 黄色加粗 bezier；否则灰色细线。

---

## 不做

- ❌ 重新设计 v8 banded layout（已经够好）
- ❌ matchedGeometryEffect 平滑过渡（折叠解耦后无需）
- ❌ 拖动（Phase B 还在排队）
- ❌ bus / shared stem 边路由（看 v9 效果再说）

# Research：BranchMap constraint-based layout

**日期**：2026-05-13
**起因**：粟粟反馈 v6.7 节点漂出右半屏；要 constraint-based layout（拓扑约束 + 屏宽约束）+ bezier 自由连接 + 可拖动
**前置**：v6 Tidy Tree 已建立基础（节点 (x,y) + bezier 已用 + 拖动尚无）

---

## 一、业界对标

### cola.js / WebCola（JS）
学术界做这类的最成熟实现。三种约束：
- **Separation**：`{axis: "y", left: 0, right: 1, gap: 25}` → `node[0].y + 25 ≤ node[1].y`（不等式）/`equality: true` 转等式
- **Alignment**：一组节点对齐到同一 x 或 y 轴
- **Group**：节点装进矩形组（可嵌套）

求解器：**stress majorization**（梯度下降一类），收敛到局部最优。

→ "父在子上方"用 separation (axis=y, gap=60) 表达
→ "屏内"是 hard constraint，cola.js 用 `boundary` 表达
→ 拖动：拖时该节点 `.fixed = true`

### SwiftUI 实现参考
- **rayfix/ForceDirectedGraph**：Canvas + TimelineView 持续物理 sim（弹簧 + 排斥）
- **nmandica/DirectedGraph**：SPM 包，directed graph 展示
- **Kodeco Mind-Map UI 教程**：拖动 textbox + 节点 + 连接线
- **Joe Crozier 物理 sim 文章**：Hooke 弹簧 / Coulomb 排斥

### Force-directed 物理模拟
- Hooke's law（弹簧）：连接节点吸引到 ideal distance
- Coulomb's law（排斥）：所有节点对推开（防重叠）
- 重力 / 边界推 / 拖动 = 固定该节点
- 性能：N² = 200²=40k ops/iter，60 iter 收敛 = 2.4M ops（≈ 50ms 现代 iPhone）

---

## 二、我们要什么 vs 不要什么

### 要
- 任何节点 x ∈ [margin, screenW - margin]（hard）
- 父 y < 子 y - vSpacing（hard，保拓扑）
- 同父 children 围绕父 x 均匀分布（soft，让 fork 看起来对称）
- 同 depth 兄弟 x 距 ≥ minSpacing（soft，防重叠）
- 连接线 cubic bezier（已有）
- 拖动节点（粟粟提到）

### 不要
- 持续物理 simulation（耗电、视觉跳）
- N² 排斥所有节点对（200 节点不必要，约束是 local 的）
- 跨 conv 联动（本视图 scope 之外）

→ **不做完整 force-directed**。做 **one-shot constraint relaxation**：初始 Tidy Tree → 迭代 30-60 次满足约束 → 静态画。

---

## 三、推荐算法

### Phase 0: 初始化（已有 = Tidy Tree D3-cluster）
每 leaf 占一个槽位 hSpacing*32pt，internal node x = avg(children x)。

### Phase 1: One-shot relaxation（新增，30-60 iter）

```
for _ in 0..<60 {
    // Constraint 1: y 拓扑（父 < 子）— hard
    BFS：对每个节点 c，若 c.y < c.parent.y + vSpacing，
         c.y = c.parent.y + vSpacing（连带 c 子树整体下移）

    // Constraint 2: 屏宽 — hard
    对每个节点：x.clamp([leftPad, screenW - rightPad])

    // Constraint 3: 同 depth 防重叠 — soft
    按 y 桶分组；每组内按 x 排序；相邻距 < minSpacing 时互推
    （前推 -half，后推 +half）

    // Constraint 4: 同父 children 围绕父 x — soft（拉父向子均值）
    n.x += (avg(children.x) - n.x) * 0.15
    
    // Constraint 5: overflow 错位 — 当 same-depth 桶宽度仍超屏 → 
    // 把最远 child 的 y 加 jitter（20pt），打散到下一行
}
```

Constraint 1+2 是 hard；3+4+5 是 soft 松弛力。每 iter 顺次施加，60 次后收敛。

### Phase 2: 拖动（nice-to-have，分期）
- DragGesture：拖时 `draggedNodeId = vn.id`，该节点 x/y 跟手指
- 松手：`draggedNodeId = nil` + 再跑一次 relaxation 让别人适应
- 拖动该节点时其他节点不动（lock pose）

---

## 四、性能估算

- 200 节点 × 60 iter
- Constraint 1+2：O(N) = 12k ops
- Constraint 3：O(N log N) sort + O(N) = 200×8=1600 + 200 = 1800 ops × 60 = 108k
- Constraint 4：O(N) = 12k
- 总 ≈ 200k ops = < 5ms 在 iPhone 17

初次 sheet 打开 layout 一次；之后切 currentPath 颜色变（不重 layout）；拖动后再 layout 一次。流畅。

---

## 五、SwiftUI 集成

- TidyNode 已是 class（mutable x/y）→ 直接 mutate
- Layout 在 BranchMapSheet.computeLayout 内 1 次（已有调用点）
- relaxation 加在 Tidy Tree pass 之后，applyOverflowFallback 替换
- bezier 已用，不变
- 拖动：每个 nodeView 加 `.gesture(DragGesture)`；移到拖动模式时禁用 tap

---

## 六、风险

1. **soft constraint 权重调不好** → 节点跳来跳去 / 收敛不到。需要 60 iter 后看视觉，可加阻尼系数
2. **过深嵌套 vSpacing 60pt × 30 层 = 1800pt 高** → 树太高竖滚很远，但可接受
3. **同 fork 8+ children** → 屏宽不够，错位机制（constraint 5）必须工作；视觉会不像草图整齐
4. **拖动** → 释放后跑 relaxation 节点会"弹"到约束位置；用户可能困惑（要不就锁死拖到的位置不再 relax）

---

## 七、建议实施顺序

**Phase A**（本次）：Phase 0 + Phase 1（hard + soft 约束 relaxation）
- 解决"漂屏外"问题
- 无拖动
- 改动 ≈ 150 行（替换 applyOverflowFallback）

**Phase B**（看效果后追加）：拖动
- DragGesture per node
- 拖动时该节点 fixed
- 松手 relax / 不 relax（粟粟拍板）
- 改动 ≈ 50 行

---

## Sources

- [cola.js — Constraint-based Layout in the Browser](https://ialab.it.monash.edu/webcola/)
- [WebCola Constraints Wiki](https://github.com/tgdwyer/WebCola/wiki/Constraints)
- [rayfix/ForceDirectedGraph — SwiftUI 实现](https://github.com/rayfix/ForceDirectedGraph)
- [nmandica/DirectedGraph — SPM 包](https://github.com/nmandica/DirectedGraph)
- [Creating a Mind-Map UI in SwiftUI — Kodeco](https://www.kodeco.com/7705231-creating-a-mind-map-ui-in-swiftui)
- [Force Directed Graphing in iOS — Joe Crozier](https://medium.com/@joecrozier/force-directed-graphing-in-ios-11202e6e3c48)

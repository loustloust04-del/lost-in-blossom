# Plan：BranchMapSheet v3 — 真 Git-graph 多 column

**日期**：2026-05-08
**关联**：B20 part 2 收尾（粟粟反馈 v2 仍像"列表加缩进"，要"跟左边那条一样"的 lane）
**v1 plan**：`docs/plan-branch-map-and-flow-chips.md`（commit 6ebb901）
**v2 plan**：`docs/plan-branch-map-v2-minimap.md`（commit 33a95b1）
**v3 目标**：每条分支独立 lane，可视化接近 git commit graph
**预计工作量**：1-1.5 天

---

## 一、为什么 v2 仍然"不像"

### v2 现状

```
●        主线 column 0
│
●        在第 4 条
│
●        在第 6 条
│ ╲
│  ●     └─ 嵌套 (col 1)
│  │
│  ●     └─ 嵌套 (col 1)  ← 同 depth 嵌套都挤在 column 1
│
●        在第 7 条
```

### 缺什么（粟粟想要）

| v2 现状 | 真 git-graph |
|---|---|
| 同 depth 嵌套全挤 column 1 | 每条分支独立 lane |
| lane line 只在该 row 出现 | lane 持续多 row（分支生命周期）|
| 嵌套分支用 depth 表达层级 | 用 column 索引 + anchor 连接表达 |
| 看起来"列表加左侧装饰" | 看起来"swimlane 时间轴" |

---

## 二、Git-graph 算法核心

### Lane assignment（swimlane）

```
活跃 lanes 池 = []
for row in 按时间序排列的所有 entry:
    if row 是分支起点:
        # 找最小空闲 lane（贪心）
        lane = min { i | i 不在 活跃 lanes }
        分配 lane 给该 branch
        加入活跃 lanes 池，记 endRow（branch lifetime 终点）
    if row 是分支终点:
        从活跃 lanes 池移除
```

### Branch lifetime 怎么定？

候选：

| 方案 | lifetime | 优 | 劣 |
|---|---|---|---|
| **L1 单行** | 仅 entry row 自己 | 简单；lane 永远空，可重用；图很扁 | 跟 v2 一样退化（每行 dot 不连续）|
| **L2 到下一 anchor** | 起点到下一个出现的分支 row | 视觉连续；可压缩 column 数 | "下一 anchor"语义不清 |
| **L3 整个分支长** | 起点 + branchLength 行 | 最像 git；行数随长度 | 行数爆炸（251 节点对话可能 50+ 行）|
| **L4 起点到对话末尾** | 永久活跃 | 简单；column 永不复用 | column 数 = 分支总数（17 条 = 17 列）|

**推荐 L4**——每条分支独立 column，简单、最像 git graph 的视觉感（每条 lane 一直贯穿到底）。column 数 = 17 看似多但 iOS 横向 scroll 能装。

### 接入弧（lane 起点连到 parent lane）

每条 branch 起点 row：
- 自己的 lane 画一条横线/弧线连到它的 parent lane
- depth=0 分支：parent = 主线 lane 0
- depth>0 嵌套分支：parent = 包含它的上层分支 lane

---

## 三、目标 UI

```
0  1  2  3  4  5  6  7  ← lane index
●                          主线
│
●                          在第 4 条 (anchor，主线 dot)
│
●─┐                        在第 6 条 (开 lane 1)
│ │
│ ●                        └─ 在第 6 处分支 (depth=0, lane 1)
│ │
●─├─┐                      在第 7 条 (开 lane 2)
│ │ │
│ │ ●                      在第 7 处分支 (depth=0, lane 2)
│ │ │
│ │ ├─┐                    嵌套 anchor (lane 2 内开 lane 3)
│ │ │ │
│ │ │ ●                    └─ 嵌套 (depth=1, lane 3)
│ │ │ │
●─┼─┼─┼─┐                  在第 12 条 (开 lane 4)
│ │ │ │ │
│ │ │ │ ●                  在第 12 处分支
│ │ │ │ │
│ │ │ │ │
●─┴─┴─┴─┘                  主线终点（所有 lane 闭合到主线）
```

每个 lane 一直从开启延伸到主线末尾（L4 lifetime）。

iOS 屏宽 420pt，每 lane 宽 18pt，17 lane = 306pt + rail 边距 ≈ 360pt，主线右侧文字预览 ≈ 230pt → 总 590pt → **超屏**。横向 ScrollView 必备。

或者：sheet 拆成"上半 git-graph rail（横滚）+ 下半文字 list（纵滚）"。或：rail + 文字一起横滚（同步 scroll）。

---

## 四、Task checklist

### [ ] T26. ConversationViewModel.collectAllBranches() 增强

返回的 entry 加 lane 字段：

```swift
struct AllBranchEntry: Identifiable {
    ...existing fields...
    var lane: Int = 0          // 新增：lane assignment 结果
    var parentLane: Int = 0    // 新增：parent branch 的 lane（接入弧用）
}
```

DFS 后做 lane assignment（L4 算法）：
- 主线 lane = 0
- 按 entry 的 (location asc, depth asc) 排序
- 每条 branch 分配 lane = 已用 lane 最大值 + 1（每条独立）
- parentLane：depth=0 → 0；depth>0 → 其包含的上层 branch 的 lane

简化：因为 L4 lifetime 永久，lane assignment 实际是"按顺序自增"。

### [ ] T27. BranchMapRail v3 重写

支持每行画多条 lane line + 自己的 dot：

```swift
struct BranchMapRailRow: View {
    let myLane: Int                    // 自己 dot 的 lane
    let activeLanes: Set<Int>          // 该行所有应画线的 lane
    let parentLane: Int?               // 起点行画接入横线/弧从 parentLane 到 myLane
    let isFirstAtLane: Bool            // 自己 lane 在本行第一次出现 → 上半不画线 + 画接入
    let kind: Kind
    let totalLanes: Int                // rail 总宽 = totalLanes × spacing + padding
    let isFirst: Bool                  // 整列第一行
    let isLast: Bool                   // 整列最后一行
    ...
}
```

绘制：
1. 对每个 active lane：画垂直线（isFirst→上半不画，isLast→下半不画，isFirstAtLane→上半不画）
2. 在 myLane 位置画 dot（kind 决定大小颜色）
3. parentLane != myLane 时画接入弧（从 (parentLane, top) 到 (myLane, mid)）

### [ ] T28. BranchMapSheet 算 row 的 active lanes 集合

```swift
// 在 mapRows 计算时：
// 累积已开 lane → 每行 activeLanes = 主线 + 所有已开未关的 branch lane
var activeLanes: Set<Int> = [0]
for row in rowsByLocation {
    if row.kind == .branch {
        // L4: branch 一旦开启永久活跃
        activeLanes.insert(row.lane)
    }
    row.activeLanes = activeLanes
}
```

### [ ] T29. 横向 ScrollView 包 rail 让窄屏也能看完整

iOS 屏宽 420pt，预计 17 lane × 18pt + 14padding + 文字预览 200pt = 540pt → 超 120pt。

方案：
- 整个 sheet 横向 ScrollView 包，文字 row 跟 rail 一起横滚（保持对齐）
- 或：rail 单独横滚，文字固定在右侧（不滚，"标签型 row"）

**推荐方案 A**（整体横滚）：保持 rail 跟文字 row 的视觉绑定。横滚指示器隐藏，提示用户"可以左右拖看完整图"。

### [ ] T30. 双端 build + 真机验证

- [ ] 进金瓶梅对话 → 点 🌿 → 看到多 column git-graph
- [ ] 嵌套分支独立 column（不挤同 column）
- [ ] 主线 lane 0 一直贯穿
- [ ] 每条分支 lane 从起点延伸到底
- [ ] 接入弧从 parent lane 弯到 child lane
- [ ] 横向滚动 → 能看完所有 lane
- [ ] 点行任何位置 → 切到那条分支 + toast
- [ ] 没分支的对话按钮仍隐藏

---

## 五、决策点（粟粟拍板）

### Q1：lifetime 选哪个

| 选项 | 视觉 | 复杂度 |
|---|---|---|
| L4 永久（每条分支独立 lane）✓ 推荐 | 17 lane 都贯穿到底 | 简单 |
| L2 到下一 anchor | lane 数能压缩到 ~5 | 中 |
| L3 真 branch 长度 | 每条分支占 N 行 | 复杂；行数爆炸 |

### Q2：横向超屏怎么处理

| 选项 | 长这样 |
|---|---|
| A 整体横滚 ✓ 推荐 | rail+文字一起拖 |
| B rail 横滚 + 文字固定 | rail 滚动时文字不动；可能感觉错位 |
| C 缩小 lane spacing 到 12pt | 17 lane = 204pt 可塞下，但 dot 拥挤 |
| D row 高度变小 + lane spacing 8pt | 极致压缩，可能丑 |

### Q3：文字 row 还需要"在第 X 条 / 共 Y 条"吗

git-graph 视觉强了，文字可以精简：
- 选项 X：保留全文字（位置 + 长度 + 预览）
- 选项 Y：只 "···预览···"（位置/长度信息已视觉表达）
- 选项 Z：不显示文字，只 git-graph + tap 后弹气泡详情

**推荐 X 保留**——文字 fallback 永远比纯图直觉。

### Q4：嵌套分支的接入弧从哪条 lane 弯过来

- 选项 P：从主线 lane 0 弯出（不区分嵌套深度）
- 选项 Q：从包含它的"父 branch" lane 弯出 ✓ 推荐
- 选项 R：双重接入弧（parent 父 + 主线连接）

**推荐 Q**——表达"分支的分支"层级关系。

---

## 六、风险

1. **lane 数过多挤屏**：17 条分支 → 17 lane → 横滚必备。如果未来某对话 50+ 分支会更挤；可加 lane 压缩算法做 fallback。
2. **lane assignment 算法错误**：DFS 收集 + 排序 + 分配三步任一出 bug 都视觉错乱。要对照测试金瓶梅的 17 条预期 lane 排布。
3. **接入弧 parent lane 算错**：嵌套时 parentLane 必须是包含它的上层 branch 的 lane（不是 lane 0）。算 nesting 关系时要回溯 parentAnchorOnMain 链。
4. **Canvas 性能**：每行画 17 条 line + 1 dot + 接入弧 ≈ 20 stroke 操作。20 行 = 400 ops，无压力。
5. **横向 scroll 跟 SwiftUI sheet 兼容**：`.presentationDetents([.medium, .large])` + 内部横向 ScrollView 应该 OK，但需要测，若冲突可砍 detents 留 .large。

---

## 七、跟 v1/v2 的关系

- v1 sheet 入口（🌿 按钮、ContentView 的 sheet binding）保留不动
- v2 的 collectAllBranches() 复用 + 加 lane 字段
- v2 的 BranchMapRail.swift 整个重写
- v2 的 BranchMapSheet 内部 rowView 重写

---

## 八、不做的事

- ❌ Lane 复用算法（L1/L2 lifetime）— 等真有 50+ 分支挤显时再加
- ❌ 横向 zoom / pinch — iOS 26 sheet 内 zoom 复杂
- ❌ Lane 颜色编码（不同分支不同色）— 暖奶白系不适合花花颜色
- ❌ Anchor row 的 child branches 折叠展开 — 不是常见交互
- ❌ macOS 同步升级 — 等 iOS 验证后再扩

---

## 九、实施顺序

```
T26 (lane assignment)
  → T28 (sheet 算 activeLanes)
  → T27 (rail 重写支持多 lane)
  → T29 (横向 ScrollView)
  → T30 (验证)
```

T26 + T28 是数据层；T27 + T29 是视觉层。建议数据层先 commit + console 打印 lane 分配验证算法对，再做视觉层。

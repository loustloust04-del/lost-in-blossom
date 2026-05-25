# Plan：BranchMapSheet v2 — Mini-map 视觉化

**日期**：2026-05-08
**关联**：B20 part 2 收尾（粟粟反馈 v1 sheet "不直觉"）
**v1 plan**：`docs/plan-branch-map-and-flow-chips.md`（已实施 commit 6ebb901）
**预计工作量**：5 个 task，~半天

---

## 决策定档（粟粟已拍）

| Q | 选项 | 决策 |
|---|---|---|
| 交互模型 | i 整行可点 / ii 整行+rail 都可点 / iii 全图交互 | **i 整行可点，rail 是视觉装饰**（iii 留以后大屏做） |
| Q1 "你在哪" hint | A1/A4/A5 | **A4 highlightedNodeId** |
| Q2 mini-map 形态 | B1 整段 Canvas / B2 inline rail | **B2 inline rail** |
| Q3 高亮"你附近的分支" | 是/否 | **是** |
| Q4 第一版 zoom | 是/否 | **否** |

---

## 一、为什么 v1 不直觉（现状诊断）

v1 BranchMapSheet 是 **纯文字 List**：

```
路径
─────────────
主线 ✓             共 180 条
─────────────
🌿 在第 12 条气泡处   共 28 条
   "他突然站起来..."
🌿 在第 47 条气泡处   共 50 条
   "你想吃糖吗..."
🌿 在第 89 条气泡处   共 38 条
   "林黛玉冷笑..."
```

缺什么：
- ❌ **位置感**：「第 47 处」是数字，扫描时要在脑里换算 47/180=26%
- ❌ **树形关系**：分支跟主线的视觉关系是文字而非图形
- ❌ **当前位置锚**：你正在看主线的哪条，sheet 里没标
- ❌ **附近感**：在你附近的分支没有"亲密度"提示

---

## 二、prior art 调研（上一轮 web 检索）

| 工具 | 方案 | 借鉴 |
|---|---|---|
| **opcode** ([opcode.sh](https://opcode.sh/)) | git-like commit graph，横向 timeline + 纵向分支 | 视觉化树形思路 ✅ |
| **LibreChat** | fork 成独立对话；MindMap (ReactFlow) 是实验 | 不适合，我们要在原对话内可视化 |
| **LangChain** | 每条 message inline `◀ 1/2 ▶` 紧凑切换器 | 已有（每条 bubble 下"🌿 N 条分支" chip）✅ |

结论：opcode 的 git-graph 思路最契合，但 iOS 屏幕小、节点数多（251）不能全画出来。**简化为左侧 mini-map（主线粗线 + 分支细线 + 节点小圆点）+ 右侧文字 list。**

---

## 三、目标 UI（β 方案 ASCII mock）

```
┌──────────────────────────────────────────────┐
│  分支地图                              完成   │
├──────────────────────────────────────────────┤
│  当前对话                                     │
│  金瓶梅话本 🔞                                │
│  主线 180 条 · 分支 3 条                       │
├──────┬──────────────────────────────────────┤
│      │                                       │
│  ●   │  ✓ 主线                               │
│  │   │     共 180 条                          │
│  │   │                                       │
│  ●╲  │  🌿 在第 12 条气泡处                   │
│  │ ╲ │     "他突然站起来，从背后..."           │
│  │  ●│     共 28 条                          │
│  │   │                                       │
│ ━●━━ │  📍 你在第 47 处（高亮 / 灰底）         │
│  │ ╲ │                                       │
│  │  ●│  🌿 在第 47 条气泡处                   │
│  │   │     "你想吃糖吗，宝宝..."              │
│  │   │     共 50 条                          │
│  │   │                                       │
│  ●╱  │  🌿 在第 89 条气泡处                   │
│  │ ╱ │     "林黛玉冷笑，从袖中..."            │
│  ●   │     共 38 条                          │
│  │   │                                       │
│  ▼   │                                       │
└──────┴───────────────────────────────────────┘
```

要素：
- **左侧 ~70pt mini-map column**：垂直占整个 sheet 高度
  - 主线一条粗线（4pt）从顶到底，颜色 `Theme.branchIndicator`
  - 主线上等距分布几个小圆点（不画 180 个，画 6-8 个 markers 即可）
  - 分支 anchor 位置画一个稍大圆点（6pt）
  - 从 anchor 圆点斜出一条细线（1.5pt）+ 末端小圆点表示分支
  - "你在哪"位置画一个亮黄/绿（用 Theme.branchIndicator 增强色）的横线 marker
- **右侧 list**：跟 v1 一样的内容（主线 row、分支 row），每条 row **垂直居中对齐**到左侧 mini-map 上对应位置（关键！）

---

## 四、关键技术问题

### A. "你在哪"位置怎么得到

候选：
- A1：`viewModel.scrollToNodeId` — 上次 scroll 目标，但 user 滚动后 stale
- A2：在 CardFlowView 加一个 `lastVisibleNodeId` 跟踪 scroll 位置 — 工程大
- A3：`viewModel.currentPath.last?.id` — 简单但永远是末尾不准
- A4：**用 viewModel.highlightedNodeId**，最近高亮的那条 ≈ 用户最近交互过的（够用）
- A5：sheet 打开时，**算最接近 viewport 中心的 bubble**（用 stickerVM.bubblePositions）— 复杂但准

**推荐 A4**：highlightedNodeId 在搜索点击 / pin 跳转 / branch 切换 时都会设，3s 后清空但 sheet 内可以保持读取最后一次。如果 nil 就**不画"你在哪"标记**。简单、无 false positive。

### B. mini-map 高度跟右侧 list 怎么对齐

挑战：右侧 list 高度是动态的（分支数 × row 高度），左侧 mini-map 要跟它一样高。

解法：
- mini-map 不用 SwiftUI ScrollView 内做（会跟 List 滚动冲突）
- 改用 `HStack { miniMap; List }` ，mini-map 作为 List 的 leading sibling
- mini-map height = List total height ⇒ 用 `GeometryReader` 测 List 高度，或者用固定每 row 高度算
- **更简单**：每条分支 row 的左侧画一个小段线 + 圆点，主线一段段拼起来（不需要 GeometryReader）

二选一：
- **B1 整段 mini-map column**：左侧一整列 Canvas/Path 画完所有线 + dots
  - 优点：分支线斜叉的视觉最像 git graph
  - 缺点：要测 List 总高度，处理对齐
- **B2 每行左侧 inline 节点**：每条 row（主线 row + 分支 row）的左侧 24pt 画一个小段（垂直线 + 圆点）
  - 优点：跟 SwiftUI List 天然对齐
  - 缺点：分支斜叉视觉缺失，看起来是"列表加图标"

**推荐 B2**：用 List 自然对齐，每行左侧 30pt 区域画一个垂直占满的细线 + row 中央放一个 dot，分支 row 的 dot 和上方 anchor row 用一条短斜线 / chevron 连。性能/复杂度低 90%，视觉损失可接受。

```
┌─────┬────────────────────┐
│  │  │ ✓ 主线              │
│  ●  │   共 180 条          │
│ /│  │                    │
│ ●│  │ 🌿 在第 12 处        │
│  │  │   "他突然..."        │
│  │  │   共 28 条           │
│  ●  │ 📍 你在第 47 处      │
│ /│  │                    │
│ ●│  │ 🌿 在第 47 处        │
│  │  │   "你想吃糖吗..."    │
│  │  │   共 50 条           │
│  │  │                    │
│  ●  │ 🌿 在第 89 处        │
└─────┴────────────────────┘
```

### C. 排序

按 `entry.location` 升序（v1 已经这样了）。主线 row 第一个，分支按出现位置从上到下。"你在第 X 处" 的标记插入到 location ≤ X < 下一条 anchor location 的位置。

### D. 颜色

memory 提示：暖奶白 + 浅灰薄荷，不要蓝色不要黄色。

- 主线 dot/line：`Theme.branchIndicator`（已有的绿薄荷）
- 分支 dot/line：`Theme.branchIndicator.opacity(0.6)` 或 `Theme.textMuted`
- 你在哪标记：`Theme.branchIndicator` 实心 + 加 inset border
- 高亮"你附近的分支"（可选）：分支 row 整行 `Theme.mainBg.opacity(0.5)` 微底色

---

## 五、Task checklist

### [ ] T18. 新建 BranchMapMiniMap rail 组件

新建 `MemoryPalace/Views/BranchMapRail.swift`：

```swift
struct BranchMapRailRow: View {
    enum Kind {
        case main
        case branchAnchor    // 分支 anchor 节点（主线上）
        case branch          // 分支末端节点（不在主线上）
        case currentPos      // "你在哪" 标记
    }
    let kind: Kind
    let isFirst: Bool
    let isLast: Bool
    let connectAbove: Bool   // 上方需要连分支斜线
    let connectBelow: Bool   // 下方需要连分支斜线

    var body: some View {
        Canvas { ctx, size in
            // 画垂直主线（顶到底，根据 isFirst/isLast 调整）
            // 画 dot（kind 决定大小/颜色）
            // 画斜线（connectAbove/Below）
        }
        .frame(width: 30, height: 56)   // row 高度由父 List 决定
    }
}
```

每条 List row 左侧塞一个 BranchMapRailRow，参数由 row 序号 + entry kind 决定。

### [ ] T19. ConversationViewModel 提供"当前位置 hint"

```swift
/// "你在哪"位置的 hint。
/// 用 highlightedNodeId（最近交互的 node）。nil 则 sheet 不画 marker。
/// 不依赖 scroll viewport（实现复杂、收益低）。
var currentPositionHint: String? {
    highlightedNodeId
}
```

### [ ] T20. BranchMapSheet 重构

把 v1 的 List 结构调整为：
- 一个统一的 `[BranchMapRow]` 数组（包括主线、所有分支、可选的"你在哪"marker）按 location 排序
- ForEach 每条 row 渲染 `HStack { BranchMapRailRow(...); BranchMapRowContent(...) }`
- "你在哪" marker row 单独样式（无 anchor 圆点，整行底色）

数据流：

```swift
struct BranchMapRow: Identifiable {
    let id: String
    let location: Int      // sort key
    let kind: BranchMapRailRow.Kind
    let title: String
    let preview: String?
    let length: Int?
    let action: () -> Void
}
```

`buildRows()` 把主线、分支、currentPos hint 拼成一个数组返回。

### [ ] T21. 移除 v1 sheet 的 Section/List 结构改用 ScrollView+VStack

iOS List section header 跟 mini-map rail 对齐很难（section spacing 可变）。直接 ScrollView + VStack 自己控间距更可控。

### [ ] T22. 双端 build + 真机验证

- [ ] 进金瓶梅 → 点 🌿 → sheet 弹
- [ ] 看到左侧 rail：主线粗线 + 分支圆点 + 斜线
- [ ] 主线 row 第一个，三条分支按位置排序
- [ ] highlightedNodeId 有值时（点过某条 bubble）→ "你在 X 处" 标记出现在合适位置
- [ ] 点分支 row → 切到分支 + toast
- [ ] 没分支的对话点 🌿（按钮不显示，跳过）
- [ ] 暗黑模式下颜色对比够

---

## 六、决策定档（见文档顶部）

所有 Q1-Q4 + 交互模型已拍 → 见文档顶部"决策定档"section。
本节的旧候选选项保留作为 trace。

### 交互模型 i 的具体含义

- 整行（rail Canvas + 文字内容）作为一个 Button 区域
- rail 上的圆点 / 斜线纯装饰，**不响应单独 hit**
- 点行任意位置 → 同一个 action（切到该分支 / 切回主线）
- rail 圆点的视觉作用：让用户**一眼看清分支位置和数量分布**，不是 hit target

---

## 七、风险

1. **rail 跟 List row 对齐**：B2 用 inline rail 每 row 一个固定高度 Canvas，应该不会错位。如果分支 row 因预览高度变化高度不固定 → 用 `.frame(maxHeight: .infinity)` 让 rail 自适应 row 高度。
2. **Canvas 性能**：每行一个 Canvas，10 条以内零成本。100+ 分支才需要担心。
3. **斜线连接的视觉**：B2 没有真正的"斜叉"，是用一段 1pt 短弧/折线表示。视觉损失可接受，但比 git graph 弱一点。
4. **highlightedNodeId 3s 后清空**：sheet 打开时如果已经清空，"你在哪"标记不显示。可以接受（视觉降级，不出 false 信息）。
5. **预览高度不固定 → rail 错位**：每条 branch row 的预览 `lineLimit(2)` 强制最多 2 行，rail 高度按这个固定。

---

## 八、不做的事

- ❌ git-graph 横向 timeline（屏太窄）
- ❌ 嵌套分支可视化（v1 plan 已说明，等需求）
- ❌ Live "你在哪" 实时跟随 scroll 更新（实现复杂、收益不高，sheet 是临时打开看一眼）
- ❌ 分支预览缩略图 / 分支 message 列表展开
- ❌ macOS 同步加按钮（iOS 主用，macOS 后续）

---

## 九、实施顺序

```
T19 (currentPositionHint helper) → T18 (rail 组件) → T20 (重构 sheet 数据流)
→ T21 (List → ScrollView+VStack) → T22 (双端 build + 验证)
```

T18 + T20 是核心，可以一起做（同 commit）。其他都是辅助。

---

## 十、跟 v1 的关系

- v1 sheet 入口（🌿 N 按钮、ContentView 的 sheet binding）保留不动
- v1 的 BranchMapSheet 内部 body 重写成 v2 mini-map 版
- v1 的 ConversationViewModel.branchLength 复用
- v1 的 switchBranch / loadConversation 调用复用

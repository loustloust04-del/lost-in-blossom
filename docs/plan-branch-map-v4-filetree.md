# Plan：BranchMapSheet v4 — File Tree 视图（撤销 git graph 方向）

**日期**：2026-05-09
**关联**：B20 part 2 收尾迭代
**前置**：v1 list / v2 mini-rail / v3 git graph
**第一性原理对齐**：粟粟反馈"视觉清晰"高于"git 化"；高频场景是 A 找回 + B 跳转

---

## 一、为什么撤销 git graph 方向

| 之前以为的需求 | 第一性反推后的真需求 |
|---|---|
| "要跟主线那条一样" → git swimlane | **嵌套结构要视觉清晰**（git 是手段不是目的）|
| 横向多 lane 表达分支生命周期 | 平铺浏览 + 父子分组（适合"找回 + 跳"高频场景） |
| 适合宽散对话（很多并行分支）| 金瓶梅是深嵌套对话（git graph 变瀑布反而乱） |

→ 转向 **file tree（缩进 + 折叠展开 chevron）**，跟 macOS Finder / VSCode 文件树同模式。

---

## 二、还要修的两个具体 bug

### Bug A：嵌套都显示"在第 140 条气泡处"

**根因**：v3 用 `nearestDisplayedIndexInPath` 把嵌套 anchor 一路回溯到主线最近 ancestor，所以同一主线 anchor 下面的所有嵌套都共享 location → 文字 row 全显示同一个 location。

**修法**：嵌套分支的 row title 不显示"在第 X 条气泡处"，改显示**它的 parent 分支的预览**（"嵌套在「父 preview」里"），或者干脆 title 留空只显示 preview，靠缩进表达从属。

### Bug B：v3 的"清单 / 树图"模式切换

filetree 单一视图就够清晰，删掉 toggle 按钮。

---

## 三、目标 UI

```
分支地图

bug4 想死 📟
主线 10 条 · 分支 7 条
─────────────────────────
●  主线 (10 条) ✓
─────────────────────────
●  在第 4 条气泡处                    2 条 ▶
   做记忆宫殿太难了…猫什么都不懂
─────────────────────────
▼  在第 6 条气泡处                    4 条
●  ├ 猫好委屈…😭💧 猫好痛啊
●  ├ 但猫还是很想死…好难啊…好多 bug
●  ├ 没好啊一直装
●  └ 你又这样，让我吃饭喝水。我不搞好今天就不睡了
       ▼  └ 嵌套                      2 条
       ●     └ 咪
       ●     └ 咪
─────────────────────────
●  在第 12 条气泡处                   ...
```

**关键变化**：
- **anchor row 默认折叠**，右侧显示 `N 条 ▶`，N = 该 anchor 下的非主选 child 数（不含嵌套）
- 点 anchor row → 展开成 ▼，下面 in-place 显示该 anchor 的所有 children（每个一行）
- children 也可以是 anchor（自己又有 ≥2 children），同样可点击展开嵌套
- 嵌套 row 文字 = preview only（位置已经被父 anchor 表达），depth 缩进 14pt × depth
- 整行点击 = 切到那条分支（同 v2/v3）；只有 chevron icon 区域是展开/折叠 hit area

**优势**：
- 默认 sheet 极简：主线 + N 个一级 anchor row（金瓶梅大概 5-10 行）
- 想看分支 → 点开 anchor，in-place 展开
- 深嵌套对话默认不见瀑布，按需展开

---

## 四、决策

| Q | 选项 | 决策 |
|---|---|---|
| Q1 一级 anchor row 默认状态 | 展开 / 折叠 | **折叠**（极简，按需展开）|
| Q2 嵌套 row title 显示 | "在第 X 条" / "└ preview only" / "嵌套在 父 里" | **preview only**（位置由父 anchor 表达）|
| Q3 chevron 单独 hit area 还是整行点了既切又展开 | 单独 hit / 一锅炖 | **单独 hit**（chevron 展开，row 主体切分支）|
| Q4 删 git graph 模式吗 | 删 / 留 | **删**（保持简洁）|
| Q5 collectAllBranches 数据结构改吗 | 改成树结构 / 保留扁平 + UI 层 group | **保留扁平 + UI 层 group**（少改 ViewModel）|

---

## 五、Task checklist

### [ ] T31. 撤销 git graph + mode toggle

`BranchMapSheet.swift`：
- 删 `@State showGitGraph`
- 删模式切换按钮 + capsule
- 删 `rowViewGit` + 横向 ScrollView
- 删 `BranchMapRailRow` 调用（保留文件本身先不删，可能复用）

可考虑直接 `git rm BranchMapRail.swift`——不再用，但暂留作为参考。

### [ ] T32. UI 层 group 数据结构

`BranchMapSheet` 内：

```swift
private struct AnchorGroup: Identifiable {
    let id: String              // = anchor row 的 id
    let anchorRow: MapRow       // anchor 自己（点了切到主线对应位置）
    let children: [BranchChildRow]  // 直接 children（可能是 leaf 也可能是 anchor）
}

private struct BranchChildRow: Identifiable {
    let id: String
    let entry: ConversationViewModel.AllBranchEntry
    let preview: String
    let length: Int
    let depth: Int
    let nestedChildren: [BranchChildRow]   // 该 child 下的嵌套（递归）
}
```

从 `viewModel.collectAllBranches()` 的扁平数组，根据 `parentAnchorOnMain + parentLane` 组装树。

### [ ] T33. 折叠展开 state

```swift
@State private var expandedAnchors: Set<String> = []
```

每个 anchor row 的 chevron 点击 toggle 该 anchor id 在 set 中。

### [ ] T34. file tree row 渲染

每个 row 类型：
- **主线 row**：dot + "主线 (N 条) ✓"，整行点 = 切回主线
- **一级 anchor row**：dot + 位置 + "N 条 ▶/▼"（chevron），点 ▶/▼ toggle 展开，点其他切到该 anchor 处的"主选 path 末尾"（or 不切？）
- **child row**（展开后显示）：缩进 14pt × depth + dot + preview + "X 条"，点切到该分支
- **嵌套 anchor row**（child 自己又是 anchor）：同 child row 但加 chevron，可以再展开

注意：**anchor row 的"切"行为有歧义** — 切到 anchor 自己吗？anchor 在主线上，切了等于回主线。所以 anchor row 主体应该不响应切，只响应 chevron。Chevron 占大 hit area。

### [ ] T35. 嵌套 location 文字优化

嵌套 row title = preview 截断（不再显示"在第 X 条"，因为位置已经被父 anchor 表达）。preview 长度可以加宽到 100 字（取代 title）。

### [ ] T36. 双端 build + 真机验证

- [ ] sheet 默认显示主线 + N 条一级 anchor row（金瓶梅约 7 行）
- [ ] anchor row 右侧 chevron `▶`
- [ ] 点 chevron → in-place 展开 children + chevron 变 `▼`
- [ ] 嵌套 row 缩进 14pt × depth
- [ ] 嵌套 child 自己是 anchor 时也有 chevron 可展开
- [ ] 整行（除 chevron）点 = 切分支（leaf row）/ 不响应（anchor row）
- [ ] 切回主线照常工作
- [ ] toast 切换提示照常

---

## 六、实施顺序

```
T31 (撤 git graph) → T32 (group 数据) → T33+T34 (UI + state) → T35 (文字) → T36 (验证)
```

---

## 七、不做

- ❌ git graph 视图（彻底放弃）
- ❌ 横向 scroll
- ❌ lane / swimlane 概念
- ❌ "在第 X 条" 出现在嵌套 row（只在一级 anchor row 上显示）
- ❌ 一级 anchor row 默认展开（要点 chevron）
- ❌ macOS 同步（先 iOS 验证）

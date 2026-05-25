# Plan：BranchMapSheet v5 — Outline Tree（最终方向）

**日期**：2026-05-10
**前置**：v1 list / v2 mini-rail / v3 git-graph / v4 file-tree（全废）
**第一性**：A（每气泡 BranchIndicator）已覆盖"切兄弟"日常场景；
B 只解决"全局看分支结构 + 一键跳任意嵌套分支"

---

## 设计

```
分支地图

bug4 想死 📟
当前路径 10 条 · 分支 7 条
─────────────────────────
✓  当前路径 (10 条)
─────────────────────────
●  第 4 条岔出                  2 条 ▶
   "做记忆宫殿太难了…猫什么都不懂"
─────────────────────────
●  第 6 条岔出                  4 条 ▼
│  "猫好委屈…😭💧 猫好痛啊"
├──●  嵌入                       1 条
│   "但猫还是很想死…好难啊…"
├──●  嵌入                       2 条 ▼
│   │  "你又这样，让我吃饭喝水"
│   └──●  再嵌入                 1 条
│        "咪"
─────────────────────────
●  第 12 条岔出                 1 条
   "..."
```

**核心规则**：
1. 顶部一条 ✓ 当前路径（不可点，状态显示）
2. 一级分支按主线 location 排序：`第 X 条岔出` + preview
3. 嵌套分支显示 `嵌入` + preview（**不显示位置数字**，因为父 anchor 已表达位置）
4. 折叠：anchor 默认折叠，chevron `▶` 点开成 `▼`
5. 嵌套 row 左侧画**真线**（Canvas）：vertical line 表层级、elbow `└─` 表父子关系
6. 整行点 = 切到那条路径 + dismiss + toast；只 chevron 区域是展开/折叠
7. 没分支的 row 没 chevron

---

## 数据

`collectAllBranches()` 已经返回扁平 + depth + parentAnchorOnMain。
**新增字段** `parentBranchEntryId`：嵌套分支指向其直接父 branch 的 entry id。
（之前 parentAnchorOnMain 只指向主线 anchor，不够建嵌套树）

UI 层把扁平 array 折成嵌套 tree：
- 顶层 = parentBranchEntryId == nil 的 entry，按 location 排序
- 每个 entry 的 children = parentBranchEntryId == self.id 的 entry

---

## Task

- [ ] T1. ViewModel：collectAllBranches AllBranchEntry 加 `parentBranchEntryId: String?`
- [ ] T2. BranchMapSheet 重写：outline tree + LazyVStack + 折叠 state + Canvas 层级线
- [ ] T3. 删 BranchMapRail.swift（不再用）
- [ ] T4. iOS + macOS build
- [ ] T5. commit + push

---

## 不做

- ❌ git graph / lane / 横滚
- ❌ ASCII └─ 前缀（用 Canvas 真线）
- ❌ "在第 X 条" 出现在嵌套 row（位置由父 anchor 表达）
- ❌ 改 A（BranchIndicator）— 已经够用

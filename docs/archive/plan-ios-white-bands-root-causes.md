# Plan: iOS 白边根因修复

基于 `docs/research-ios-white-bands-root-causes.md`，Susu 已明确要求直接解决，不再停留在试探式微调。

---

## 1. 目标

这轮要一次打中 iOS 上下白边的三个主要来源：

1. 第 2 页顶部 safe area 没被页面 chrome 接住
2. 右页当天无对话时，空状态卡被拉成超高白块
3. 左页空列表时，主卡被拉成整张空白卡

不做：

- 不改聊天页主结构
- 不重做主题配色
- 不扩大到 macOS 白条问题

---

## 2. 实施步骤

### Step 1: 把第 2 页顶部改成真正的 top inset chrome

文件：

- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/MemoryPanelView.swift`

动作：

- 从 `RightPanelView` 中拆出 iOS 顶部 tab/action 行
- 用 `safeAreaInset(edge: .top)` 承接第 2 页顶部安全区

预期结果：

- 状态栏下方不再只剩一块纯底色
- 顶部 tab/action 成为真正的页头

### Step 2: 修右页空状态卡高度策略

文件：

- `MemoryPalace/Views/CalendarPanelView.swift`

动作：

- 有对话时保留可滚动、可扩展列表卡
- 无对话时改为较矮的空状态卡，不再无限拉伸

预期结果：

- 底部不再出现巨型空白卡片

### Step 3: 修左页空列表高度策略

文件：

- `MemoryPalace/Views/SidebarView.swift`

动作：

- 搜索无结果、普通空列表、空回收站分别用 compact empty card
- 只在有内容时才使用整张可滚动主卡

预期结果：

- 左页不再出现“整页白卡”假象

### Step 4: 编译验证

动作：

- iOS build
- macOS build

---

## 3. 执行 Todo

- [x] Step 1: 第 2 页顶部改成真正的 top inset chrome
- [x] Step 2: 修右页空状态卡高度策略
- [x] Step 3: 修左页空列表高度策略
- [x] Step 4: 编译验证

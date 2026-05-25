# Plan: iOS 白边收口 + Kelivo 化轻导航

基于 `docs/research-ios-white-bands-kelivo.md`，Susu 已明确要求：`plan+开始`。

这轮只收 iOS 左页 / 右页的页面骨架，不扩到聊天页，不重做整套设计系统。

---

## 1. 目标

把 iOS 当前最突兀的两类问题一次收掉：

1. 左页和右页顶部 / 底部那种“内容没铺满”的白边感
2. 右页顶部那块说明书式黑字

同时把第 0 页和第 2 页往 `Kelivo` 的这两个特征上靠：

- 轻顶部 chrome
- 整页连续画布

不做的事：

- 不改聊天页主结构
- 不换整套配色
- 不新增复杂导航层
- 不把右页重做成另一套功能

---

## 2. 产品判断

### 2.1 右页不再用“大标题 + 大外壳卡”

当前最丑、也最像桌面 side panel 的部分，就是：

- `宫殿面板`
- `按时间翻看对话`
- 外层整页大圆角卡

这三者会一起拆掉或显著弱化。

### 2.2 右页保留原有能力，只重组顶部与容器

保留：

- 日历
- 记忆
- 导入
- 设置

变化：

- 导入 / 设置改成轻量顶部动作
- tab 切换更像手机页头
- 面板本体不再被一层“大卡片外壳”包住

### 2.3 左页不做重设计，只把页面骨架收干净

左页保留现有搜索、过滤、列表、底部统计结构。

这轮只做：

- iOS 页背景铺满
- 顶部 / 底部间距收紧
- 主体卡片和页面边界关系更顺

---

## 3. 具体实施步骤

### Step 1: 重构 iOS 第 3 屏容器

文件：

- `MemoryPalace/Views/ContentView.swift`

动作：

- 删除 `iOSDashboardHeader`
- 删除说明文案式 quick buttons 区
- 让 Page 2 直接成为完整 dashboard 页面
- 把导入 / 设置入口交给 `RightPanelView` 的轻顶栏

预期结果：

- 顶部黑字消失
- 右页从“模块介绍页”变成真正的功能页

### Step 2: 让 `RightPanelView` 变成 iOS 轻导航容器

文件：

- `MemoryPalace/Views/MemoryPanelView.swift`

动作：

- 给 `RightPanelView` 增加 iOS 顶部 action 区（导入 / 设置）
- 保留 `日历 / 记忆` 切换，但改成更轻的顶部 segment
- 去掉 iOS 下整页大圆角背景、描边、阴影

预期结果：

- 更像 Kelivo 的“轻顶部 + 内容主体”
- 减掉最明显的一层“卡套卡”

### Step 3: 收右页内部白边

文件：

- `MemoryPalace/Views/CalendarPanelView.swift`
- `MemoryPalace/Views/MemoryPanelView.swift`

动作：

- 调小 iOS 下多余外边距
- 让日历和记忆内容更贴近页面骨架
- 避免底部再出现横向整条底色带

预期结果：

- 右页上下边界更像完整手机页面

### Step 4: 收左页页面骨架

文件：

- `MemoryPalace/Views/SidebarView.swift`

动作：

- iOS 下背景改为整页铺满
- 顶部搜索区和底部统计区的留白收紧
- 主体列表区的卡片外边距略缩，减少“悬空抽屉”感

预期结果：

- 左页在空列表和正常列表时都不再像“中间一块、上下两条”

### Step 5: 编译验证并回填计划

动作：

- 运行 iOS build
- 运行 macOS build
- 把完成项标成 ✅

---

## 4. 影响范围

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift)
- [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SidebarView.swift)
- [MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift)
- [CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift)

---

## 5. 执行 Todo

- [x] Step 1: 重构 iOS 第 3 屏容器
- [x] Step 2: 让 `RightPanelView` 变成 iOS 轻导航容器
- [x] Step 3: 收右页内部白边
- [x] Step 4: 收左页页面骨架
- [x] Step 5: 编译验证并回填计划

---

## 6. 实际完成情况

### ✅ Step 1: 重构 iOS 第 3 屏容器

- 删除了 `iOSDashboardHeader`
- Page 2 改成直接承接 `RightPanelView`
- 导入 / 设置不再占一整块 hero header

### ✅ Step 2: 让 `RightPanelView` 变成 iOS 轻导航容器

- `RightPanelView` 新增 iOS 顶部轻动作区
- 导入 / 设置变成轻量图标按钮
- iOS 下移除了原来的整页大圆角外壳

### ✅ Step 3: 收右页内部白边

- `CalendarPanelView` 的 iOS 外边距收紧
- iOS 下卡片描边和圆角统一
- `MemoryPanelView` 的添加记忆区不再是一整条横带

### ✅ Step 4: 收左页页面骨架

- `SidebarView` iOS 顶部 / 底部 padding 收紧
- 主体卡片外边距缩小
- 背景改为整页铺满

### ✅ Step 5: 编译验证并回填计划

- `xcodegen generate`
- `xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- `xcodebuild -scheme MemoryPalace build`

结果：两端均 `BUILD SUCCEEDED`

# Research: iOS 白边与 Kelivo 化收敛

日期：2026-04-09

## 任务理解

Susu 这轮反馈的不是功能缺失，而是 iOS 外观还没有收干净，主要有三件事：

1. 左页和右页都还有明显的上下白边，画面像没有铺满。
2. 我前一轮加上的右页顶部黑字（`宫殿面板 / 按时间翻看对话`）很丑，要拿掉。
3. 视觉方向先不要自己发挥，先往 `Kelivo` 那种更干净、更像成熟手机产品的气质上靠。

这不是单点 bug。它涉及 iOS 三页容器、右页 dashboard 外壳、左页列表页的页面 chrome，所以按项目约定走一轮新的 research。

## 用户截图里已经暴露出来的问题

### 1. 右页（dashboard）的问题

从截图看，当前右页有三层不协调的结构同时存在：

- 页面底色是一整层米色。
- 中间又套了一张大圆角卡片。
- 卡片里面的日历和列表自己又是两张卡。

结果就是：

- 顶部 header 占了一段高度，下面大卡再开始，视觉重心被顶上那块黑字拖住。
- 底部还有一圈空出来的米色呼吸区，像“内容没长到边上”。
- 整页是“卡套卡”，不像手机主界面，更像桌面侧栏被硬搬上来。

### 2. 左页（列表）的问题

左页截图也能看到同类问题：

- 顶部搜索区下面就开始一大片空白，但整页上下边界没有被组织成完整的手机页面。
- 底部统计栏单独悬着，和中间内容区不是一个整体。
- 视觉上像“一个 sidebar 被放进手机壳里”，而不是原生 iOS 列表页。

这说明问题不只在右页，而是 iOS 页面容器本身还保留着桌面版 sidebar / inspector 的布局习惯。

## 当前实现里，问题具体是怎么来的

### 1. 顶部黑字是我前一轮主动加出来的

文件：[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L223)

这一段就是截图里那块丑的来源：

- `Text("宫殿面板")`
- `Text(rightPanelTab == .calendar ? "按时间翻看对话" : "看看小雾记住了什么")`

这块 header 不属于原有产品结构，是为了把第 3 屏从“更多页”临时抬成一个 dashboard 时加上的。现在看，方向是对的，但呈现方式太“说明书”了，不像 app。

### 2. 右页白边来自“页面 header + 外层大卡 + 内层双卡”三层叠加

文件：[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L149)

第 3 屏当前结构是：

- 外层 `VStack`
- 顶部 `iOSDashboardHeader`
- 下面整个 `RightPanelView`
- `RightPanelView` 额外有左右上下 padding

文件：[MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift#L16)

`RightPanelView` 本身又包了一层：

- 大圆角背景
- 描边
- 阴影

文件：[CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift#L20)

而 `CalendarPanelView` 内部继续是：

- 日历卡一张
- 当日列表卡一张
- 外层再有横向和纵向 padding

所以右页现在不是“一个完整页面”，而是“页面里放了一个悬浮组件”，这正好解释了截图里的上下边带。

### 3. 左页白边来自桌面 sidebar 结构直接搬到 iOS

文件：[SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SidebarView.swift#L38)

`SidebarView` 现在整体还是桌面侧栏思路：

- 顶部搜索和筛选是独立头部区。
- 中间列表区是一张圆角浮卡。
- 底部统计栏又是独立 footer。
- 整页只在最外层 `.background(Theme.sidebarBg)`。

文件：[SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SidebarView.swift#L568)

这在 macOS sidebar 里成立，但在 iPhone 全屏页里，视觉上就会出现：

- 顶部和底部像“留白带”
- 中间内容像一张没铺满的抽屉
- 页面骨架不够像移动端产品

## Kelivo 参考里，真正值得抄的是什么

我这轮找到了 `Kelivo` 公开仓库里的手机截图，而不是只凭印象猜。

来源：

- 仓库 README 截图入口：[Chevey339/kelivo README](https://github.com/Chevey339/kelivo)
- 截图区在 README 中可见，GitHub 抓取行号见 `Image: Chat Screen / Model Selection / Tool Calling / Web Search`
- README 还明确写了其界面设计 heavily inspired by `RikkaHub`

直接截图链接：

- [Kelivo Chat Screen](https://github.com/Chevey339/kelivo/raw/master/docx/screenshot_1.png)
- [Kelivo Model Selection](https://github.com/Chevey339/kelivo/raw/master/docx/screenshot_2.png)
- [Kelivo Tool Calling](https://github.com/Chevey339/kelivo/raw/master/docx/screenshot_3.png)
- [Kelivo Web Search](https://github.com/Chevey339/kelivo/raw/master/docx/screenshot_4.png)

### 从这些截图里能稳定提取出的设计特征

#### 1. 顶部是轻导航，不是大标题说明区

Kelivo 顶部一般只有：

- 左侧轻量按钮
- 中间当前上下文标题
- 下方一行更浅的次级信息
- 右侧 1-2 个动作按钮

它不会再在页面内部额外塞一块“模块说明文案”。

#### 2. 页面是整面连续画布，不是卡套卡

Kelivo 的主页面虽然内部有气泡、输入框、sheet、弹层，但“页面本身”是连续的。

也就是说：

- 内容不是被一张大卡再包住
- 页面顶部和底部不会露出多余背景边带
- 结构更像“全屏容器 + 必要局部卡片”，而不是“全屏底色 + 中间大圆角组件”

#### 3. 分组是轻的，外壳是弱的

Kelivo 会把强层级留给真正重要的东西：

- 输入框
- sheet
- tool block
- model picker

而不是先给整页做一个非常强的大轮廓框。

### 对记忆宫殿 iOS 的可迁移结论

能抄的是“页面组织方式”，不是把配色或 Flutter 细节原样照搬。

具体来说，应该抄：

1. 轻顶部 chrome
2. 整页连续背景
3. 减少一层外壳卡片
4. 让局部模块自己承担分组，而不是整页再套一个容器

不该抄的是：

1. 直接改成 Kelivo 的纯白冷色体系
2. 把 Memory Palace 现有暖奶白 + 浅灰薄荷主题推翻
3. 把聊天页、列表页、右页全部重做成另一套产品

## 这轮改动如果继续往前走，最小正确方向是什么

基于当前代码和用户截图，我认为最小正确方向是下面这条，而不是“大改版”：

### A. 右页去掉大黑字说明头

也就是删掉或重构 `iOSDashboardHeader`，不要再保留：

- `宫殿面板`
- `按时间翻看对话`

如果右页还需要动作入口，应该收成更轻的顶栏，而不是独立 hero header。

### B. 右页去掉最外层那张“整页大卡”

当前 `RightPanelView` 的大圆角背景是白边感的主要来源之一。

更接近 Kelivo 的方式应是：

- 页面本身直接作为画布
- 日历 / 记忆切换条保留
- 真正需要分组的内容再用局部卡片

也就是说，把“整页包装卡”弱化甚至取消。

### C. 左页从“桌面 sidebar”收成“手机列表页”

重点不是加更多装饰，而是把骨架整理顺：

- 顶部搜索区更像页头
- 中间列表区承担主体
- 底部统计栏更轻，或者并入同一连续面

目标是避免顶部一段、底部一段、中间一张卡彼此脱节。

### D. 白边优先从页面骨架解决，不先怪 safe area

这轮最值得警惕的一点是：问题看起来像 safe area，但根因更像布局层级。

如果一上来就粗暴地到处加 `ignoresSafeArea()`，很容易造成：

- 内容顶进 Dynamic Island 下方
- 底部贴到 Home Indicator
- 页面切换时出现新的遮挡问题

所以顺序应该是：

1. 先删掉多余 header 和外层包装卡
2. 再收紧页面内 padding
3. 最后只在必要位置处理 iOS safe area

## 影响范围

如果按上面的方向做，核心影响文件会是：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift)
- [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SidebarView.swift)
- [MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift)
- [CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift)

潜在次级影响：

- iOS 第 0 页和第 2 页的上下留白、导航感会一起变化
- 右页 tab 条和日历卡层级会重排
- 需要重新编译检查 iPhone 模拟器实际效果

## 当前判断

当前最像正确答案的，不是“修一个白边 bug”，而是把我前一轮给 iOS 第 3 屏加出来的桌面式包装壳拆掉一层，让第 0 页和第 2 页都更像真正的手机页面。

如果 Susu 认可这份 research，下一步 plan 我会按这个范围收得很窄：

1. 去掉右页大黑字说明头
2. 去掉或显著弱化右页整页大卡
3. 重组左页与右页的 iOS 页面骨架，优先消灭截图里的上下白边
4. 只借 Kelivo 的“轻导航 + 整页连续画布”，不照搬它的冷白视觉

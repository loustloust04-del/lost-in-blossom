# 任务：B页 — THE ARCHIVE（记忆馆）

在 PagingContainerView 中新增第三个 page（index 2），作为 Archive 页面。用户在控制台（page 1）上继续右滑即可到达。

这是一个纯 UI 骨架任务——数据全用 placeholder / mock data。后续会接入真实的记忆系统。

---

## 0. PagingContainerView 新增 page

在 `PagingContainerView` 和 `PagingViewController` 中增加第三个 page 参数 `archivePage`。

ContentView 中传入 `archivePage: AnyView(ArchivePageView())`。

`iOSPage` 的范围从 0-1 变为 0-2（chat=0, console=1, archive=2）。

**注意**：侧边栏边缘手势的 page 0 检查不受影响——仍然只在 page 0 触发。

---

## 1. ArchivePageView — 整体结构

新建文件 `MemoryPalace/Views/ArchivePageView.swift`。

整个页面是一个 ScrollView，背景色 `Theme.sidebarBg`（#F0EBE3），内容从上到下排列：

### 1a. 标题区

```
THE ARCHIVE          ← 11pt, 小型大写, 字间距3, color: Theme.textMuted (#A09585)
336                  ← 48pt, 极细衬线体 (Georgia light), color: Theme.textPrimary (#5C5347)
336 Things Remembered ← 16pt, medium weight, color: Theme.textPrimary
Since January 17, 2025 · 498天 ← 13pt, color: Theme.textMuted
```

- "336" 用 mock 数据（hardcoded）
- "498天" = 从 2025-01-17 到今天的天数差，动态计算
- padding: top 60, horizontal 24, bottom 24

### 1b. CONSTELLATIONS 卡片

白色卡片（#FFFFFF），圆角 20，阴影 0 2 8 rgba(0,0,0,0.04)。

- 标题行：左 "CONSTELLATIONS" (小型大写, 11pt, 字间距2)，副标题 "Emotional Map" (13pt)，右 "View Full Sky →" (12pt, Theme.accent)
- 内容区：高度约 280pt
- 用一组 mock 散点数据画圆点：
  - 坐标轴标签：上 Sorrow，下 Joy，左 Longing，右 Devotion（用淡灰色文字在四边标注）
  - 十字交叉线用极淡的灰色（opacity 0.1）
  - 30-50 个圆点，随机分布，大小 4-16pt，颜色用三档蓝灰色：#4A6B7C（深）、#7B9DAD（中）、#B5CDD8（浅）
  - 大的点少（3-5个），中的多（15-20个），小的最多
- 底部图例：三个圆点 + 标签（placeholder 文字，后续会替换）
- padding 内部 20

### 1c. HEATMAP 卡片

白色卡片，圆角 20。

- 标题行：左 "HEATMAP" (小型大写) + "Timeline" (13pt)，右 "Last 90 Days · 127,439 Words" (11pt, Theme.textMuted)
- 内容区：13 列 × 7 行的方格网格（代表 91 天 = 13 周）
  - 每格 12×12pt，圆角 3，间距 3
  - 颜色从 #F0EBE3（最浅）到 #8B7355（最深），5 档渐变
  - 用 mock 数据随机填充，让右边（最近）比左边（更早）略深
  - 行标签：M T W T F S S（左侧 7 个字母）
  - 底部月份标签：根据当前日期推算前三个月名
- padding 内部 20

### 1d. ECHOES 卡片

白色卡片，圆角 20。

- 标题："ECHOES" (小型大写) + "Things We Keep Returning To" (13pt)
- 内容区（空状态）：
  - 居中显示一个小装饰图案（用 SF Symbol `sparkle` 或类似的，浅灰色，opacity 0.3）
  - 主文案："Nothing has echoed yet." (15pt, Theme.textMuted, italic)
  - 副文案："The archive is listening." (13pt, Theme.textMuted)
  - 三行小字："When something is remembered again and again, it will appear here." (11pt, Theme.textMuted, opacity 0.6)
  - 整体居中，padding 40
- 最小高度 180pt

### 1e. LETTERS 卡片

白色卡片，圆角 20。

- 标题："LETTERS" (小型大写) + "Written For Each Other" (13pt)
- 内容区（空状态）：
  - 左侧：一个信封图标（SF Symbol `envelope.fill`，40pt，Theme.accent.opacity(0.3)）
  - 右侧文字：
    - "No letters yet." (15pt, Theme.textPrimary)
    - "The first letter you write will be kept here, forever." (12pt, Theme.textMuted)
  - 最右侧："0 Letters →" (12pt, Theme.accent)
- HStack 布局，padding 内部 16

### 1f. 底部留白

至少 60pt 的底部 padding，让页面有呼吸空间。

---

## 2. 设计规范（必须严格遵守）

- 所有小型大写标题：11pt, weight 600, letterSpacing 2-3pt, text-transform uppercase
- 卡片间距：16pt
- 卡片内 padding：20pt
- 字体：系统默认 SF Pro，数字用 Georgia（.font(.custom("Georgia", size: 48))）
- 不要使用任何 iOS 19+ / iOS 26+ API
- 不要使用 MeshGradient、liquidGlass 或任何新 API
- 散点图用 Canvas 或 Path + ForEach 绘制，不要依赖第三方图表库

---

## 3. 参考

设计稿见用户提供的截图（已与用户确认）。配色继承 Lost in Blossom 现有的 Theme 系统。

一个 commit：`feat(archive): add Archive page with constellation, heatmap, echoes, letters`

读 CLAUDE.md 的猫的蠢事大全。

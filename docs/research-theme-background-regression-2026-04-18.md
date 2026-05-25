# Research: 主题背景图导致的 iOS 布局回归

> 时间：2026-04-18  
> 工作树：`/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings`  
> 关联 commit：`e351250 Add theme library and adjustable backgrounds`

---

## 0. 这轮任务的理解

这轮要研究的不是“主题还能怎么升级”，而是一个已经影响可用性的 **P0 回归 bug**：

1. iOS 左页 / 中页现在会变得 **比屏幕还宽**。
2. 很多控件被裁到屏幕外，已经 **无法正常操作**。
3. 背景图相关改动是回归起点，但当前最严重的问题不是配色是否好看，而是 **布局本身坏了**。

所以这份 research 的目标是：

- 深查“为什么页面宽度会被撑爆”
- 深查“为什么中页也跟着一起坏”
- 再把背景图层和表面层问题当成 **第二层问题** 去分析

这轮 **不进入实现**，只写事实、根因判断、影响范围和后续 plan 约束。

---

## 1. 最新症状复盘

### 1.1 用户反馈的严重症状

Susu 最新补充的信息非常关键：

- 左页 / 中页都变得很宽
- 宽到超过屏幕
- 很多控件看不见
- 已经无法使用

这意味着当前问题优先级应该被定性为：

- **P0 可用性 bug**
- 不是视觉 polish
- 不是背景图参数调得不够好

### 1.2 截图里能直接看到的现象

从 `/var/folders/.../Screenshot 2026-04-18 at 12.49.49 AM.png` 可以直接看出：

- 顶部的搜索 / 新建对话区域并没有完整出现在可视区域内
- tab 区只剩一部分内容，`+` 在奇怪的位置
- 对话列表/内容板左边被裁掉，文字从中间开始显示

这不是简单的“背景图不协调”，而是典型的：

- **整页内容横向偏移**
- 或 **整页内容宽度大于屏幕并被居中裁切**

### 1.3 背景图确实存在，但这不是主症状

同一张图里也能看到：

- 顶部和底部有浅紫色背景图纹理

所以现在不是“背景图没接上”。  
真正 blocking 的主症状是：

- **页面尺寸/布局已经错了**

---

## 2. 已深读的相关代码

### 2.1 主题与背景相关

- `MemoryPalace/Models/AppTheme.swift`
- `MemoryPalace/Utils/Theme.swift`
- `MemoryPalace/Utils/ThemeManager.swift`
- `MemoryPalace/Views/ThemeBackgroundView.swift`
- `MemoryPalace/Views/ThemeEditorView.swift`
- `MemoryPalace/Views/ThemeSettingsTab.swift`

### 2.2 iOS 主界面骨架

- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/SidebarView.swift`
- `MemoryPalace/Views/CardFlowView.swift`
- `MemoryPalace/Views/MemoryPanelView.swift`
- `MemoryPalace/Views/WorldBookPanelView.swift`
- `MemoryPalace/Views/CardLibraryPanelView.swift`
- `MemoryPalace/Views/ToolBarView.swift`

### 2.3 之前文档

- `docs/research-theme-kelivo-settings-2026-04-17.md`
- `docs/plan-theme-kelivo-settings-2026-04-17.md`

---

## 3. 先纠正一个判断：要优先看这次 commit 真改了什么

在 Susu 提醒“这个 bug 是背景图功能之后才出现”之后，我重新做了 `HEAD^ -> HEAD` 对比。

### 3.1 这次主题 commit 真正改过的父层文件

本次主题功能 commit 里，和主界面骨架直接相关的改动主要是：

- `ContentView.swift`
- `SettingsView.swift`
- `Theme.swift`
- `ThemeBackgroundView.swift`
- `ThemeManager.swift`
- `AppTheme.swift`

### 3.2 `SidebarView.swift` 没在这次 commit 里改过

这点很关键。

`HEAD^ -> HEAD` 里：

- `SidebarView.swift` 没有 diff
- `CardFlowView.swift` 也没有 diff

所以：

- 我上一轮把第一嫌疑放在 `SidebarView` 顶部横向 tab 条本身，这个判断 **不够严谨**
- 因为它无法单独解释“为什么是背景图功能出来之后才出现”

### 3.3 新的研究原则

从现在开始，第一优先要怀疑的是：

- **这次 commit 新引入的 root/background/layout 变化**

而不是没有改过的旧页面代码本身。

---

## 4. 第一结论：当前最严重的问题是 iOS page width 被撑爆

这是这轮 research 最重要的结论。

不是先去谈 surface 语言，也不是先谈 wallpaper 风格，而是：

- **左页本身很可能把分页宽度撑到了大于屏幕**
- 然后 `TabView(.page)` 连中页一起被带坏

---

## 5. 新的第一嫌疑：`ContentView` 把纯色根背景换成了 `ThemeBackgroundView`

## 5.1 这次 commit 的关键 root 改动

`ContentView.swift` 在 `HEAD^ -> HEAD` 的 diff 里，最关键的一段是：

- 之前：`Theme.mainBg.ignoresSafeArea()`
- 现在：`ThemeBackgroundView(...).ignoresSafeArea()`

也就是主 app root 从一个纯色 `Color`，变成了一个带图片的背景 view。

### 代码位置

`ContentView.swift:60-72`

```swift
ZStack {
    ThemeBackgroundView(
        fill: Theme.mainBg,
        imageURL: manager.currentBackgroundImageURL,
        scheme: manager.activeScheme,
        backgroundStyle: manager.currentBackgroundStyle
    )
    .ignoresSafeArea()

    ...
}
```

## 5.2 `ThemeBackgroundView` 本身是本次 commit 新引入的

而且 `ThemeBackgroundView.swift` 里，背景图实现是：

`ThemeBackgroundView.swift:54-79`

```swift
Image(...)
    .resizable()
    .scaledToFill()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .offset(...)
    .clipped()
```

## 5.3 当前最可信的新判断

我现在更怀疑的是：

- `ThemeBackgroundView` 在 full-screen root 场景下，没有被一个明确的有限 frame 锁住
- 背景图片又是 `resizable + scaledToFill + maxWidth/maxHeight infinity`
- 于是它可能在 SwiftUI 布局里报告了异常大的理想尺寸
- 最外层 `ZStack` 被这个背景 child 撑大
- 整个 app 内容随之一起进入“宽于屏幕、被居中裁切”的状态

### 这是推断，但它比上一轮更符合“回归出现的时间点”

因为：

1. 这部分代码是 **这次 commit 新加的**
2. 问题是 **背景图功能出来之后才有**
3. 它天然会影响整个 `ContentView` root，而不只是某一个子页面

### 它还能解释“左页和中页一起坏”

如果最外层 root `ZStack` 已经被背景 view 撑大：

- 左页会坏
- 中页也会坏
- 看起来像整个分页系统都横向超宽

这比“某个旧子页面自己突然坏了”更符合现象。

---

## 6. 次级嫌疑：Sidebar 顶部横向 tab 条仍然可能是放大器，不一定是首发点

## 4.1 代码位置

`SidebarView.swift:808-830`

当前 sidebar tab 条是：

```swift
private var sidebarTabBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
            let tabs = allTabs
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                tabButton(tab, index: index, total: tabs.count)
            }
            Button { ... } label: { ... }
        }
        .padding(.horizontal, isIOSStyle ? 20 : 12)
    }
}
```

## 6.1 tab 本身被设计成“按内容宽度展开”

`SidebarView.swift:841-848`

每个 tab label 现在是：

- `Text(label)`
- `.lineLimit(1)`
- `.fixedSize()`

这意味着：

- tab 不会压缩
- 会按文字自然宽度展开
- 自定义标签一多，整条 HStack 的内容宽度会持续增长

## 6.2 当前 tab 条没有被约束到屏幕宽

我在这个节点上没有看到：

- `.frame(maxWidth: .infinity, alignment: .leading)`
- 或其他把它锁回父容器宽度的约束

所以这条 `ScrollView(.horizontal)` 的理想宽度，本来就很可能就是：

- 整个 tab 内容宽度
- 而不是屏幕宽度

### 但现在它更适合被定义成“放大器”

因为在 `HEAD^ -> HEAD` 对比下：

- 它不是新引入的代码
- 所以更像是一个本来就脆弱的宽度来源
- 当 root 背景布局也开始异常时，它会把“页面很宽”的问题放得更明显

---

## 7. 第三个放大器：Sidebar 根容器是 top 对齐，不是 topLeading

`SidebarView.swift:599-600`

```swift
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
```

这里的 `alignment: .top` 水平方向是 **居中**。

这点非常关键。

如果 `SidebarView` 内部某个 child 把理想宽度撑大了，那么当前行为更可能是：

1. 整个页面内容宽度大于屏幕
2. 内容按中心对齐
3. 左右两边一起被裁掉

这和截图现象完全一致：

- 左边搜索入口不见了
- tab 条只剩中间一段
- 内容列表从中间开始显示

换句话说：

- 宽度溢出本身是一个问题
- `alignment: .top` 让这个问题以“整页被居中裁切”的方式变得更糟

---

## 8. 为什么中页也跟着一起坏

## 6.1 代码位置

`ContentView.swift:148-157`

```swift
TabView(selection: $iOSPage) {
    iOSListPage.tag(0)
    iOSChatPage.tag(1)
    iOSDashboardPage.tag(2)
}
.tabViewStyle(.page(indexDisplayMode: .never))
```

## 6.2 当前判断

我现在根据 `HEAD^ -> HEAD` 和当前代码做出的判断是：

- **最外层 `ContentView` root** 很可能已经因为背景 view 报告了异常大的尺寸
- page 0 的 sidebar 结构又可能继续放大这个宽度
- `TabView(.page)` 内部分页容器很可能跟着采用了这个异常 page width
- 所以 **中页 page 1** 虽然自己不一定先坏，但会一起表现成“页面比屏幕宽”

### 这是推断，不是已经跑到 UIKit 层拿到精确 frame 的实测

但这条推断目前非常强，因为它能同时解释：

1. 为什么左页先明显出问题
2. 为什么中页也一起变宽
3. 为什么截图里看起来像整个 page 被横向裁切，而不是单个子控件错位

---

## 9. 为什么我现在认为“root 背景布局回归”比“surface 语言问题”更优先

## 9.1 它直接解释了“无法使用”

Susu 现在抱怨的核心不是：

- 背景图不够美
- 背景图太淡

而是：

- 控件不见了
- 页面宽过屏幕
- 没法点

这类症状和 `sidebarTabBar`/page width 异常比 wallpaper 更直接相关。

## 9.2 它直接解释了截图里的横向裁切

当前截图最突出的不是“通透感不对”，而是：

- 左边整个被削掉

这就是一个标准布局宽度/对齐问题。

## 9.3 它还能解释“左页和中页同时坏”

单纯的 wallpaper/surface 叠层，通常只会让页面显得厚、显得脏，不会天然让：

- 中页和左页同时横向超出屏幕

而：

- root 尺寸异常
- 再加上 `TabView(.page)` 共享 page width

刚好能解释这点。

---

## 10. 次一级问题：背景图虽然接上了，但页面表面系统仍然不兼容

这部分依然成立，但它是 **第二层问题**，不是当前最 blocking 的那个。

## 10.1 root wallpaper 已经存在

`ContentView.swift:66` 的最外层已经用了：

- `ThemeBackgroundView`
- `manager.currentBackgroundImageURL`
- `manager.currentBackgroundStyle`

所以背景图本身不是没接上。

## 10.2 主题 token 也在背景图模式下降了 alpha

`AppTheme.swift:274-295`

`applyingBackgroundImageSurfaceStyle(for:)` 已经把：

- `mainBg`
- `sidebarBg`
- `userBubble`
- `assistantBubble`
- `accent`

都做了透明度乘法。

## 10.3 但大量页面仍然在重复铺大块 surface

例如：

- `CardFlowView.swift:142` 直接 `.background(Theme.mainBg)`
- `CardFlowView.swift:226` 整个容器再次 `.background(Theme.mainBg)`
- `ContentView.swift:267` 的 `iOSDashboardPage` 直接 `Theme.sidebarBg.ignoresSafeArea()`
- `RightPanelView` 本体和它的子页继续 `.background(Theme.sidebarBg)`
- `SidebarView` 的大内容板仍然是 `Theme.mainBg`

所以 wallpaper 虽然存在，但它只活在最外层，内层还是老的“大面板骨架”。

### 这会造成什么

- 页面看起来很厚
- 背景图只在边缘漏出来
- “UI 很巨大”的主观感受被进一步放大

但这部分更像是：

- **在修完宽度回归之后** 还要继续处理的主题适配问题

---

## 11. 当前最可信的因果链

我目前认为最可信的因果链是：

1. 主题背景功能把 `ContentView` 根背景从纯色 `Color` 换成了 `ThemeBackgroundView`。
2. `ThemeBackgroundView` 在 full-screen root 场景里，可能因为 `resizable + scaledToFill + infinity frame` 报告了异常大的理想尺寸。
3. 最外层 root 尺寸先变得不稳定。
4. `SidebarView` 顶部横向 tab 条本来又是一个容易拉宽内容的旧结构：
   - `ScrollView(.horizontal)`
   - tab label `.fixedSize()`
   - 没显式收口到屏幕宽
5. `SidebarView` 根容器还是 center 水平对齐。
6. 所以左页最先呈现出“宽于屏幕、左右裁切”的状态。
7. `TabView(.page)` 很可能共享了这个异常 page width，中页也跟着一起坏。
8. wallpaper/surface 叠层问题再进一步放大了“整页巨大、很厚、很难用”的观感。

---

## 12. 之前那份 research 偏掉的地方

我上一版 research 的主要问题是：

- 过早把重点放在“背景图表面系统还没重构完”
- 没把“页面已经横向超宽、无法使用”提升为主问题
- 也没有先对照 `HEAD^ -> HEAD` 看这次 commit 到底改了哪些父层文件

这在当前阶段是偏题了。

真正应该优先写清楚的是：

- 这是个 **布局回归 bug**
- 而且已经是 **blocking**

---

## 13. 进入 plan 前必须先明确的点

如果下一轮进入 plan，我认为 plan 必须优先围绕 **P0 布局回归** 展开，而不是先围绕 wallpaper 风格展开。

至少要回答：

1. `ThemeBackgroundView` 在 root/full-screen 场景下，是否必须改成由外层 `GeometryReader` 或明确 frame 驱动，彻底切断图片理想尺寸对根布局的污染？
2. `SidebarView` 的 `sidebarTabBar` 是否必须显式限制到屏幕宽？
3. `SidebarView` 根容器是否必须改成 `.topLeading`，避免内容溢出时继续居中裁切？
4. `TabView(.page)` 的每个 page 是否都应该显式 `.frame(maxWidth: .infinity, maxHeight: .infinity)`，切断 page 之间的宽度污染？
5. 修完 page width 之后，再分别处理：
   - `SidebarView`
   - `CardFlowView`
   - `iOSDashboardPage`
   - `RightPanelView`
   的 wallpaper/surface 适配

---

## 14. 当前结论

### 结论 A

当前最严重的问题不是背景图参数，而是 **iOS page width 回归**。

### 结论 B

新的第一嫌疑是：

- `ContentView` 根背景从纯色换成 `ThemeBackgroundView` 后，背景 view 很可能污染了 root 尺寸

### 结论 C

`SidebarView` 的横向 tab 条 + center 对齐仍然是高风险放大器，但它更像：

- 旧的脆弱结构
- 在这次 root 背景布局回归后被同时放大

### 结论 D

中页一起变宽，我目前判断是 page 0 把 `TabView(.page)` 的分页宽度一起带坏了。

### 结论 E

背景图相关的 surface 冲突依然存在，但它是 **第二层问题**。  
当前应先修 blocking 布局 bug，再谈 wallpaper 质感。

---

## 15. 当前状态

这轮 research 到这里结束。

**DON'T IMPLEMENT YET**

下一步应该写一份新的 plan，先按 P0 布局回归来设计修复路径，再等 Susu 批。

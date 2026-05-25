# Research: iOS 上下白边根因总排查

日期：2026-04-09

基于：

- 新截图：`Screenshot 2026-04-09 at 3.44.24 AM.png`
- 当前 iOS 代码路径：
  - `MemoryPalace/Views/ContentView.swift`
  - `MemoryPalace/Views/MemoryPanelView.swift`
  - `MemoryPalace/Views/CalendarPanelView.swift`
  - `MemoryPalace/Views/SidebarView.swift`
- 历史文档：
  - `docs/白条排查记录.md`
  - `docs/右侧面板样式排查记录.md`

---

## 1. 先说结论

这次 iOS 的“上下白边”不是一个单点 padding 问题，而是 **3 类不同来源叠在一起**：

1. **页面顶部空带**：
   iOS 第 2 页没有把顶部区域当成真正的导航 chrome 来处理，而是把 tab/action 行放在普通内容流里，导致顶部 safe area 只剩一块纯底色。

2. **页面底部大空白**：
   `CalendarPanelView` 的当天列表卡被强行拉伸到整页剩余高度，空状态又填满这张卡，所以视觉上像“底部白边没收掉”，其实是一个被拉得过高的空白卡片。

3. **左页同类问题**：
   `SidebarView` 的主列表区在内容很少或为空时，也会撑成一整张大空卡，所以看上去像上下一圈白边，但根因是“空内容卡无限拉伸”，不是单纯背景没铺满。

所以我前两轮只砍 padding，命中了很小的一部分，但 **没有打到最大头的根因**。

---

## 2. 这次最重要的判断

### 2.1 右页现在最像“两个问题”

用户截图里，右页视觉上有两种“白”：

#### A. 顶部那一截浅色空带

位置：

- Dynamic Island / 状态栏下方
- tab 行上方

这段不是日历卡造成的，而是 **页面级 safe area 没有被顶部 chrome 吃掉**。

当前代码：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L149)
- [MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift#L18)

当前第 2 页结构是：

- `TabView(.page)`
- page 2 是普通 `ZStack`
- 里面直接摆 `RightPanelView`
- `RightPanelView` 顶部 tab/action 行也是普通 `VStack` 第一行

也就是说：

- 顶部安全区存在
- 但没有系统导航栏
- 也没有自定义 `safeAreaInset(edge: .top)` 去承接它

结果就是顶部会保留一块“只是底色”的空带。

#### B. 底部那一大块空白

位置：

- “4月9日 星期四”标题下面的大块空白卡片
- 空状态图标漂在很低的位置

这个不是 page 外边距，也不是 safe area。

根因在这里：

- [CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift#L41)
- [CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift#L171)

当前逻辑是：

1. `dayConversationList.frame(maxHeight: .infinity)`
2. 空状态 `VStack` 继续 `.frame(maxWidth: .infinity, maxHeight: .infinity)`

所以只要当天没有对话：

- 下面这张卡就会被拉满剩余空间
- 空状态会被放进这张超高卡里
- 用户看到的就是“下面还是一整片白”

这类问题，继续削外层 padding 基本不会根治。

---

## 3. 右页所有可能来源，按置信度排序

### P0. 顶部 safe area 没有被导航 chrome 接管

置信度：高

证据：

- page 2 不是 `NavigationStack`
- 没有 `.toolbar`
- 没有 `.safeAreaInset(edge: .top)`
- 顶部 action/tab 是普通内容流

影响：

- 顶部永远会留出一段纯底色区
- 即使内部 padding 改到 0，这块也不会自然消失

### P0. `dayConversationList` 空状态卡被无限拉高

置信度：高

证据：

- `dayConversationList.frame(maxHeight: .infinity)`
- 空状态继续 `maxHeight: .infinity`
- 截图里最大的“白边感”正是这张空卡

影响：

- 底部空白极显眼
- 页面会被误判成“底边还没修”

### P1. `RightPanelView` 顶部 tab 行和 `CalendarPanelView` 的 header 是双层顶栏

置信度：中高

证据：

- `RightPanelView` 先有一行 tab/action
- `CalendarPanelView` 自己又有月份 header

结果：

- 上半屏的结构重心过高
- 页面显得“顶部堆了一坨，下面空很大”

这不是白边本身，但会放大“上面有空带”的感知。

### P1. page 2 外层 `TabView(.page)` 容器本身可能增加了页面 safe-area 语义

置信度：中

`TabView` 的 `.page` 风格底层是分页控制器语义，子页面通常更像“普通内容页”，不会自动帮你把顶部安全区消费成导航栏。

它不一定是 bug 根源，但它决定了：

- 如果不用系统导航栏或自定义 top inset
- 顶部就只会是一块底色

### P2. 我前几轮改的 padding 只是次要变量

置信度：高

这次回头看，前几轮主要改的是：

- `RightPanelView` 顶部 padding
- `CalendarPanelView` 卡片外边距
- `ContentView` page 2 顶部 padding

这些会有一点帮助，但都绕开了：

- 顶部 safe area 归属
- 空状态卡高度策略

所以用户持续看到“还是有”是合理的。

---

## 4. 左页为什么也会有同类问题

当前左页：

- [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SidebarView.swift#L38)
- [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SidebarView.swift#L525)

结构是：

- 顶部搜索/筛选头
- 中间整个 `ScrollView` 主卡
- 底部统计栏

中间主卡在内容少或为空时，会自然占满剩余高度。

所以用户看到的不是：

- “有一条系统白边”

而更像：

- 顶部一截头部
- 中间一张巨大的空白卡
- 底部一截 footer

这和右页当天无对话时的巨大空卡，本质上是同一种问题：

**空内容容器被当成整页主卡无限拉伸。**

---

## 5. 哪些方向已经可以排除或降级

### 5.1 不是 `MemoryPalaceApp.swift` 外层 scene 的问题

文件：

- [MemoryPalaceApp.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/MemoryPalaceApp.swift#L384)

iOS 下这里只是 `ContentView()` + environment + modelContainer，没有额外包一层会制造白边的导航或宿主。

所以 scene 入口不是这次的主要矛盾。

### 5.2 不是 macOS 那个“白条排查记录”里的同一类问题

`docs/白条排查记录.md` 处理的是：

- macOS
- `NavigationSplitView`
- unified toolbar
- AppKit 容器白条

这次 iOS 的问题和它不是一类。

这很重要，因为继续按 macOS 那套“补背景色 / patch 宿主 view”思路走，会浪费时间。

### 5.3 不是单纯颜色不对

虽然 `Theme.mainBg` 和 `Theme.sidebarBg` 的对比，会让空带更显眼，但即使统一颜色：

- 顶部 safe area 空带仍然存在
- 巨型空状态卡仍然存在

所以颜色只能弱化，不是根治。

---

## 6. 这次如果要一次性修，应该怎么分层处理

### 层 1：页面顶部

要解决“上白边”，重点不是再砍 padding，而是决定：

- 顶部安全区到底归谁管

最合理的两条路线：

#### 路线 A：把 page 2 变成真正的导航页

做法：

- page 2 用 `NavigationStack`
- 顶部 action/tab 收进 toolbar / navigation chrome

优点：

- 顶部 safe area 会被页面 chrome 吸收
- 更像成熟 iOS app

风险：

- 需要重新设计 page 2 的顶部组织方式

#### 路线 B：保留普通页面，但用 `safeAreaInset(edge: .top)` 显式占住顶部

做法：

- 页面主体允许铺满
- 顶部 tab/action 用 `safeAreaInset(edge: .top)` 挂进去

优点：

- 控制力高
- 不必完全切到系统导航栏

风险：

- 要自己处理顶栏背景、层级和滚动关系

### 层 2：右页空状态卡高度

要解决“下白边”，重点是改空状态策略：

- **不要让空状态卡无限撑高**

具体策略：

1. 有对话时：
   底部列表卡继续吃掉剩余高度
2. 没有对话时：
   改成一个较矮的空状态卡，或者让卡片只占内容高度

这是目前命中率最高的修法。

### 层 3：左页空列表页

左页应同步采用同一原则：

- 内容多时，主卡吃剩余空间
- 内容少/为空时，主卡不要无限装满整页

否则右页修完，左页还会继续像“中间一大片空白卡”。

---

## 7. 我现在对“最小正确方案”的判断

如果要真正一次打中，而不是继续小修小补，最小正确方案应该是：

1. page 2 顶部改成真正的 top inset / navigation chrome
2. `CalendarPanelView` 的空状态卡不再 `maxHeight: .infinity`
3. `SidebarView` 在空内容时也改成 compact empty state card

这三步一起做，才算“系统性解决上下白边”。

如果只做其中一步：

- 只修顶部：下面还会像一大块白
- 只修底部：上面 still 像没贴边
- 只修右页：左页还会继续一样

---

## 8. 当前判断

用户这次催的方向是对的：不该再继续凭感觉一刀一刀砍 padding。

从当前代码和截图看，真正该排在前面的，不是“还有哪个 `.padding(.top)` 没删”，而是：

1. 顶部 safe area 的归属策略
2. 空状态卡是否应该无限拉伸
3. 左右两页是否统一采用“空内容不充满整页”的规则

如果 Susu 认可这份 research，下一步 plan 应该按这个结构来，不再做盲改：

- Step 1：重构 page 2 顶部承接方式
- Step 2：重构 `CalendarPanelView` 空状态高度策略
- Step 3：重构 `SidebarView` 空状态高度策略
- Step 4：统一验证左右页截图效果

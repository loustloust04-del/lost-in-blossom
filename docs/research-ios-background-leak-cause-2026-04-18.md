# Research: iOS 背景图为什么还在漏

日期：2026-04-18  
分支：`codex/theme-kelivo-settings`  
范围：只找原因，不提修法

---

## 1. 这次要回答的不是“怎么改”，而是“到底坏在哪一层”

当前现象已经不是最早那种“整页被撑得超宽”的回归了。  
那部分布局问题基本已经被收住。

现在剩下的核心现象是：

1. iOS 主界面顶部还能看到一整条明显的背景图。
2. 底部页码附近、列表页底部留白区、聊天页顶部工具条下方，背景图都会漏出来。
3. 这不是单点漏色，而是**整套页面表面层和 root wallpaper 的挂法不一致**。

结论先说：

> 当前“背景图还在漏”的原因，不是单一的一行代码，而是三层问题叠在一起：
> 1. 背景图模式把全局 page surface 统一降成了半透明；
> 2. root wallpaper 被挂在了一个对 safe area 判断不可靠的层级；
> 3. iOS 页面本身又保留了大量故意留白 / 渐变到透明 / home-indicator 区域内容。

所以只要这三层里有两层同时存在，背景图就一定会继续从顶部、底部和大块留白区漏出来。

---

## 2. 第一层原因：背景图模式把 page surface 直接变成了半透明

最关键的因果链在这里：

- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:274)
- [ThemeManager.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Utils/ThemeManager.swift:317)

`ThemeManager` 只要发现主题带背景图：

```swift
if theme.hasBackgroundImage {
    base = base.applyingBackgroundImageSurfaceStyle(for: scheme)
}
```

而 `applyingBackgroundImageSurfaceStyle(for:)` 做的事情是：

- `mainBg *= 0.88`
- `sidebarBg *= 0.82`
- `userBubble *= 0.90`
- `assistantBubble *= 0.90`
- `accent *= 0.76`

对应代码在：

- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:279)
- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:280)
- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:281)
- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:282)
- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:283)

这意味着什么？

这意味着：

- 不是某个具体页面偶尔透明了；
- 而是**整个 app 的基础底色 token**，只要开背景图就统一半透明。

于是所有本来靠 `Theme.mainBg` / `Theme.sidebarBg` 撑住的区域，都会天然透出 wallpaper。

所以现在看到的“顶部一整坨、底部一整坨”不是偶然渲染异常，而是：

> 只要页面上存在大块 `mainBg` / `sidebarBg` 留白，这些区域就会被设计成允许 wallpaper 穿透。

这就是第一层根因。

---

## 3. 第二层原因：root wallpaper 挂在了一个不适合做 safe area 裁切的位置

当前 root wallpaper 在：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:95)

它不是直接挂在一个明确的全屏容器上，而是挂在：

```swift
.background {
    GeometryReader { proxy in
        ...
        proxy.safeAreaInsets
        ...
    }
}
```

这里的问题不是“数学算错一点点”，而是**层级就不对**。

我查了 xcdocs：

- `GeometryProxy.safeAreaInsets` 的定义是 “The safe area inset of the container view.”
- `background(_:ignoresSafeAreaEdges:)` 的说明明确说，背景是 anchored to the modified view’s bounds

这两条放在一起，能推出一个关键事实：

> 在 `.background { GeometryReader ... }` 里拿到的 `safeAreaInsets`，是“这个 background 所在容器”的 safe area，不是天然等于“整块屏幕的 status bar / home indicator 安全区”。

所以当前这段逻辑：

- 先用 `proxy.safeAreaInsets.top/bottom` 算 `wallpaperHeight`
- 再 `offset(y: proxy.safeAreaInsets.top)`

并不能保证 wallpaper 真的被裁到我们肉眼理解的“状态栏以下、home indicator 以上”。

这也是为什么：

- 虽然代码里已经显式写了“想避开 safe area”
- 但实际截图里，顶部依然能看到 wallpaper 条带

当前截图证据：

- `/tmp/memorypalace-ios-safearea-check.png`

这说明：

> 现在不是“参数没调对”，而是 wallpaper 的挂载层级本身就不适合承担 safe-area 精确裁切。

这就是第二层根因。

---

## 4. 第三层原因：iOS 页面本身故意留了很多会暴露 wallpaper 的区域

即使不看 root 挂法，页面内部也已经有很多“只要底色半透明，就一定露壁纸”的结构。

### 4.1 左页 Sidebar 整页背景本身就是半透明 sidebarBg

代码在：

- [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:330)

```swift
if isIOSStyle {
    Theme.sidebarBg.ignoresSafeArea()
}
```

问题在于 `Theme.sidebarBg` 不是不透明色。  
背景图模式下它已经被乘成 `0.82 alpha` 了。

所以列表页那些没被内层卡片盖住的区域：

- 顶部搜索条外侧
- 列表卡片上方
- 列表卡片下方 footer / 空白
- 底部安全区附近

都会透出 wallpaper。

### 4.2 左页内容卡本身也不是实底

代码在：

- [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:261)

```swift
RoundedRectangle(...)
    .fill(Theme.mainBg.opacity(0.6))
```

也就是说，列表主卡不是“真正把背景盖住”的卡，而是又叠了一层更透明的卡。

这会把 wallpaper 感继续放大，尤其是列表页那种大面积空白内容时，视觉上就会形成“上下两坨很大的背景图”。

### 4.3 中页聊天顶部还主动做了一个渐变到透明的 overlay

代码在：

- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:142)
- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:149)
- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:161)

这里做了：

- `ScrollView.background(Theme.mainBg)`
- 顶部再叠一个 `VariableBlurView`
- 再叠一个从 `Theme.mainBg` 逐步过渡到 `0 alpha` 的渐变
- 而且这个 overlay `ignoresSafeArea(.all, edges: .top)`

所以聊天页顶部工具条下方那一片，本来就是“设计上允许逐渐露出下面那层”的。

只要下面那层是 wallpaper，顶部就一定会看到它。

### 4.4 中页空状态虽然有背景，但也是半透明主底色

代码在：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:726)

```swift
.background(Theme.mainBg)
```

而 `Theme.mainBg` 在背景图模式下已经不是实底了。  
所以空状态页也只是“盖了一层半透明奶白”，不是把壁纸隔绝掉。

### 4.5 页码点被故意放进了底部安全区

代码在：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:183)
- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:196)

```swift
.ignoresSafeArea(.container, edges: .bottom)
```

也就是说，底部页码区域本来就被设计成踩进 home indicator 那块区域。

只要 root wallpaper 还存在于那块区域，点点后面就会直接看到它。

---

## 5. 为什么我现在认为“主因不是一条线，而是叠加”

如果只有第一层，没有第二层：

- 页面会变得偏通透
- 但不一定在顶部 safe area 也漏得这么明显

如果只有第二层，没有第一层：

- root wallpaper 可能会进错层
- 但只要 page surface 是实底，大部分区域还是会被盖住

如果只有第三层，没有前两层：

- 页面有留白和渐变
- 但下面如果只是纯色底，不会形成明显的 wallpaper 条带

现在之所以会变成“你一眼就能看见的 bug”，是因为这三层同时成立：

1. wallpaper 真在 root 上
2. page surface 被整体改半透明
3. iOS 页面本身又有大量 top/bottom 留白和渐变透明结构

这才会让问题从“主题有点通透”升级成“顶部底部都在漏，已经像坏了”。

---

## 6. 哪些不是主因

这次我明确排除了几件事。

### 6.1 不是背景图文件本身坏了

`ThemeBackgroundView` 能正确读图、渲染、偏移、调 opacity。

相关代码在：

- [ThemeBackgroundView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ThemeBackgroundView.swift:19)
- [ThemeBackgroundView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ThemeBackgroundView.swift:82)

所以这不是“图片没导入好”。

### 6.2 不是背景图位置/透明度调节逻辑坏了

背景图参数本身是有持久化链路的：

- [ThemeManager.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Utils/ThemeManager.swift:282)
- [ThemeManager.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Utils/ThemeManager.swift:293)

所以这也不是“调节参数根本没生效”的那种 bug。

### 6.3 不是最早那次 page-width 回归导致的视觉假象

现在看到的 wallpaper leak，在当前截图里即使页面已经没有继续横向超宽，也依然存在。  
所以它和最初“整页被撑爆”不是同一个病。

---

## 7. 当前最可信的主因排序

如果必须排优先级，我现在的判断是：

### P0 主因

背景图模式把 `mainBg/sidebarBg` 这些 page-level surface 统一降成半透明。

这件事一发生，就注定所有页面留白都能透出 wallpaper。

### P0 主因

root wallpaper 被挂在 `.background { GeometryReader ... }` 这一层，并试图用该层的 `safeAreaInsets` 去裁切屏幕级 safe area。

这层级不可靠，所以顶部 / 底部无法被稳定切干净。

### P1 放大器

iOS 页面自身含有：

- 留白
- 渐变到透明
- `ignoresSafeArea(.top/.bottom)`
- 玻璃按钮悬浮在 page surface 上

这些结构会把前两条主因进一步放大成肉眼可见的大块漏图。

---

## 8. 一句话归纳

一句话归纳这次 bug 的真正原因：

> 背景图不是“漏出来了一点”，而是被作为 root canvas 正常铺上去了；真正出错的是，背景图模式又把整套 iOS 页面表面层一起做成了半透明，而 root wallpaper 的 safe-area 裁切还挂在了错误层级上，于是顶部、底部和所有大块留白都开始稳定透图。

---

## 9. 这份 research 的边界

这份文档只回答：

- 为什么现在还在漏
- 漏的是哪几层
- 哪个是主因，哪个是放大器

它**不包含修复方案**。  
下一步如果要写 plan，应该围绕这里的三层因果去拆，而不是继续做局部遮罩或视觉补丁。

---

## 10. 现在其实混着两类 bug，不是一类

继续往下拆之后，我认为当前“漏背景图”其实包含两种完全不同的病：

### 10.1 A 类：真的没盖住

这一类是结构问题。

典型位置：

- `ContentView` root wallpaper 自己在做 safe-area 裁切
- 页码点被放进底部安全区
- 某些顶部按钮区没有单独的实底 bar

代表代码：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:95)
- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:183)
- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:196)

这一类的特点是：

- 下面确实是 wallpaper
- 上面没有完整的 page surface 接住

所以这是真正意义上的“没盖住”。

### 10.2 B 类：其实盖了，但故意做成了半透明

这一类不是空洞，而是主题系统把结构层本身变透明了。

代表代码：

- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:274)
- [ThemeManager.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Utils/ThemeManager.swift:317)
- [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:330)
- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:727)

比如：

- 左页 root 是 `Theme.sidebarBg`
- 中页空状态是 `Theme.mainBg`
- 聊天页主体是 `Theme.mainBg`

这些代码表面上看都“有背景”。  
但在背景图模式下，它们已经不是实底，而是被统一降过 alpha 的表面。

所以从用户眼里看，它和“没盖住”几乎没有区别。

### 10.3 为什么这个区分重要

因为如果不先把这两类分开，就很容易做出错误判断：

- 看到壁纸，就以为一定是 safe area 没裁好
- 或者看到代码里有 `.background(Theme.mainBg)`，就以为页面一定已经被盖住了

其实现在两种情况都在同时发生。

---

## 11. 当前截图里，顶部和底部并不是同一种原因

基于当前截图：

- `/tmp/memorypalace-ios-safearea-check.png`

我认为顶部和底部来源不完全一样。

### 11.1 顶部更像 B 类：结构层半透明

在当前聊天空状态截图里，顶部能看到 wallpaper，但并不是只有最顶上一条细线。

实际现象更接近：

- 整个上半区都在透 wallpaper
- 顶部因为内容最少，所以透得最明显

这一点更符合“`Theme.mainBg` 本身半透明”的模式，而不是单独某一条 safe-area 没填到。

也就是说，顶部现在最大的原因更像：

> 页面确实有背景，但这个背景已经被主题系统降成了通透 surface。

### 11.2 底部更像 A+B 混合

底部页码区同时满足两件事：

1. 页码 overlay 自己踩进了底部安全区  
   代码在 [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:196)
2. 页面主底色又是半透明的

所以底部比顶部更复杂：

- 一部分是真正“页内容没接住”
- 另一部分是“接住了但 surface 太透”

这也解释了为什么底部看起来往往比顶部更像“两坨大背景图”。

---

## 12. 聊天页顶部那条，不只是 root wallpaper 的锅

我之前把重点放在了 root wallpaper 挂法上，但继续读代码后，要把聊天页顶部的责任再往下分。

在聊天页有真实对话时，`CardFlowView` 还会主动叠一个顶部视觉层：

- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:144)
- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:149)
- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:161)

这里不是简单一层纯色，而是：

- blur
- 再加从 `Theme.mainBg` 渐变到透明
- 并且向 top safe area 延伸

这意味着：

> 即使 root wallpaper 完全正确，聊天页顶部只要继续用“渐变到透明”这套结构，背景图仍然会被故意显露出来。

所以聊天页顶部问题不能只盯 `ContentView`，还要承认 `CardFlowView` 顶部本身就在做“露底层”的视觉结构。

---

## 13. 左页为什么会显得特别像“上下两坨背景图”

左页之所以观感特别糟，不是因为它比别页多一个 bug，而是因为它同时拥有最容易放大通透感的几种结构：

1. 根背景是 `Theme.sidebarBg.ignoresSafeArea()`  
   代码在 [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:330)
2. 列表主内容又包了一层 `Theme.mainBg.opacity(0.6)` 的圆角卡  
   代码在 [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:261)
3. 顶部搜索区和底部 footer 都属于大面积留白区  
   代码上能看到：
   - 顶部搜索/新建条 [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:42)
   - 底部 footer 区 [SidebarView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SidebarView.swift:320)

所以左页的视觉结果是：

- 最外层已经透
- 中间内容卡也透
- 上下还留很多空

这会让 wallpaper 在用户眼里形成非常稳定的“上面一坨、下面一坨”。

严格说，这不是图片太大，也不是 offset 没调好；  
而是左页表面系统本身从根到底就是通透链路。

---

## 14. 设置页/主题页为什么当时也会出类似问题

继续对照设置页链路后，也能解释为什么用户前面会在设置总页、主题页看到类似的顶底问题。

设置页 iOS 根结构是：

- [SettingsView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/SettingsView.swift:85)
- [ThemeSettingsTab.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ThemeSettingsTab.swift:294)
- [ThemeEditorView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ThemeEditorView.swift:234)

这些页的共同点也是：

1. 整页背景直接用 `ThemeBackgroundView(...).ignoresSafeArea()`
2. `List` 自己透明：`.scrollContentBackground(.hidden)`
3. row 背景再单独用 `Theme.mainBg`

而 `Theme.mainBg` 在背景图模式下也是半透明。

所以设置页当时出现类似顶底问题，并不是新的独立 bug，仍然属于同一套因果链。

这也再次说明：

> 当前问题不是某个页面单独忘了加背景，而是“背景图模式 + page surface alpha 化”这个决策打到了多个页面。

---

## 15. 目前最应该坚持的判断

继续往下想之后，我现在最该坚持、不该再摇摆的判断是：

### 15.1 这不是图片参数 bug

不是：

- 图片太大
- 图片位置偏了
- 图片透明度滑杆不对

这些都只会影响“漏出来的 wallpaper 长什么样”，不会决定“会不会漏”。

### 15.2 这不是单纯 safe-area bug

safe area 的确有问题，尤其底部更明显。  
但如果把所有 `mainBg/sidebarBg` 继续保留为背景图模式下的半透明 surface，就算 safe area 全对，主界面仍然会显得像在漏壁纸。

### 15.3 最本质的问题是“结构层被主题化过头”

更准确地说：

> 背景图模式把本来应该承担结构遮蔽职责的 page surface，也一起主题化成了 atmosphere layer。

一旦结构层不再承担遮蔽职责，root wallpaper 就会从所有留白和所有透明梯度里稳定露出来。

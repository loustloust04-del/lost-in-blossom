# Research: iOS 聊天背景失效与 Safe Area 回归

日期：2026-04-18  
分支：`codex/theme-kelivo-settings`  
范围：只找原因，不给修法

---

## 1. 这次其实是两类回归，不是一类

Susu 这次指出的现象有两个，而且它们不是同一个 bug：

1. 背景图不再对聊天背景本身生效。
2. 我后来补的 iOS safe-area 条把聊天底栏层级打乱了：
   - 页面指示器飘进聊天输入区附近
   - 底部还留着一条明显的白条
   - 聊天底部的输入栏 / 贴纸栏 / safe-area 承载层互相穿透

这两件事的共同点只是都发生在最近两笔修复提交之后，但根因并不相同。

---

## 2. 第一类回归：为什么背景图不再对聊天背景生效

### 2.1 直接引入点在 `01e5fea`

相关提交：

- `01e5fea Fix iOS wallpaper leak surfaces`

这个提交里，最关键的变更不在 `ThemeBackgroundView`，而在：

- [AppTheme.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Models/AppTheme.swift:274)

当前 `applyingBackgroundImageSurfaceStyle(for:)` 只再给这些 token 降 alpha：

- `userBubble`
- `assistantBubble`
- `accent`

但不再给这些 token 降 alpha：

- `mainBg`
- `sidebarBg`

也就是说，从 `01e5fea` 开始：

> 背景图主题仍然存在，但 page-level surface 已经不再通透。

---

### 2.2 聊天页本身几乎整页都被 `Theme.mainBg` 盖住

背景图仍然是全局 root 背景，挂在：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:95)

```swift
.background {
    ThemeBackgroundView(...)
        .ignoresSafeArea()
}
```

但聊天页自己的表面层又在多处直接使用了 `Theme.mainBg`：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:273)
- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:132)
- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:234)

具体包括：

1. `iOSChatPage` 整页 `.background(Theme.mainBg)`
2. `ScrollView` 自己 `.background(Theme.mainBg)`
3. `CardFlowView` 外层容器 `.background(Theme.mainBg)`
4. 顶部 blur overlay 的渐变也是从 `Theme.mainBg` 开始
5. 输入栏底部 blur overlay 也是逐步落到 `Theme.mainBg`

而 `Theme.mainBg` 现在已经重新是不透明底色。

于是结果就是：

> 背景图没有坏，坏的是“聊天页已经不再允许它透进来”。

所以现在肉眼看到的是：

- 背景图还能在 root 层存在
- 但聊天页的大面积内容背景已经被实底奶白盖掉
- 只在没有被页面 surface 完整遮住的洞里，背景图才会出现

这就解释了为什么用户会感觉：

> “背景图根本没作用到聊天背景，只剩边边角角偶尔漏一下。”

---

### 2.3 结论：聊天背景失效不是渲染坏了，是承载层职责被改掉了

这不是 `ThemeBackgroundView` 没加载图片，也不是 offset / opacity 失效。

真正原因是：

1. 背景图还在 root
2. 聊天页自己的所有大面都被不透明 `Theme.mainBg` 吃掉
3. `01e5fea` 为了止 leak，顺手把“聊天页还能感受到背景图”这件事也一起切断了

所以当前“聊天背景不生效”是结构结果，不是偶发样式 bug。

---

## 3. 第二类回归：为什么 safe-area 条把聊天底栏搞乱了

### 3.1 直接引入点在 `f2a27e2`

相关提交：

- `f2a27e2 Fix iOS safe area wallpaper leak`

这个提交在：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:152)

新加了一层：

```swift
iOSSafeAreaFill(topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom)
```

它不是页面自己的一部分，而是放在 `ContentView` 的 root iOS layout 里，和 `TabView` 同级。

并且页码点的底部位置也从固定 `15` 改成了：

```swift
.padding(.bottom, max(proxy.safeAreaInsets.bottom, 12) + 8)
```

也就是：

> safe-area 补丁和页码点，都是在 root 层全局处理的，不知道聊天页底部到底现在是什么状态。

---

### 3.2 聊天底部实际早就不是“一个简单的底栏”

聊天页底部本来就已经有三层不同职责：

#### A. 输入栏

- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:187)

`ChatInputBar` 是通过：

```swift
.safeAreaInset(edge: .bottom, spacing: 0)
```

插到聊天页底部的。

#### B. 贴纸面板

- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:225)
- [StickerKeyboardPanel.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/StickerKeyboardPanel.swift:113)

贴纸面板不是 safe-area inset，而是外层 `.overlay(alignment: .bottom)`，而且它自己还：

```swift
.ignoresSafeArea(.container, edges: .bottom)
```

#### C. 页面指示器

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:176)

页码点是在 `ContentView` root 的 `ZStack` 里，单独叠的一层。

所以聊天页底部原本就有：

1. 页面内容
2. ChatInputBar
3. StickerKeyboardPanel
4. 页码点 overlay

现在再加一个 root 级的 `iOSSafeAreaFill`，就变成第五层。

---

### 3.3 `iOSSafeAreaFill` 最大的问题：它完全不知道聊天底部真正长什么样

`iOSSafeAreaFill` 当前逻辑在：

- [ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/ContentView.swift:291)

它做的是：

1. 用 `Theme.mainBg` / `Theme.sidebarBg` 单独补 top / bottom safe area
2. 底部固定补 `bottomInset + 28`
3. 不读取聊天底栏是否展开
4. 不知道输入框是否聚焦
5. 不知道贴纸面板是否在场
6. 不知道页码点当前是不是应该让位

所以它只是“机械地在 root 层再刷一条底色”。

这会带来两个直接后果。

#### 后果 A：页码点会飘进聊天输入区的视觉范围

因为页码点仍然在 `ContentView` 的全局 overlay 里，而 `ChatInputBar` 本身在 iOS 端又不是实底块，而是：

- [CardFlowView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/.claude/worktrees/theme-kelivo-settings/MemoryPalace/Views/CardFlowView.swift:607)

```swift
.background(alignment: .bottom) {
    VariableBlurView(...)
    LinearGradient(...)
}
```

也就是：

> 聊天底栏后面本来就是半透明 blur + 渐变，不是完全遮蔽层。

因此 root 层的页码点并不会被它彻底吃掉，而是会从底栏透明区透出来。

这就是为什么截图里页码点会看起来“飘在输入框下面那一坨 UI 中间”。

#### 后果 B：底部白条不是新主题，而是 root 补丁自己刷出来的条

`iOSSafeAreaFill` 底部直接刷了一段固定高度的 `Theme.mainBg`：

```swift
currentIOSPageSurface
    .frame(height: bottomInset + 28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .ignoresSafeArea(edges: .bottom)
```

这意味着：

> 底部最后看到的“白条”并不是聊天页自然形成的，而是 root 级 safe-area patch 主动补出来的。

它和聊天底栏没有统一设计，也没有跟 sticker / input bar 协调，所以视觉上就像“底下又垫了一块不该存在的板子”。

---

## 4. 这两个问题为什么会同时出现

因为最近两步修的是相反方向：

### `01e5fea`

目标是止住 wallpaper leak。  
做法是让 page surface 重新变不透明。

副作用：

- wallpaper 不再作用到聊天背景本体

### `f2a27e2`

目标是补住顶底 safe area。  
做法是在 root iOS layout 额外刷 top / bottom 条。

副作用：

- 把聊天页原本已经很复杂的底栏层级搅乱
- 页码点与输入栏/贴纸栏打架
- 底部出现额外实底条

所以当前并不是“一处小偏差”：

1. 第一笔修复把聊天页变成了太实
2. 第二笔修复又把 safe-area 修补放错到了 root 层

最后就变成了现在这张截图里的状态：

- 聊天主背景没吃到 wallpaper
- safe area 又被单独补坏了

---

## 5. 结论

### 结论 A：聊天背景不生效

不是背景图功能坏了。  
是 `01e5fea` 为了止 leak，把 `mainBg/sidebarBg` 从“可感受到 wallpaper 的 surface”改成了“完全不透明的 structure layer”，而聊天页正好大量依赖 `Theme.mainBg`。

### 结论 B：safe-area 条打坏底栏

不是聊天栏自己突然乱掉。  
是 `f2a27e2` 把 safe-area 修补做在了 `ContentView` root 这一层，和聊天页内部的：

- `safeAreaInset`
- `overlay`
- blur / gradient
- page indicator

完全脱节，导致底部视觉层级失真。

### 结论 C：这两件事必须分开修

当前最不能继续做的事，就是再往 `ContentView` root 上叠新的遮罩、渐变、补丁条。

因为：

1. 聊天背景失效属于“背景承载层职责丢了”
2. 底栏混乱属于“safe-area 修补挂错层级了”

它们虽然都出现在聊天页，但不是同一个开关能一起修好的问题。

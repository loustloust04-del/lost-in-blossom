# Research: 设置 / Prompt / 简单 页面

日期：2026-04-16

## 任务理解

这次只 research `设置 → Prompt → 简单` 这个页面，不写代码。

你想要的行为非常明确：

1. 初始是一个不大的输入框。
2. 当内容越来越多，输入框高度要跟着增长。
3. 增长到某个上限后，不再继续撑页面，改为输入框内部出现滚动条。
4. 如果之后删字，输入框要继续跟着缩小。
5. 删到足够少时，最后回到原始高度。

这不是“差不多自动变高”就行，而是一个很具体的交互契约：**能长、能停、能滚、还能缩回去。**

---

## 我深读后看到的当前状态

### 1. macOS 现在实际跑的不是自动增高

当前 macOS 的 Prompt 简单模式入口在 `MemoryPalace/Views/SettingsView.swift`：

- `personaTab` 在第 1437-1448 行选择 `personaSimpleMode`
- `personaSimpleMode` 在第 1987-2004 行
- 真正的输入框实现 `personaTextField` 在第 2021-2042 行

现在这里用的是固定高度 `TextEditor`：

- 默认高度 40
- “角色描述”传 60
- “对话示例”传 50

也就是说，**当前 macOS 这页根本没有“随输入动态长高”的实现**，所以它现在一定达不到你要的效果。

### 2. 外层容器其实已经允许页面整体滚动

`macOSSettingsBody` 在第 175-200 行把 tab 内容包在了外层 `ScrollView` 里，而且整个设置窗固定为 `480 x 560`。

这点很重要：

- 页面整体已经能滚
- 所以简单模式里的每个输入框完全可以先自己长高
- 长到一个上限后，再只让该输入框内部滚动
- 不会把整个设置页撑炸

从结构上说，这个目标是成立的，不需要大改整页架构。

### 3. 仓库里确实已经试过两条路，但都没有成为 macOS 的最终解

#### 路 A：`TextField(axis: .vertical)`

仓库历史：

- `df35d2e`：把简单模式从 `TextEditor` 改成 `TextField(axis: .vertical)`
- `c3691e7`：继续加原地编辑和全屏按钮
- `e8d265d` / `6eaa9e3` / `0453920`：持续修这套行为

当前代码里，这条路只留在 iOS helper 上：

- `iOSSimpleField` 第 747-785 行
- 第 779-783 行仍然是 `TextField(..., axis: .vertical).lineLimit(1...50)`

但它没有被 macOS 简单模式复用。

#### 路 B：自制 `AutoGrowingTextEditor`

仓库历史：

- `d115fb0` 新增 `AutoGrowingTextEditor`

当前组件在 `SettingsView.swift` 第 3358-3404 行，逻辑是：

- 用一个隐藏的 `Text` 测内容高度
- 再把 `TextEditor` 的 frame 高度夹在 `minHeight...maxHeight`

这个组件当前也只挂在 iOS 的 `iOSSimpleSlotSection` 上（第 723-724 行），**macOS 简单模式并没有使用它**。

---

## 为什么这个页面现在会显得“古怪”

我认为不是单点 bug，而是下面几件事叠在一起：

### 1. macOS 和 iOS 的简单模式已经分叉了

现在同一个“简单模式”概念，实际上有三套思路残留：

- macOS：固定高度 `TextEditor`
- iOS 当前主路径：`TextField(axis: .vertical)`
- iOS 旧 helper：`AutoGrowingTextEditor`

所以“简单模式应该长什么样、用什么输入控件、哪个行为才算正确”这件事，在代码层已经不统一了。

### 2. `TextField(axis: .vertical)` 本身不适合当这个页面的最终解

Apple 官方文档对 `TextField(_:text:axis:)` 的描述很关键：

- `axis` 是“preferred axis”
- 文档明确说：**depending on the style of the field, this axis may not be respected**

也就是说，它更像“尽量这样滚”，不是“我给你一个可精确控制的多行编辑器”。

而你现在要的是一个非常确定的编辑体验：

- 到多少高度停
- 什么时候出现内部滚动
- 删除内容后必须缩回

这类精确行为，不适合押宝在 `TextField(axis: .vertical)` 这种“偏好式”接口上。

### 3. 现有 `AutoGrowingTextEditor` 是启发式方案，不是 macOS 级别的精确控件

这个组件的本质是：

- 用隐藏 `Text` 估算高度
- 再驱动 `TextEditor` 高度

这类做法在 SwiftUI 里常见，但它依赖“测量视图”和“真实编辑视图”高度始终足够接近。

问题是这两个东西不是同一个底层控件：

- 一个是 `Text`
- 一个是 `TextEditor`（背后是 AppKit 文本系统）

所以它天然容易出现：

- 行高不完全一致
- inset / padding 不完全一致
- 到上限时滚动状态和高度切换边缘不够稳定
- 看起来“差不多”，但手感发虚

如果只是 iOS `List` 里临时救火，这种方案可以接受；但如果要把它当成 **macOS Prompt 简单页面的最终交互**，我觉得不够稳。

### 4. Apple 自己对 macOS 大段文本编辑给出的主角其实是 `NSTextView`

Apple 文档对 AppKit 的态度也很直白：

- 简单输入用 `NSTextField`
- 更大段、更完整的文本编辑用 `NSTextView`

而 Prompt 简单模式这五个框，本质上就是“短到中长文本编辑器”，尤其“角色描述 / 对话示例 / 系统指令”根本不是普通单行输入。

所以从第一性原理看，这里更像 `NSTextView` 的地盘，不像 `NSTextField` 的地盘。

---

## 我认为正确的方向

### 结论

**这页不该继续在 macOS 上赌 `TextField(axis: .vertical)`，也不该直接把现在的 `AutoGrowingTextEditor` 生搬过去。**

更稳的方向是：

**给 macOS 的 Prompt 简单模式单独做一个 AppKit-backed 的多行编辑器，用 `NSTextView + NSScrollView` 精确控制高度与滚动。**

### 为什么我推荐这条路

因为 AppKit 正好提供了你要的那几个控制点：

- `NSText` / `NSTextView` 的 `isVerticallyResizable`
- `minSize` / `maxSize`
- `NSTextContainer` 的宽度跟踪
- `NSScrollView` 的纵向滚动条控制

这和你的目标是一一对应的：

- 内容增加时：重新计算内容高度，往上长
- 达到 maxHeight：编辑器高度卡住
- 超过 maxHeight：内部滚动条接管
- 删除内容：重新计算内容高度，再往下缩
- 低于 minHeight：回到初始高度

这是“直接控制真正的文本系统”，不是“拿一个别的视图去猜它应该多高”。

---

## 这页后续实现时，交互上我建议坚持的边界

这里先记结论，不展开 plan。

### 1. 只改 macOS 的 `Prompt / 简单`

不要顺手统一 iOS。

原因：

- 你这次点名的是这个页面
- 当前问题集中在 macOS 这条路径
- iOS 现在本来就有另一套容器约束（`List` / `Section` / push 页面）
- 一次只收一个战场，更符合你说的“小步迭代”

### 2. 初始高度要稳定，不要一上来就显得巨大

你想要的是“原始小框，越打越长”，所以 minHeight 应该是一个舒服的一到两行视觉高度，而不是默认给半屏。

### 3. maxHeight 要比现在更清楚地成为一个“阈值”

到达阈值以后，行为要明显切换成：

- 框不再继续长
- 内部滚动条出现

而不是继续把整页撑得忽大忽小。

### 4. 缩回去必须是实时的，不接受“长得动，缩不回”

这是这次需求里最核心的一条。

只要删字后高度不能即时回落，这个页面就仍然是失败的。

### 5. 外层页面滚动和内层编辑器滚动要分工清楚

- 平时：页面随内容自然排布
- 单个框过长：只让这个框内部滚
- 不要让外层和内层同时争夺滚动感

---

## 风险提醒

### 1. 这不是“修一行 modifier”级别的问题

如果目标只是“看起来会变高”，SwiftUI 小修补可以试。

但你这次要的是：

- 长高
- 到上限停住
- 内滚
- 再删又缩回

这已经是一个明确的控件行为定义，所以我认为直接做成 macOS 专用组件更稳。

### 2. 这页现在是每次输入都 `psm.save(p)`

当前绑定在每次文字变化时都会保存 preset。

这本身不是错，但如果后续实现不小心让 editor view 每次输入都被重建，就会出现：

- 光标跳动
- 滚动位置丢失
- IME 输入手感差

所以之后真做时，必须保证这个编辑器是“稳定实例”，不能一边打字一边反复销毁重建。

### 3. 不要把全屏编辑按钮和这次修复绑死

这次问题的核心是“原地编辑器行为”。

全屏编辑按钮是否保留，是第二层决策；不要让它干扰对主问题的判断。

---

## Research 结论

一句话总结：

**当前 macOS 这页没有自动增高；而过去试过的两条 SwiftUI 路子都更像权宜之计。要稳定实现你要的“长高 → 封顶 → 内滚 → 删除再缩回”，最靠谱的方向是给 macOS Prompt 简单模式做一个基于 `NSTextView + NSScrollView` 的专用输入组件。**

---

## 参考

### 仓库内

- `MemoryPalace/Views/SettingsView.swift:175-200`
- `MemoryPalace/Views/SettingsView.swift:1987-2042`
- `MemoryPalace/Views/SettingsView.swift:723-724`
- `MemoryPalace/Views/SettingsView.swift:747-785`
- `MemoryPalace/Views/SettingsView.swift:3358-3404`
- `MemoryPalace/Utils/Theme.swift:30-60`
- 提交：`df35d2e`, `c3691e7`, `e8d265d`, `6eaa9e3`, `d115fb0`, `0453920`, `af91b8c`

### Apple 文档

- [TextField init(_:text:axis:)](https://developer.apple.com/documentation/swiftui/textfield/init%28_%3Atext%3Aaxis%3A%29?changes=_4_7_9)
- [NSText](https://developer.apple.com/documentation/appkit/nstext)
- [NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [NSScrollView / hasVerticalScroller](https://developer.apple.com/documentation/appkit/nsscrollview/hasverticalscroller)
- [Tracking the Size of a Text View](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextStorageLayer/Tasks/TrackingSize.html)

---

## 状态

Research 完成。

**DON'T IMPLEMENT YET**

等粟粟看完这份 research，再决定要不要进入下一轮 plan。

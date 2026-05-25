# Research: 设置 / Prompt / 简单 页面（iOS 优先）

日期：2026-04-16

## 任务理解

这轮先不管 macOS，优先把 **iOS 的 `设置 → Prompt → 简单`** 研究清楚。

目标不是“输入框差不多能多行”，而是这组明确行为：

1. 初始高度小，像正常设置页输入框。
2. 文本变多时，输入框跟着变高。
3. 到某个上限后，不再继续撑开，改为输入框内部滚动。
4. 删除内容后，输入框要实时缩回。
5. 同时不能破坏 iOS 设置页现在那套舒服的间距和节奏，尤其不要把 `iOSGeneralPage` 的排版带坏。

---

## 当前 iOS 真实实现

### 1. Prompt 简单模式现在走的是 `TextField(axis: .vertical)`

当前 iOS Prompt 页面在 `MemoryPalace/Views/SettingsView.swift`：

- 简单模式入口：第 `612-633` 行
- 简单模式外层容器：第 `615` 行，`VStack(alignment: .leading, spacing: 20)`
- 单个字段实现：`iOSSimpleField`，第 `747-785` 行
- 字段内部布局：第 `760` 行，`VStack(alignment: .leading, spacing: 6)`
- 真正输入控件：第 `779-783` 行，`TextField(..., axis: .vertical).lineLimit(1...50)`

也就是说，当前 iOS 的简单模式不是 `TextEditor`，也不是 UIKit 包装，而是：

- 一个 `List`
- 里面一个 `Section`
- `Section` 里放一个大 `VStack`
- `VStack` 里堆 5 个 `iOSSimpleField`
- 每个 field 内部用 `TextField(axis: .vertical)` 试图自动增高

### 2. 现在这页的间距体系其实和 `iOSGeneralPage` 不是一套

`iOSGeneralPage` 在 `MemoryPalace/Views/GeneralSettingsTab.swift`：

- 主要字段容器：第 `175-179` 行，`VStack(spacing: 8)`
- `SettingsTextField` 本体在 `SettingsView.swift` 第 `3144-3169` 行
- `SettingsTextField` 的输入框竖向 padding 用的是 `Theme.optionRowVerticalPadding`

而 iOS Prompt 简单模式当前是：

- 字段与字段之间：`spacing: 20`
- 单字段内部 label 和 editor 之间：`spacing: 6`
- 输入框内 padding：写死 `10`

所以现在的事实是：

**Prompt 简单模式本来就没有复用 `iOSGeneralPage` 那套 spacing token。**

这反而是个好消息，因为它说明：

- 如果我们只改 Prompt 简单模式，不会“自动冲坏” `iOSGeneralPage`
- 真正要注意的是：后续别把组件做得把外层 spacing 也一口吞掉

### 3. 仓库里之前试过另外一条路：`AutoGrowingTextEditor`

历史上有个 `AutoGrowingTextEditor`：

- 组件定义在 `SettingsView.swift` 第 `3358-3404` 行
- 旧 helper `iOSSimpleSlotSection` 第 `710-744` 行还在调用它

但要注意：

- 当前简单模式主路径并没有走 `iOSSimpleSlotSection`
- 当前真正使用的是 `iOSSimpleField`
- 所以这个组件现在更像“旧尝试残留”，不是当前行为来源

---

## 为什么现在 iOS 还是不够“能用”

### 1. `TextField(axis: .vertical)` 只能提供“差不多多行”，不是你要的强约束行为

你要的是：

- 长高
- 到上限停住
- 内部滚动
- 删除后缩回

而当前 `TextField(axis: .vertical)` 只是在告诉系统“偏好多行”。它适合轻量多行输入，但不适合这种需要精确控制高度阈值和滚动切换的场景。

换句话说：

- 它可以“看起来像在变高”
- 但不适合作为这页最终行为保证

### 2. 现在没有一个真正的“maxHeight + 内滚 + 缩回”控制层

当前代码只有：

- `lineLimit(1...50)`
- 没有独立 `measuredHeight`
- 没有 `maxHeight` 状态切换
- 没有“超过阈值后只在内部滚”的控制

所以现在即便输入框能变高，它也只是把高度交给 SwiftUI 猜，不是你要的那种稳定交互。

### 3. 旧的 `AutoGrowingTextEditor` 也不够稳，至少不适合直接当最终方案复用

这个组件的做法是：

- 用隐藏 `Text` 测高度
- 用测出来的高度驱动 `TextEditor`

这类方案在 SwiftUI 里很常见，但它的问题也很典型：

- 测量视图不是实际编辑视图
- 高度边界靠“估算”而不是真实文本控件反馈
- 接近上限时，滚动和高度切换容易发虚
- 删除后缩回虽然有机会实现，但边界手感不一定稳定

如果只是临时补丁可以考虑；但如果目标是“这页以后就别再怪了”，我不建议直接把它当最终解。

---

## 我对 iOS 的判断

### 结论

**iOS 这页最好做成一个小而专用的输入组件，但组件化范围只到“编辑器本体”，不要把外层布局一起吃进去。**

也就是：

- 做一个 `iOS-only` 的多行 Prompt 编辑器组件
- 它只负责：
  - 文本绑定
  - placeholder
  - 动态高度
  - `maxHeight`
  - 超过上限后内部滚动
  - 删除后缩回
- 外层仍然由页面自己控制：
  - Section
  - 标题
  - 全屏按钮
  - 字段之间的 spacing
  - 页面说明文字

### 为什么这样不会和 `iOSGeneralPage` 冲突

因为 `iOSGeneralPage` 的间距控制点都在外层：

- `VStack(spacing: 8)`：`GeneralSettingsTab.swift:175-179`
- `Theme.optionRowVerticalPadding`：`SettingsView.swift:3163`
- `Theme.optionRowSpacing`：`AppearanceSettingsTab.swift:203`

如果未来的新组件只管“这个多行框怎么长高和滚动”，而不去内置整套 section/row 排版，那它就不会改写 `iOSGeneralPage` 的节奏。

一句话：

**冲突不在“做不做组件”，冲突在“组件吞不吞布局权”。**

我建议的做法是不吞。

---

## iOS 更稳的方向

### 方向判断

对 iOS 来说，我也不想继续赌纯 SwiftUI 的 `TextField(axis: .vertical)`。

更稳的是：

**做一个基于 `UITextView` 的 `UIViewRepresentable` 小组件。**

理由很直接：

- `UITextView` 天生就是多行编辑器
- 可以真实拿到内容高度
- 可以精确控制 `isScrollEnabled`
- 可以在小于阈值时自适应高度
- 超过阈值时固定高度并打开内部滚动
- 删除内容后重新计算，再缩回去

这条路和用户要的交互是对齐的，不是猜出来的。

### 我认为这个组件应该长什么样

这里只写 research 结论，不进入 plan。

建议这个组件只暴露很少的参数：

- `text`
- `placeholder`
- `minHeight`
- `maxHeight`

可选：

- `font`
- `onEditingChanged`

但不要把下面这些也塞进去：

- label
- 全屏按钮
- 外层 section
- 页面级 spacing

这些应该继续留在 Prompt 页外层。

---

## 对当前页面排版的额外发现

### 1. Prompt 简单模式现在的 spacing 是写死的

当前 iOS 简单模式：

- 字段之间：`spacing: 20`
- 单字段内部：`spacing: 6`

它没有接入 `Theme.optionRowSpacing` 这套 token。

所以如果你说“还要保持 iOSGeneralPage 那些自适应间距”，那我理解成：

- 后续实现时，最好顺便把 Prompt 简单模式的间距也往 token 化方向靠
- 至少不要继续扩大 hard-coded 数字的分叉

### 2. 组件化和 token 化是两件事

这两件事不要绑死：

- 组件化：解决输入框行为问题
- token 化：解决不同页面的 spacing 统一问题

这轮优先级上，**行为正确 > 间距统一**。

但如果实现时能顺手让 Prompt 简单模式更贴近 iOS 现有设置页节奏，那会更稳。

---

## 风险提醒

### 1. `List` 里的可变高输入框要小心复用和跳动

iOS 的 `List` 对可变高内容比普通 `ScrollView` 更敏感。

后续实现要特别注意：

- 输入时不要反复失焦
- 高度变化不要造成 cell 抖动
- 不要一输入就让整个 section 重新布局得过分明显

### 2. 当前是每次输入都 `psm.save(p)`

现在输入绑定每改一个字符就会保存 preset。

如果后续组件更新过程不稳，容易出现：

- 光标跳动
- 中文输入法候选异常
- 滚动位置抖动

所以真做时必须让这个 UIKit 文本视图实例保持稳定，不要每次 change 都被 SwiftUI 重建。

### 3. 全屏编辑按钮不该和这次修复绑死

全屏编辑是补充入口，不是主问题。

这次先把“原地输入框能不能像正常人一样长高/封顶/缩回”解决，才是主线。

---

## Research 结论

一句话总结：

**iOS 这页应该做一个小型、iOS 专用、只负责编辑器本体的 `UITextView` 组件；这样能把动态长高、上限后内滚、删除后缩回做稳，同时不会和 `iOSGeneralPage` 的外层自适应间距冲突。**

macOS 的想法先继续留在之前那份 research 里挂起，不参与这轮实现判断。

---

## 参考

### 仓库内

- `MemoryPalace/Views/SettingsView.swift:612-633`
- `MemoryPalace/Views/SettingsView.swift:747-785`
- `MemoryPalace/Views/SettingsView.swift:710-744`
- `MemoryPalace/Views/SettingsView.swift:3144-3169`
- `MemoryPalace/Views/SettingsView.swift:3358-3404`
- `MemoryPalace/Views/GeneralSettingsTab.swift:175-179`
- `MemoryPalace/Views/AppearanceSettingsTab.swift:203`
- `MemoryPalace/Utils/Theme.swift:54-60`
- 历史提交：`df35d2e`, `c3691e7`, `d115fb0`, `0453920`, `af91b8c`

### 挂起的 macOS research

- [docs/research-prompt-simple-page-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/research-prompt-simple-page-2026-04-16.md)

---

## 状态

Research 完成。

**DON'T IMPLEMENT YET**

等粟粟看完这份 iOS research，再进入下一轮 plan。

# Plan: 设置 / Prompt / 简单 页面路线 B 实施方案（iOS）

日期：2026-04-16

基于：

- [docs/research-prompt-simple-ios-jank-caret-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/research-prompt-simple-ios-jank-caret-2026-04-16.md)
- [docs/plan-prompt-simple-ios-jank-caret-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/plan-prompt-simple-ios-jank-caret-2026-04-16.md)
- 当前实现：
  - `MemoryPalace/Views/SettingsView.swift`
  - `MemoryPalace/Views/IOSPromptTextView.swift`

---

## 这份 plan 要解决什么

上一份 plan 已经把路线判定清楚了：

**iOS `设置 → Prompt → 简单` 不再继续挂在 `List` 里修，而是走路线 B：简单模式脱离 `List`，改成显式可控滚动容器。**

这份文档不再负责“要不要换路线”。

这份文档只负责把路线 B 落成一个可执行的实施方案，确保下一轮实现时不再边猜边改。

---

## 最终目标

要收到的体验是：

1. 输入框随着字数增加自然长高。
2. 长到上限后，输入框内部自己滚动。
3. 删除内容后，输入框会平滑缩回原始高度。
4. caret 始终留在当前输入框的可视区里。
5. 页面不再和输入框抢滚动，也不再出现“掉到 z 轴后面”的错位感。
6. 保留已经修好的能力：
   - 回车换行正常
   - 文本同步正常
   - 全屏编辑来回同步正常
   - 预设切换 / 模式切换不丢内容

---

## 范围

### 会改

- 只改 iOS
- 只改 `设置 → Prompt → 简单`
- 会动：
  - `MemoryPalace/Views/SettingsView.swift`
  - `MemoryPalace/Views/IOSPromptTextView.swift`

### 不会改

- 不动 macOS Prompt 简单模式
- 不动 slots / raw / assembly / request 模式的页面容器
- 不动 `iOSGeneralPage`
- 不顺手统一整个设置页 spacing system
- 不顺手重做 Prompt 页视觉风格

---

## 核心策略

路线 B 不是单纯“把 `List` 换成 `ScrollView`”这么粗糙。

真正要做的是把“谁负责滚动、谁负责长高、谁负责 caret 可见性”三件事重新分工。

新的分工会是：

1. **外层页面负责字段级滚动。**
   简单模式页面自己决定当前聚焦的是哪个字段，并把那个字段滚到合适位置。

2. **输入框组件只负责自身尺寸和自身内容滚动。**
   它不再尝试向上爬祖先 `UIScrollView` 并强行推动外层容器。

3. **动态高度优先走 SwiftUI/Representable 的直接尺寸通道。**
   不再把“测高 -> 回写 `@State` -> 再改 frame”作为主链路。

---

## 结构改造方案

### Step 1：把 iOS Prompt 页拆成“简单模式页”和“非简单模式页”

当前 `iOSPromptPage` 的根是一个统一的 `List`，所有模式都塞在里面。

路线 B 会把它改成：

- `simple` 模式：走一条专用的 `ScrollView` 页面
- 其他模式：继续保留现有 `List`

这样做的原因是：

- 问题只集中在简单模式
- 没必要为了修一个页面，把 slots/raw/assembly/request 一起拖下水
- 可以把风险精确锁在简单模式这一条 iOS 路径里

这里我不会追求“大一统容器抽象”。

如果为了隔离风险，需要让 `simple` 与非 `simple` 在页面结构上适度分叉，这是合理的。

### Step 2：简单模式页改成显式 `ScrollView`

简单模式专页会使用：

- `ScrollViewReader`
- `ScrollView`
- 普通 `VStack`

这里不优先用 `LazyVStack`，因为字段数量固定，只有很少几块内容，普通 `VStack` 更直接，也更容易避免额外的懒加载时序变量。

这个页面会承载：

1. 预设选择卡片
2. 模式切换卡片
3. 5 个简单字段
4. 底部说明文案

也就是说，简单模式下不只是“输入框区域脱离 `List`”，而是**整页简单模式内容都脱离 `List`**，避免顶部卡片和输入区仍然被 `List` row 几何绑住。

### Step 3：保留现有视觉语言，不在这轮发散样式

虽然容器会从 `List` 换成 `ScrollView`，但视觉语言尽量维持现在这页的感觉：

- 背景继续用 `Theme.sidebarBg`
- 卡片继续贴近现有 inset grouped 的暖白块感
- 输入框继续用当前圆角输入区
- 当前 simple mode 自己写死的 `20 / 6` 节奏先保留，不在这轮顺手改成全局 spacing token

这一步的目标是只改交互结构，不顺手制造新的视觉变量。

---

## 输入框组件改造方案

### Step 4：`IOSPromptTextView` 停止负责“外层滚动”

这是路线 B 最重要的一刀。

当前组件会：

1. 自己滚 `UITextView`
2. 再去找祖先 `UIScrollView`
3. 对祖先再做一次 `scrollRectToVisible`

路线 B 下，这条链要砍掉外层部分。

组件只保留两类职责：

1. 文本编辑
2. 自身高度变化
3. 到上限后的内部滚动

组件不再：

- 猜外层滚动容器是谁
- 直接推动页面滚动
- 试图跨 UIKit / SwiftUI 层级去修页面可见性

### Step 5：把高度计算改成更直接的尺寸通道

当前 `IOSPromptTextView` 的主问题之一，是高度通过 `@State measuredHeight` 回传到 SwiftUI，再用 `.frame(height:)` 驱动布局。

路线 B 里，计划把它改成更直接的尺寸策略：

- 优先使用 `UIViewRepresentable.sizeThatFits(...)`
- 让 SwiftUI 在布局阶段直接拿到组件想要的高度
- 组件内部仍然保留 `minHeight / maxHeight`
- 超过 `maxHeight` 后只启用 `UITextView` 内部滚动

这样可以减少：

- UIKit 测高
- 异步回写 SwiftUI state
- SwiftUI 再次 relayout
- 页面再响应高度变化

这一整条“多一拍”的反馈链。

### Step 6：输入框新增“焦点变化”回调，不自己处理页面定位

为了让外层页面知道“当前是谁在编辑”，`IOSPromptTextView` 需要对外暴露一个最小焦点信号。

计划中的接口方向是：

- 当字段开始编辑时，把当前 `slotId` 上报给页面
- 当字段结束编辑时，允许页面清理焦点状态
- 当字段高度变化时，如果它正处于焦点中，页面可选择再次轻推一次外层滚动

这里的原则是：

**输入框只上报事实，不替页面做决策。**

---

## 页面级滚动策略

### Step 7：页面用稳定 field id 管“当前字段可见”

简单模式专页会给每个字段稳定 id，对应：

- `system`
- `charDescription`
- `personaDescription`
- `dialogueExamples`
- `jailbreak`

页面维护一个当前聚焦字段 id。

当发生这些事件时，页面滚动到对应字段：

1. 某字段开始编辑
2. 聚焦字段内容继续增长，且字段高度变化
3. 键盘出现后，首次需要把当前字段顶回可视区

这里滚动的单位不再是 caret rect，而是**整个字段容器**。

这是刻意的。

因为用户给出的证据已经说明，当前 bug 有几何/层级脱锚风险；继续追 caret 像素级坐标，收益不如先把“当前字段整块始终可见”这件事收稳。

### Step 8：页面滚动只做一层，不做双重推动

新结构下会明确分工：

- 如果内容还没超过 `maxHeight`：
  - 外层页面滚字段
  - 内层 `UITextView` 不滚
- 如果内容已经超过 `maxHeight`：
  - 输入框内部开始滚
  - 外层页面只保证这整个字段块仍在键盘上方可见

也就是说，外层和内层不再同时围着同一个 caret 抢着滚。

### Step 9：滚动触发时机收敛

当前实现的一个问题是 `ensureCaretVisible` 被很多时机反复触发。

路线 B 下会把页面级滚动收敛到少数明确时机：

1. `didBeginEditing`
2. 当前聚焦字段高度发生实际变化
3. 必要时的键盘出现后一次修正

不会再在：

- 每次 selection change
- 每次 refreshUI
- 每次内部 layout

都尝试推外层页面。

---

## `SettingsView.swift` 的具体落点

### Step 10：保留现有 draft/save/full screen 逻辑，不重写数据流

这轮不应该再去碰已经修好的同步机制。

所以这些逻辑原则上都保留：

- `iOSSimpleDrafts`
- `iOSSimpleDraftPresetId`
- `scheduleIOSSimpleDraftSave`
- `flushIOSSimpleDraftSave`
- `persistIOSSimpleDrafts`
- 全屏编辑完成后的 `applyIOSSimpleDraft` / `persistIOSSimpleDrafts`

这轮的重点是页面容器和输入组件，不是数据同步。

### Step 11：把 simple mode 的 UI 抽成一段独立视图

为了避免 `iOSPromptPage` 根部条件分支越来越乱，simple mode 计划抽成一段独立视图或独立 `@ViewBuilder`。

这里的“抽”只抽页面块，不做过度工程化。

目标只是让结构变成：

- `iOSPromptSimplePage(...)`
- `iOSPromptAdvancedList(...)`

而不是继续把所有条件都堆在一个巨大 `List` 里。

### Step 12：预设卡片和模式切换卡片允许少量重复，不为去重制造风险

路线 B 下，简单模式页和非简单模式页都需要“预设选择 + 模式切换”。

这里不强求抽成高度共享的大组件。

如果实现时发现：

- 共享会把绑定和副作用绕复杂

那么允许保留少量重复 UI 代码，只要行为一致、影响面更小就行。

这比为了“优雅复用”再把风险引回去更稳。

---

## 风险与对应控制

### 风险 1：换成 `ScrollView` 后，视觉不像原来的 iOS 设置页

控制方式：

- 只复刻必要的卡片层级和间距
- 不趁机改主题
- 不在这轮改 `Theme.optionRowSpacing`

### 风险 2：页面滚动虽然稳了，但组件内部长高还会发黏

控制方式：

- 同时改掉 `measuredHeight` 反馈链
- 让组件优先走 `sizeThatFits(...)`

### 风险 3：字段块可见了，但长文到上限后的内部滚动仍然不顺

控制方式：

- 明确“超过上限后只滚内部文本区”
- 只让页面负责字段级可见性，不碰 caret 级精细滚动

### 风险 4：模式切换或预设切换时草稿同步回退

控制方式：

- 不重写现有 draft/save 流程
- simple mode 只是换容器，不换数据通道

---

## 验证方案

实现后要按固定场景验证，不凭“手感差不多”收尾。

### 手动交互验证

至少覆盖下面这些动作：

1. 在 `角色描述` 连续输入多行，观察是否持续长高。
2. 输入到接近上限后继续输入，观察是否切到内部滚动。
3. 大量删字，观察是否持续缩回到初始高度。
4. 在键盘弹起时切换到 `用户描述`、`对话示例`，观察页面是否把当前字段保持在可视区。
5. 打开全屏编辑，编辑后返回，观察 simple mode 是否同步。
6. 切换 preset，再切回，观察草稿和持久化是否正确。
7. 在 `simple` 与 `raw/slots` 之间切换，观察是否没有旧 bug 回潮。

### 构建验证

实现后必须跑：

- `xcodegen generate`
- `xcodebuild -scheme MemoryPalace build`
- `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build CODE_SIGNING_ALLOWED=NO`

---

## Todo

- [x] 把 iOS Prompt 页拆成 simple / non-simple 两条容器路径
- [x] 为 simple mode 建立独立 `ScrollView` 页面
- [x] 保留 simple mode 现有 draft/save/full screen 数据流
- [x] 让 `IOSPromptTextView` 停止推动祖先 scroll view
- [x] 把输入框高度策略切到更直接的尺寸通道
- [x] 给输入框补最小焦点回调，让页面知道当前编辑字段
- [x] 用稳定 field id + 页面级滚动维护当前字段可见
- [ ] 验证“长高 / 封顶 / 内滚 / 缩回 / 同步 / 模式切换”
- [x] 跑完整构建验证

---

## 状态

IMPLEMENTED

这份文档对应的代码改动已经落地，构建验证已完成。

当前还没完成的是手动交互验证，所以“长高 / 封顶 / 内滚 / 缩回 / 同步 / 模式切换”的最终体验还需要继续实机或模拟器操作确认。

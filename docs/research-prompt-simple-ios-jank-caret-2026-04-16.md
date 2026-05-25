# Research: 设置 / Prompt / 简单 页面卡顿与光标出区（iOS）

日期：2026-04-16

基于：

- 当前实现：`MemoryPalace/Views/IOSPromptTextView.swift`
- 页面接线：`MemoryPalace/Views/SettingsView.swift`
- 用户截图：`/Users/susu/Downloads/截屏 2026-04-16 下午10.01.10.png`
- 用户运行时录像：`/Users/susu/Downloads/ScreenRecording_04-17-2026 00-36-45_1.mov`
- 用户局部截图：`/Users/susu/Desktop/Screenshot 2026-04-16 at 9.41.24 AM.png`
- Apple Developer Documentation

---

## 这轮排查的问题

这次不是在问“能不能长高/缩回”。

这两个行为现在已经成立。

这轮要排查的是：

1. 为什么输入框在长高/缩回时仍然明显卡顿。
2. 为什么输入过程中 caret 仍然经常跑出可视区。
3. 这到底是单个 `UITextView` 细节问题，还是页面容器层级本身在打架。

用户明确要求：先 research，不写代码。

---

## 先说结论

我当前的判断是：

**剩下的问题已经不再是“多行输入能不能做”，而是“当前这套高度回传 + 双滚动协调的架构本身就在制造卡顿和出区”。**

更具体地说，问题大概率不是一个点，而是三件事叠在一起：

1. **高度测量链路不够顺。**
当前实现没有把 UIKit 视图的首选尺寸直接交给 `UIViewRepresentable.sizeThatFits(...)`，而是走了一条“UIKit 里测高 -> 回调 -> SwiftUI `@State` -> `.frame(height:)` -> 再 layout”的反馈链。

2. **页面存在双滚动容器。**
外层是 `List`，内层是 `UITextView`，而 `UITextView` 本身就是 `UIScrollView` 的子类。当前代码在很多时机同时推动内外两层滚动，这很容易造成抖、卡、抢滚动权。

3. **caret 可见性维护时机不对，而且太频繁。**
当前实现把“滚到看见光标”这件事挂在文本变化、选区变化、layout、刷新等多个时机上；而 `scrollRectToVisible` 本身如果判断“已经可见”就会直接不动。只要调用时机略早于外层 `List` 完成 relayout 或键盘 inset 稳定，就很容易看起来“明明调用了，但 caret 还是出去了”。

4. **用户新增了一个比“出区”更强的现场线索：caret 可能不是单纯滚出去了，而是跑到了“z 轴后面”。**
这意味着问题不一定只是 scroll timing，还有可能包含：

- 行容器 / section 容器的 clipping
- `List` 行之间的层级叠放
- `UITextView` 自己的 caret 渲染层被周围 SwiftUI 容器视觉上盖住
- 输入框在长高缩回时，cell 合成顺序和可见区域发生错位

一句话总结：

**同步问题已经修好了；剩下的是 layout/scroll orchestration 问题，而且现在还带着明确的 layering / clipping 风险。**

在看完用户提供的运行时录像后，这个判断可以进一步收紧成：

**问题不再像“光标单纯滚出去了”，而更像“文本已经排到了下一行，但 field 的外层可见高度没有及时长起来，导致最后一行和 caret 被压在底边，视觉上像掉到 z 轴后面”。**

也就是说，录像证据更支持：

- `UITextView` 内部文本布局已经先走了
- 但 SwiftUI / `List` / row 可见区域没有同步长高
- 于是最后一行和 caret 落在 clipping / layering 的冲突带里

而不是更支持：

- 文本框本身已经长好了，只是滚动没跟上

用户后来补的局部截图又把这个判断往前推进了一步：

**有些时刻 caret 甚至不是贴在输入框底边，而是直接出现在输入框外、靠近上方 label 的区域。**

这说明问题不只是：

- 底边 clipping

还可能已经包含：

- caret 渲染坐标和文本容器坐标脱节
- 焦点文本视图的可视层与它的内容层发生错位
- SwiftUI / `List` row 在动态高度变化时，让 UIKit 子视图的绘制区域和逻辑区域短暂分家

---

## 运行时录像验证

我已经对用户提供的视频做了抽帧检查：

- 视频时长：约 `40.12s`
- 文件：`/Users/susu/Downloads/ScreenRecording_04-17-2026 00-36-45_1.mov`

抽帧后确认到的现象：

1. 在后半段，`角色描述` 内部文本继续增加到更多行。
2. 但 `角色描述` 这个输入块的可见高度没有以同样节奏往下长。
3. 最后一行文本会贴到输入块底边附近。
4. caret 在末段表现成“贴着底边闪烁 / 消失”，非常像进入了被裁切或被后层盖住的区域。

用户补充的局部截图还确认了一件更强的事：

5. 在某些帧里，蓝色 caret 点会直接出现在输入框外、靠近上方 label 的空白带里，而不是稳定待在输入框内部。

我抓到的代表性帧包括：

- `/tmp/prompt-frame-31-crop.png`
- `/tmp/prompt-frame-34-crop.png`
- `/tmp/prompt-frame-37-crop.png`
- `/tmp/prompt-simple-video-zissue-contact.png`

从这些帧里可以直接看到：

- 文本已经长成两到三行
- 但 field 可见区域没有稳定把最后一行完整容纳进去
- 下方的 `用户描述` 区域非常靠近，形成明显的视觉压迫带

这和用户说的“打字之后本来应该长高但是没长高到 z 轴后面去了，最后那几秒在 z 轴后面闪”是吻合的

换句话说：

**用户的 runtime 观察是对的，这不是主观错觉。**

而且最新局部截图说明：

**这不只是“看起来像在后面”，而是 caret 的可见位置本身已经和输入框内容区脱锚了。**

---

## 现状代码怎么工作的

### 1. 外层页面结构

`SettingsView.swift:436-741`

当前 iOS Prompt 页面本体是一个 `List`：

- 页面根是 `List`
- 简单模式内容放在一个 `Section`
- `Section` 里面又放了一个 `VStack`
- 5 个输入框都堆在这个 `VStack` 里

也就是说，简单模式不是一个普通 `ScrollView + VStack` 页面，而是：

**一个复杂滚动容器（`List`）里，塞了一个会动态变高的 UIKit 文本编辑器。**

这点很关键。

### 2. 当前多行输入组件

`IOSPromptTextView.swift:5-234`

当前组件做法是：

- SwiftUI 层维护 `@State private var measuredHeight`
- UIKit 容器 `PromptTextViewContainer` 在 `layoutSubviews` 和 `refreshUI()` 里测量内容高度
- 测完通过 `onHeightChange` 回传给 Coordinator
- Coordinator 再异步写回 SwiftUI 的 `measuredHeight`
- SwiftUI 再通过 `.frame(height: measuredHeight)` 改视图高度

也就是说，高度不是 SwiftUI 在同一次布局中直接问 UIKit“你想多高”，而是：

**UIKit 先布局，测完再通知 SwiftUI 改 frame。**

### 3. 当前 caret 可见性维护

核心逻辑在：

- `textViewDidChange`：`IOSPromptTextView.swift:85-89`
- `textViewDidBeginEditing`：`IOSPromptTextView.swift:91-93`
- `textViewDidChangeSelection`：`IOSPromptTextView.swift:95-98`
- `refreshUI`：`IOSPromptTextView.swift:145-150`
- `recalculateHeightIfNeeded`：`IOSPromptTextView.swift:200-221`
- `ensureCaretVisible`：`IOSPromptTextView.swift:153-165`

当前实现会：

1. 尝试滚动 `UITextView` 自己。
2. 再向上找第一个祖先 `UIScrollView`。
3. 对那个祖先 scroll view 再调用一次 `scrollRectToVisible(...)`。

也就是：

**内层滚一次，外层再滚一次。**

---

## 我看到的本地强信号问题

### 问题 1：高度回传链路是“多一拍”的

当前实现：

- `recalculateHeightIfNeeded()` 里用 `textView.sizeThatFits(...)` 算高度
- 高度变化时通过 `onHeightChange` 回调
- Coordinator 在 `DispatchQueue.main.async` 里写回 `parent.measuredHeight`

对应代码：

- 测高：`IOSPromptTextView.swift:200-217`
- 异步回写：`IOSPromptTextView.swift:100-105`

这意味着一次输入可能至少经过：

1. `UITextView` 自己内容变了。
2. UIKit 测出新高度。
3. 异步切回 SwiftUI 状态。
4. SwiftUI 重新布局。
5. `List` 再重新计算这一行高度。

这条链路本身就容易带来“黏一下”的感觉。

它不是绝对错误，但它和 Apple 给 `UIViewRepresentable` 提供的尺寸入口相比，路径更绕。

---

### 问题 2：当前实现会重复触发 caret 滚动

这是我这轮排查里最强的本地信号之一。

现在一次普通输入，可能触发：

- `textViewDidChange` 一次
- `textViewDidChangeSelection` 一次或多次
- `refreshUI(keepCaretVisible: true)` 一次
- `recalculateHeightIfNeeded()` 一次

而这里面：

- `refreshUI(keepCaretVisible: true)` 先调用 `recalculateHeightIfNeeded()`
- `recalculateHeightIfNeeded()` 末尾已经调用了 `ensureCaretVisible()`
- `refreshUI` 结束前又会因为 `keepCaretVisible == true` 再调用一次 `ensureCaretVisible()`

对应代码：

- `refreshUI`：`IOSPromptTextView.swift:145-150`
- `recalculateHeightIfNeeded`：`IOSPromptTextView.swift:220`

也就是说，**光是 `refreshUI(keepCaretVisible: true)` 这一条路径，就可能在一次刷新里滚两次。**

如果再叠上：

- `textViewDidChangeSelection`
- `textViewDidBeginEditing`

那么一两个字的输入，就可能打出很多次滚动尝试。

这非常符合“会卡”和“看起来在抢滚动”的主观感受。

---

### 问题 3：当前页面是双滚动容器

Apple 文档明确说：

- `UITextView` 是 “A scrollable, multiline text region.”
- `UITextView` 继承自 `UIScrollView`
- `List` / `Table` 自身也隐含 scroll view

来源：

- `UITextView` 文档：<https://developer.apple.com/documentation/uikit/uitextview>
- `UIScrollView` 文档：<https://developer.apple.com/documentation/uikit/uiscrollview>
- SwiftUI Scroll views 文档：<https://developer.apple.com/documentation/swiftui/scroll-views>

Apple 对 `Scroll views` 的描述里还明确写了：

- `Lists and Tables implicitly include a scroll view.`

这和当前本地实现一对照，问题就很明确了：

- 外层 `List`：一层 scroll view
- 内层 `UITextView`：一层 scroll view
- 代码还在很多时机主动驱动这两层都滚

所以这已经不是“单控件高度不准”这么简单，而是：

**两个滚动系统同时存在，而且都在被命令式滚动。**

---

### 问题 4：当前 outer scroll targeting 是“猜祖先”

`IOSPromptTextView.swift:223-232`

当前 `enclosingScrollView()` 的策略是：

- 从当前 view 一路往上找
- 碰到第一个 `UIScrollView` 就返回

这在普通 UIKit 手写层级里有时够用，但在 SwiftUI `List` 里它有两个天然风险：

1. 你找到的“第一个 scroll view”不一定就是语义上应该推动的那一层。
2. 即使找对了，那层 scroll view 也是 SwiftUI 自己管理的复杂容器。

这里我没有做运行时 view hierarchy dump，所以“第一个祖先 scroll view 是否一定就是正确目标”现在还不能百分百下结论。

但从研究角度，这已经足够说明：

**当前 caret 可见性方案不是显式地控制“应该滚哪个字段到哪”，而是在做一个层级猜测。**

这类方案天然稳定性一般。

---

### 问题 5：`scrollRectToVisible` 的语义决定了它很吃时机

Apple 对 `UIScrollView.scrollRectToVisible(_:animated:)` 的说明非常关键：

- rect 必须在 scroll view 的坐标系里
- 如果目标区域“已经可见”，这个方法就什么都不做

来源：

- <https://developer.apple.com/documentation/uikit/uiscrollview/scrollrecttovisible%28_%3Aanimated%3A%29>

这对当前问题的意义是：

如果我们在下面这些时机太早调用它：

- 外层 `List` 还没完成新高度 relayout
- 键盘相关 inset 还没稳定
- 当前 field 的实际 frame 还没落到最终位置

那么 `scrollRectToVisible` 很可能会基于旧几何信息判断“已经可见”，于是直接不滚。

之后等布局真的稳定了，caret 就已经跑出去了。

所以现在“明明有 ensureCaretVisible，但用户仍然能看到光标出区”并不奇怪。

---

### 问题 6：当前结构没有显式的“focused field scroll target”

现在简单模式这 5 个字段是堆在一个 `Section` 里的：

`SettingsView.swift:633-649`

但页面层并没有：

- per-field 的 `id`
- focused slot state
- `ScrollViewReader`
- `scrollPosition`

而 Apple 对 `ScrollPosition` / `ScrollViewReader` 的文档强调的是：

- 你可以按 view identity 去滚动
- SwiftUI 会尽量在内容尺寸变化时保持该 view 可见

来源：

- `ScrollPosition`：<https://developer.apple.com/documentation/swiftui/scrollposition>
- `ScrollViewReader`：<https://developer.apple.com/documentation/swiftui/scrollviewreader>

也就是说，如果未来要做“输入时把当前字段稳定留在键盘上方”，当前页面结构其实缺了一个很关键的前提：

**没有被明确建模的‘当前焦点字段’滚动目标。**

---

## Apple 文档给出的关键方向信号

### 信号 1：`UIViewRepresentable` 本来就有尺寸入口

Apple 给 `UIViewRepresentable` 提供了：

- `sizeThatFits(_:uiView:context:)`

官方描述是：

- 给定一个 proposed size，返回 representable 的 preferred size
- SwiftUI 会在同一次布局中从这些返回值里选择实际使用的尺寸

来源：

- <https://developer.apple.com/documentation/swiftui/uiviewrepresentable/sizethatfits%28_%3Auiview%3Acontext%3A%29>

这对当前 research 的含义很明确：

如果一个 UIKit 包装视图的高度本身就是布局核心，那优先研究的应该是：

**能不能把“首选高度”直接接回 representable 的 sizing hook，而不是再走一层 SwiftUI 本地状态回环。**

我现在不在这里写方案，只记录判断：

这条 Apple 提供的入口，比当前“异步回写 `measuredHeight`”更像对路的地方。

---

### 信号 2：Apple 明确把键盘遮挡责任交给应用层

`UITextView` 文档里写得很直白：

- 键盘可能遮住你的界面
- 某些系统视图，比如 table views，会帮你把 first responder 滚进可见区
- 但如果 first responder 靠近底部，应用仍然可能需要自己 resize 或 reposition scroll view

来源：

- <https://developer.apple.com/documentation/uikit/uitextview>

这几乎直接解释了当前现象：

- 外层是类 table/list 的滚动区域
- 键盘占掉了大量下方空间
- 当前 field 还会动态长高

只依赖“系统可能会帮我滚一点”是不够的。

---

### 问题 7：新的 runtime 线索把怀疑范围扩大到了 z-order / clipping

用户在运行时补充说明：

- “z 轴后面”

这条线索的重要性很高，因为它说明用户肉眼看到的可能不是：

- caret 单纯滑出了可视区

而是：

- caret 仍在当前几何区域附近，但被其他层盖住了

如果这个观察准确，那么当前问题至少可能包含下面这些类型：

1. `List` row / section 的可见区域在动态高度变化时没有同步更新。
2. SwiftUI 容器把 UIKit 子视图的某部分裁掉了。
3. 当前 field 的视觉背景或相邻 row 在合成顺序上压住了 caret。
4. 我们现在看到的“出区”，部分其实是“被盖住”，不是“没滚到”。
5. caret 自己的绘制位置已经短暂跑到输入框外部的空白区域。

这会改变后续验证优先级：

- 不能只盯 `scrollRectToVisible`
- 还要把 `List`、row、section、background、clip、compositing 当成一级嫌疑对象
- 还要把“UIKit 光标绘制位置和 SwiftUI 容器几何不同步”当成一级嫌疑对象

现在看完录像后，这条已经不是“可能”，而是至少可以升级为：

- **有强视频证据支持 clipping / layering 的确参与了问题表现**

录像并没有支持“单纯滚动延迟”作为唯一主因，反而更支持：

- 文本先长
- 容器后长，甚至某些时刻根本没及时长
- 最终进入了底边 clipping 区域

而新截图进一步说明：

- 某些时刻 caret 已经越过输入框可见边界，跑进上方空白带

这比“底边 clipping”更严重，因为它说明：

- 不是只有容器太短
- 还可能有坐标系 / 合成层 / 复用时机错位

---

### 信号 3：List 是复杂滚动容器，不是白纸一张

Apple 对 `List` / `Lists` 的文档描述：

- `List` 是复杂容器
- 自带 implicit scrolling behavior
- 支持大量 list-specific 的 row / section / inset / style 逻辑

来源：

- <https://developer.apple.com/documentation/swiftui/list>
- <https://developer.apple.com/documentation/swiftui/lists>

它不是“外面包了个最简单的 `UIScrollView`”。

因此当前这种做法：

- 在 `List` 里面放一个动态长高编辑器
- 再在 UIKit 层直接命令祖先 scroll view 去滚

从架构味道上就不是特别稳。

---

### 信号 4：如果要显式控滚动，Apple 给的是 ScrollView 侧的 API

Apple 给 SwiftUI 的显式滚动控制主要是：

- `ScrollViewReader`
- `ScrollPosition`
- `scrollPosition(...)`

而不是“让你去猜祖先 scroll view 然后命令式滚它”。

来源：

- <https://developer.apple.com/documentation/swiftui/scrollviewreader>
- <https://developer.apple.com/documentation/swiftui/scrollposition>
- <https://developer.apple.com/documentation/swiftui/view/scrollposition%28_%3Aanchor%3A%29>

所以如果后续要真正稳定解决“光标别出去”，更对齐 Apple 路子的方向会是：

- 让页面滚动成为显式、可控、带 identity 的行为
- 而不是在 `UIViewRepresentable` 里往上找祖先 scroll view 去推

---

## 对这次截图的解释

结合截图和现有代码，我的理解是：

1. 第一个输入框已经被撑成较大高度。
2. 键盘占据了屏幕下半部。
3. 页面上方还有导航栏、分段控件、section header。
4. 这意味着当前可用于“显示正在编辑的那一行”的垂直预算很小。

在这种情况下，如果：

- 高度变化是多拍反馈的
- 外层 `List` 和内层 `UITextView` 都在滚
- outer scroll 命令又可能基于旧布局做判断

那“看起来卡顿”和“光标还是会出区”就是非常合理的结果。

---

## 我现在的根因排序

### P0：架构层级的双滚动 + 多次命令式滚动

这是我现在认为最像主因的点。

原因：

- `List` 是 scroll view
- `UITextView` 是 scroll view
- 当前一两个输入事件就可能命中多次 `ensureCaretVisible`
- `ensureCaretVisible` 里还会同时推动内外两层滚动

这非常容易造成卡和错位。

### P0：高度不是通过 representable sizing hook 回给 SwiftUI

这不是“肯定唯一原因”，但它很像卡顿的重要放大器。

当前高度链路绕了一圈状态同步，天然比“同一布局过程直接拿 preferred size”更重。

### P1：caret 可见性的触发时机偏早，且缺少 focused field 级别的滚动模型

即使滚动逻辑是对的，如果它发生在：

- 外层 `List` 还没完成高度更新
- 键盘 inset 还没稳定

那也会出现“调用了但没真的留住 caret”的体验。

### P0：存在真实的 layering / clipping 风险，而且已被运行时录像支持

在看录像之前，这还是高优先级怀疑。

看完录像之后，它已经可以和上面两条并列到 P0。

因为现在有视频证据说明：

- 最后一行和 caret 不是单纯离开了可视内容区
- 它们像是掉进了底边后的裁切带 / 覆盖带

这意味着如果后续继续把问题只当成 scroll bug 来修，很可能方向会偏。

### P0：存在 caret 坐标脱锚 / 绘制层错位风险，而且已被局部截图直接支持

用户补充的局部截图里，蓝色 caret 点出现在输入框外、靠近上方 label 的位置。

这说明至少在某些瞬间：

- caret 不是简单“不可见”
- 而是被画在了错误的几何区域里

所以后续验证不能只问“该不该滚”，还要问：

- 当前正在闪烁的 caret 到底属于哪个 `UITextView`
- 它是不是还在旧 frame / 旧 layout 上闪
- 当前可见文本和当前焦点输入层是不是短暂分离了

### P1：caret 可见性的触发时机偏早，且缺少 focused field 级别的滚动模型

### P2：祖先 scroll view 猜测策略不够可靠

这点更像结构性风险，而不是我现在最核心的主因。

但如果后面只微调局部逻辑，不处理这一层，问题很可能还会反复。

---

## 这轮 research 的建议边界

这份文档先不进 implement，只记录建议方向。

### 我不建议继续做的事

1. 不建议继续在当前组件里追加更多“输入一次就多滚几次”的补丁。
2. 不建议继续把“卡顿”理解成单纯的动画问题。
3. 不建议只盯 `caretRect` 数学细节，而忽略外层 `List` 本身是复杂滚动容器。

### 我认为后续最值得进入 plan 的两个方向

#### 方向 A：保留当前页面结构，重做输入组件的 sizing 与 caret 策略

研究重点：

- 高度回传是否改到 `UIViewRepresentable.sizeThatFits(...)`
- caret 可见性是否改为更少、更晚、更单一时机触发
- 内外两层滚动是否要明确分工，而不是每次都两层一起推

优点：

- 改动面相对收敛

风险：

- 仍然在 `List + UITextView` 这个组合里打磨
- 可能继续被外层容器的隐式滚动行为牵制

#### 方向 B：简单模式脱离 `List`，改为显式可控的 `ScrollView` 页面段

研究重点：

- 简单模式那部分是否单独改为 `ScrollView + VStack/LazyVStack`
- 每个字段给 identity
- 用 `ScrollViewReader` / `ScrollPosition` 管焦点字段可见性

优点：

- 滚动权更清楚
- 更符合 Apple 给 SwiftUI 暴露的 programmatic scrolling 模型

风险：

- 页面层级变动比方向 A 更大
- 需要小心保持现有视觉和 section 节奏

---

## 我现在的判断

如果只问一句“为什么现在还是卡、为什么光标还是会出去”，我的答案是：

**因为现在修到的是‘能工作’，但还没修到‘滚动模型是对的’。**

当前实现已经把“保存导致整页刷新”这条错路排掉了，但剩余问题说明：

- 高度同步方式
- 内外滚动分工
- 焦点字段可见性策略

这三件事还没有被收成一个稳定模型。

---

## 这轮使用到的 Apple 文档

- `UIViewRepresentable.sizeThatFits(_:uiView:context:)`
  <https://developer.apple.com/documentation/swiftui/uiviewrepresentable/sizethatfits%28_%3Auiview%3Acontext%3A%29>

- `UITextView`
  <https://developer.apple.com/documentation/uikit/uitextview>

- `UIScrollView`
  <https://developer.apple.com/documentation/uikit/uiscrollview>

- `UIScrollView.scrollRectToVisible(_:animated:)`
  <https://developer.apple.com/documentation/uikit/uiscrollview/scrollrecttovisible%28_%3Aanimated%3A%29>

- `List`
  <https://developer.apple.com/documentation/swiftui/list>

- `Lists`
  <https://developer.apple.com/documentation/swiftui/lists>

- `Scroll views`
  <https://developer.apple.com/documentation/swiftui/scroll-views>

- `ScrollViewReader`
  <https://developer.apple.com/documentation/swiftui/scrollviewreader>

- `ScrollPosition`
  <https://developer.apple.com/documentation/swiftui/scrollposition>

- `View.scrollPosition(_:anchor:)`
  <https://developer.apple.com/documentation/swiftui/view/scrollposition%28_%3Aanchor%3A%29>

- Apple Archive: Managing Text Fields and Text Views
  <https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/ManageTextFieldTextViews/ManageTextFieldTextViews.html>

---

## 这轮不确定但值得后续验证的点

1. `enclosingScrollView()` 在当前 SwiftUI `List` 层级里，运行时拿到的到底是哪一层。
2. 现在的卡顿里，外层 `List` relayout 占比有多高，内层 `UITextView` 滚动占比有多高。
3. 如果简单模式脱离 `List`，问题是否会立刻缩小一大截。

这些已经超出纯静态阅读，需要下一轮决定是否进入有目的的验证。

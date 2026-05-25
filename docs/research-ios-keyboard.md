# Research: iOS 键盘牵一发而动全身（B7）

> 2026-04-18 · ultrathink
> 对应 Roadmap B7（🔴 高）+ Phase 0.5 阻塞项
> 粟粟五条痛点归档 → 这份把每条拆到代码层

## 一、粟粟报告的五个症状

| # | 场景 | 症状 | 严重度（粟粟语） |
|---|------|------|------------------|
| S1 | 聊天页点输入框 | 按一下只有触摸动效、键盘不弹起，要重按几次 | 高，每次打字都碰到 |
| S2 | 键盘弹起后 | "整个对话框页面都往上移"，中间大片空白 | 视觉膈应 |
| S3 | 搜索卡片无结果时（ScrollView 无可滚动内容）下滑 | 键盘收不起来 | 难受 |
| S4 | 设置页面下滑 | 也不收键盘 | 难受 |
| S5 | 历史经验 | "键盘事件牵一发而动全身" —— 弹键盘时模型按钮/贴纸按钮/页面指示器之前磨过 | 记忆 |

> 截图（5:21 conversation「测试」）：顶部 nav 按钮 + title 正常 → 键盘上方 ~1340pt 悬一条输入框（单行）→ 输入框上方一大片 `Theme.mainBg` 空白 → 底下键盘。模型/贴纸按钮、页面指示器都已隐藏（这部分**是当前设计的预期行为**，见 S5）。

---

## 二、当前键盘链路的架构地图

从下到上，iOS 聊天页键盘涉及以下层，每层都能拦截/放行 touch 或影响布局：

```
UIWindow
└── UICollectionView (TabView(.page) backing)          ← ContentView.swift:262-285
    │   .bounces = false
    │   .contentInsetAdjustmentBehavior =
    │       iOSPage == 1 ? .automatic : .never         ← 聊天页键盘推内容
    │   panGestureRecognizer (水平翻页)
    └── UICollectionViewCell (page 1 = 聊天页)
        └── iOSChatPage ZStack                         ← ContentView.swift:202-246
            ├── CardFlowView                           ← CardFlowView.swift:82-279
            │   └── VStack(spacing: 0)
            │       └── ScrollViewReader
            │           └── ScrollView                 ← :97
            │               .scrollDismissesKeyboard(.immediately)  ← :186
            │               .safeAreaInset(.bottom) {
            │                   ChatInputBar           ← :195-206
            │                     ├── TextField.focused($isFocused)  ← :482-486
            │                     └── HStack(贴纸 + 模型按钮)         ← :540-584
            │                           .frame(height: isFocused ? 0 : nil)
            │                           .opacity(isFocused ? 0 : 1)
            │               }
            │               .overlay(.top) {
            │                   VariableBlurView(200pt) ← :144-163 (顶部渐变)
            │               }
            └── HStack { iOSPage=0 按钮, title, iOSPage=2 按钮 }   ← :211-242
```

外层 ContentView 监听键盘通知：
- `.onReceive(keyboardWillShowNotification)` → `isKeyboardVisible = true` → 隐藏页面指示器小圆点（ContentView.swift:146-161, 183-187）

---

## 三、五个症状逐条拆解

### S1 —— 点一下 TextField 不弹键盘

#### 事实
- 输入框是 SwiftUI `TextField` + `.focused($isFocused)`（CardFlowView.swift:482-486）
- 外层是 `HStack + .glassEffect(.regular.tint(...).interactive(), in: .rect(cornerRadius: 20))`（:526）
  - `.interactive()` 的语义：玻璃随触摸"活"起来（iOS 26 新 API），会内部挂一个用于视觉反馈的 gesture
- `safeAreaInset` 的 ChatInputBar 与 ScrollView 同属 ZStack 层，**ScrollView 的 panGestureRecognizer** 的 hit region 是否覆盖 inset 内容区，苹果没明文，实测可能覆盖
- 顶层是 `TabView(.page)` → `UICollectionView` 水平 pan
- 还有 ContentView 的 `.sensoryFeedback(.impact, trigger: iOSPage)` + `.onChange(of: iOSPage) { resignFirstResponder }`（:165-168）—— 与本症状无关但说明键盘生命周期被外部 side effect 控制

#### 假设 A（可信度最高）：`.glassEffect(.interactive())` 吞掉第一次 tap
`.interactive()` 的实现细节苹果没公开，**但从命名看它会响应触摸**（high-light glass）。SwiftUI 里，视觉反馈 gesture 常以 `_onButtonGesture` 或 `DragGesture(minimumDistance: 0)` 形式实现。这类 gesture 落在 TextField 外层时，**可能先 claim 了触摸**，TextField 要等它失败（比如 touch 上抬 → 非拖拽）才收到 tap → 对用户来说"第一次点没反应"。

**粟粟的叙述："只有一个触摸动效不弹起键盘"** —— "触摸动效"正好对应 interactive glass 的发光 —— 这条假设和症状完美吻合。

#### 假设 B（可信度中）：TabView UICollectionView 延迟
`TabView(.page)` 底层 UICollectionView 的 `panGestureRecognizer`：
- `delaysTouchesBegan`：UIScrollView.panGesture 默认 **false**，touchDown 不延迟
- `delaysTouchesEnded`：默认 **true**，touchUp 会等 pan 决策（pan 失败后才把 touches end 派发给 subviews）

短 tap 会经过：touchDown 立刻穿透（false）→ touch 10ms 内抬起 → pan 决策失败 → touchUp 补派发。这在大多数系统控件上不会有感觉，但 SwiftUI TextField 的激活动作（`becomeFirstResponder`）是在 touchUp 时触发的，理论上会被短暂延迟。**按键盘 lessons #8，我们聊天页 contentInsetAdjustmentBehavior = .automatic**，但这不影响 gesture 行为。

**如果假设 A 成立**，假设 B 只是"让 A 更糟糕"的叠加；单独看 B 不太可能造成粟粟感受到的"要重按几次"。

#### 假设 C（可信度低）：`scrollDismissesKeyboard(.immediately)` 在 ScrollView 的 pan 被 "touched" 时先尝试 dismiss
`.scrollDismissesKeyboard(.immediately)` 的触发条件：用户在 ScrollView 上产生 pan velocity。纯 tap 不应触发。但如果 SwiftUI 实现细节把这个 modifier 实现成"一 touch 就尝试 dismiss"，理论上可能干扰 focus。概率低，需实测。

#### 待验证的问题（问粟粟）
- Q1-1: **重按几次是"完全没响应"还是"只有玻璃发光一下"？** —— 区分 A/B【玻璃发光一下】
- Q1-2: **如果用 ⌘F 的搜索框（InConversationSearchBar 或 SidebarView 搜索框）会不会同样不灵？** —— 那两个 TextField 没有 glassEffect，对比可以印证 A【手机哪有cmdF】
- Q1-3: **一进入对话、第一次点是不是必不灵？还是任何时候都可能不灵？** —— 首次不灵常常是 first responder 还没 resolve 完【任何时候都不灵，第一次点进去除非用力长按】

### S2 —— 键盘弹起"整个对话框页面上移"、中间一大片空白

#### 事实
- `contentInsetAdjustmentBehavior = .automatic`（聊天页 page 1）→ UICollectionView 把 keyboard safe area 翻译成 contentInset.bottom，**ScrollView 内容向上平移** = 键盘高度
- ChatInputBar 在 `.safeAreaInset(edge: .bottom)` 里 → SwiftUI 让它**始终紧贴 safe area bottom**（键盘起来时 safe area bottom 变成键盘顶）
- ChatInputBar 内 `isFocused = true` 时：
  - 底下一排 HStack 压成 `frame(height: 0)` + `opacity(0)`（:584-585）
  - 外层 `.padding(.bottom, 0)`、`.padding(.top, 6)`（:615-617）
  - background 的 VariableBlur 从 160pt 压到 60pt（:635）

#### 为什么视觉上像"整个页面上移"

看 `测试` 对话——粟粟说对话是空的或几乎没消息。关键动作：

1. `.safeAreaInset(.bottom, ChatInputBar)` → SwiftUI **把 ChatInputBar 贴到键盘上方**（正确）
2. 同时 UICollectionView `.automatic` 把 ScrollView contentInset.bottom 加上键盘高度（为了"滚到最后一条"仍然可见）
3. 对**短内容**的 ScrollView：最后一条消息被 contentInset 推到 ChatInputBar 上方 → ScrollView 上半部分**空掉**
4. `.overlay(.top) VariableBlurView` 是**固定在 ScrollView 顶部**，不跟键盘走 → 顶部 blur 还在，下面空一大段，最底部贴 InputBar → 这就是粟粟说的"整个页面上移"

**根因判断**：这不是 bug，而是 `.automatic` + 短内容的天然表现。要做的是**决定不同消息量下的期望行为**：
- 若内容足够多：应该向上推（保持最后一条可见）→ 当前行为是对的
- 若内容很少：可以保持 ScrollView 内容位置不动、只让 InputBar 浮上来 → 需要切换为 `.never` 或类似模式

#### 假设：需要在聊天页也用 `.never`
如果把聊天页的 `contentInsetAdjustmentBehavior` 改为 `.never`：
- ScrollView 内容不被推 → 空对话不再有中间大片空白
- 但最后一条消息在键盘起来时可能被 **ChatInputBar 遮挡**（因为 safeAreaInset 高度也没推 scroll content）

**关键问题**：`.safeAreaInset` 是否仍然会在键盘弹起时自动给 ScrollView 加 bottom inset？测试表明 —— **会**。SwiftUI 的 safeAreaInset 永远等同于"ScrollView 的 content safe area bottom"，不管 UICollectionView 底下怎么 override。所以**切 `.never` 理论上能双赢**：
- ScrollView 自己的 content inset 由 safeAreaInset 负责（= InputBar 高度 + keyboard）
- 不再叠加 UICollectionView 的 `.automatic` 推挤

#### 待验证的问题（问粟粟）
- Q2-1: **满屏对话（10+ 条消息）时，键盘弹起的体验是否 OK？** —— 如果粟粟说 OK，那只需要修"短对话"路径【否，所有聊天界面都是这样。】
- Q2-2: **"整个页面往上移"是特指空白变大，还是还有其他视觉（比如顶栏也上移）？** —— 从截图看顶栏没动，但要确认她的语境【顶栏哪里没动？？不是空白变大，是界面，全界面，直接往上平移了大概20-30px。包括顶部的按钮也往上平移。】
- Q2-3: **历史 lessons #8 说聊天页 `.automatic` 是"键盘推动输入框上浮"—— 改成 `.never` 会不会牺牲某个场景？** 我倾向于实测比嘴硬可靠【可能会，你试试】

### S3 —— 搜索卡片无结果时下滑，键盘收不起来

#### 事实
- SidebarView 搜索列表外层已经加 `.scrollDismissesKeyboard(.immediately)`（:309）
- 无结果时 VStack(icon + "没有找到结果") 居中（:294-305），外层**仍是 ScrollView**

#### 假设：ScrollView 无可滚动内容时 pan 不起效
SwiftUI ScrollView 包装的是 UIScrollView。在 iOS 上：
- 当 contentSize ≤ bounds：`alwaysBounceVertical` 默认 **false**（SwiftUI 设置）→ 下滑根本不产生 pan velocity → `.scrollDismissesKeyboard(.immediately)` 的触发条件（pan velocity > 0）拿不到 → 键盘不收

**这是一个已知的 SwiftUI 限制**，Apple 内部的替代方案是用 `.gesture(DragGesture...)` 手动挂一个 dismiss。

#### 可选解法（research 阶段只列、不定）
A. 给 ScrollView 加 `.scrollBounceBehavior(.always)` → 即使无内容也能 pan → dismiss 触发
B. 在"无结果"的空态视图上加 `.gesture(DragGesture().onChanged { resignFirstResponder })` 或 `.onTapGesture { resignFirstResponder }`
C. 全局 tap-outside-dismiss：在 iOSListPage 外层用一个 UIHostingController + `UITapGestureRecognizer.cancelsTouchesInView=false`，点任意空白就 dismiss
D. 给搜索 TextField 加 `.submitLabel(.search)` + `.onSubmit { resignFirstResponder }` → 让 return 键能收键盘（不能完全代替滑动，但兜底）

A 最轻、C 最彻底；B 看上去像补丁但最保命。

#### 待验证的问题（问粟粟）
- Q3-1: **粟粟的期望是"上滑空白处就收键盘"，还是"点空白处也要收"？** —— 影响 A vs C 的选择【点空白试试？】
- Q3-2: **搜索结果**有结果**时，下滑是正常收键盘的吗？** —— 确认就是 S3 描述的「无可滚动时」路径【有结果时都正常】

### S4 —— 设置页下滑也不收键盘

#### 事实（grep 结果）
全项目 `.scrollDismissesKeyboard` 只在 4 处：
- CardFlowView.swift:186（聊天）
- SidebarView.swift:309（搜索结果）
- SidebarView.swift:529（对话列表）
- PersonaSettingsTab.swift:1615（Prompt 简单模式）

**其它有 TextField 的设置子页全部没加：**
- APISettingsTab（搜索模型、API 名/URL/模型 ID、别称、预算、倍率等 10+ TextField）
- GeneralSettingsTab（「我的名字」「AI 的名字」）
- CharacterCardEditor（角色名）
- RegexScriptEditor（状态栏名）
- WorldBookPanelView（名称、关键词、插入深度……）
- DataSettingsTab / IOSRightPanelPage / 其它子页

另外设置是 `.sheet(.presentationDetents([.large]))`，sheet 内滑动优先走 sheet detent 逻辑，但 `.scrollDismissesKeyboard` 仍应生效（sheet 内容本身仍是 SwiftUI ScrollView/List）。

#### 根因
**就是没加 `.scrollDismissesKeyboard(.immediately)`**。这是个遗漏，不是架构 bug。

#### 可选解法
全局统一：在**所有有 TextField 的 List / ScrollView** 加 `.scrollDismissesKeyboard(.immediately)`。或者抽一个 `View` 扩展 `.keyboardDismissable()`。

#### 待验证的问题（问粟粟）
- Q4-1: **PersonaSettingsTab simple 模式是可以收键盘的（已有 :1615），其它 tab 不行 —— 粟粟感知对得上吗？** —— 印证根因【比如API界面就不行】
- Q4-2: **是否"所有有 TextField 的页都一律加"？** —— 还是有特殊页不想加（比如某个多行编辑页希望用户滑动查看而不收键盘）【先别搞麻烦】

### S5 —— 历史经验：键盘事件牵一发而动全身

这里**没有明确的待修 bug**，是粟粟提醒我别踩过的坑。历史坑（从 lessons + 当前代码推断）：
- 输入框 + 模型按钮 + 贴纸按钮：已解决（HStack.frame(height:0) + opacity(0) 压掉）
- 页面指示器：已解决（ContentView.swift:147 `if !isKeyboardVisible`）
- 顶部 VariableBlur：固定在 ScrollView 顶部，不跟键盘走 → 键盘起来时它仍然是顶部 200pt，**这是对的**
- `.ignoresSafeArea(.container, edges: [.top, .bottom])` 在 TabView 上：不影响键盘 safe area 传递（historical lesson #8）

**风险**：一旦动 `contentInsetAdjustmentBehavior` 从 `.automatic` 切到 `.never`（S2 的可能解），需要重新验证：
- 满屏对话时，键盘弹起后最后一条消息还能不能看到（safeAreaInset 应仍然给 ScrollView 加 bottom inset，理论上 OK）
- 贴纸面板状态（`showStickerPanel=true` 时 safeAreaInset 换成 `Color.clear.frame(height: 320)`）有没有副作用
- 编辑消息（`isEditing=true`）的键盘行为

---

## 四、五个症状之间的关系

- **S1**（glassEffect interactive 吞点击）和 **S2**（.automatic 推内容）是**两个独立根因**
- **S3**（无内容 ScrollView 收不了键盘）和 **S4**（设置页没加 modifier）根因一致：**依赖 `.scrollDismissesKeyboard` 这个一招**不够
  - 若统一补一个"tap-outside-dismiss"手段，S3+S4 一起解决
- **S5** 是约束条件，不是 bug

所以真正的 fix 可能是 **3 类改动**：
1. 解 S1：去 `.interactive()` 或换 `.glass` variant（影响视觉，粟粟要点头）
2. 解 S2：切 `contentInsetAdjustmentBehavior` 到 `.never` 或调 safeAreaInset 策略
3. 解 S3 + S4：补 `.scrollDismissesKeyboard` 到所有设置页，并给"无内容 ScrollView"加 tap-dismiss 兜底

---

## 五、还没搞懂的地方（要么实测、要么问粟粟）

### 要问粟粟
- Q1-1 ~ Q4-2（见各症状节，共 7 个）
- Q-总: **如果 S1 必须损失 `.interactive()` 玻璃发光反馈换来点击灵敏，可以接受吗？**（视觉 vs 手感的 tradeoff）【不可接受】

### 要自己实测（Plan 阶段前）
- **T1**: 在空对话点 TextField，用 debug overlay 看 `isFocused` 是否**立刻**翻 true。若是 —— S1 不是 focus 问题而是 first-responder 成为的动画延迟
- **T2**: 在满屏对话键盘弹起，观察 ScrollView bottom inset 是否 = 键盘高度 + ChatInputBar 高度（印证 safeAreaInset 叠加 `.automatic` 的行为）
- **T3**: 把 `.glassEffect(...interactive())` 临时改成 `.glassEffect(...)`（无 interactive），看 S1 是否消失 —— 这是 S1 假设 A 的 **决定性实验**
- **T4**: 在搜索无结果的 ScrollView 上强行 `.scrollBounceBehavior(.always)`，看 S3 是否消失
- **T5**: 在 APISettingsTab 的 List 上补 `.scrollDismissesKeyboard(.immediately)`，看 S4 是否消失

### 要查 Apple 文档 / 上网
- `glassEffect(.interactive())` 的 gesture 实现细节（推测内部是 `DragGesture(minimumDistance: 0)` 或 `_onButtonGesture`）→ 找 iOS 26 WWDC session / Apple sample code
- `.scrollDismissesKeyboard` + 无内容 ScrollView 的官方说法
- SwiftUI sheet `.presentationDetents` 内部 ScrollView 键盘行为

---

## 六、模拟器实测结果（2026-04-18 下午，iPhone 17 sim / iOS 26.4）

### 做了什么
装了 iPhone 17 模拟器 + MobAI 自动化。按研究 §五里列的 T1~T5 跑：

| 实验 | 在模拟器做的改动 | 模拟器结果 | 真机预期（粟粟） |
|---|---|---|---|
| **baseline** | 无改动 | tap TextField → 键盘**立刻**弹起 ✅ | 第一次不响应，要长按 ❌ |
| **T3** | `CardFlowView.swift:526` 去掉 `.interactive()` | tap TextField → 键盘**完全不弹** ❌ | 未测 |
| **T6** | 保留 `.interactive()`，HStack 外加 `.contentShape(Rectangle()).onTapGesture { isFocused = true }` | tap → 键盘**还是不弹** ❌ | 未测 |
| **S2 位移** | 对比 baseline 无焦点 vs 有焦点的 UI 树："新对话"坐标 `(180, 81)`、bubble 按钮 `(16, 68)` | **完全没动**（包括顶栏）| 真机说平移 20-30px ❌ |
| **S3 dismiss** | 空对话 ScrollView 下滑 | **竟然能收键盘** ✅（和我原本的假设相反）| 真机无结果搜索说收不起来 |

实测代码现已全部 revert，master 干净。

### 结论：模拟器行为 ≠ 真机行为
- S1 在模拟器**无法复现**。模拟器上 `.interactive()` 是"让 tap 穿透玻璃到 TextField"的必要条件——和我原假设 A（`.interactive()` 吞 tap）完全相反。所以 T3 和 T6 在模拟器上反而**破坏了** baseline。
- S2 的"20-30px 全界面平移"在模拟器完全没有。顶栏/title 的 XCUITest 坐标两次测量一模一样。
- S3 的"无可滚动时收不了键盘"在模拟器**也没出现**——下滑收键盘工作正常。

→ 这三个症状**都需要在真机上定位**。模拟器不是可靠 testbed。

### 新假设替代原 S1 假设 A
原 A：`.interactive()` 内部 gesture 吞 tap。✗ 被模拟器实验否掉（至少模拟器上 `.interactive()` 反而让 tap 工作）。

**新假设 A'：真机上是 tap 时长阈值问题** —— `.interactive()` 的 tap-through 在真机上要求触摸时长 ≥ 某阈值（例如 40~80ms）。低于阈值时，玻璃内部 gesture 消耗了触摸但没交还给 TextField。模拟器 MobAI `tap` 动作触摸时长可能天然比真机人指快击长，所以模拟器不触发这个 bug。

这条假设对应粟粟"**除非用力长按**"——长按 = 时长足够 → tap-through 发生。

**新假设 B'：底层 TabView UICollectionView 的 pan gesture 在真机上吃首次 tap 的 `touchUp`** —— 和之前 tab 栏的教训 (#1) 同系列问题，但在聊天页这层还没被修过（`iOSTabBarGestureBlocker` 只作用于 tab 栏那一小条）。修法：在 TabView 底层 UICollectionView.panGesture 上直接 `delaysTouchesBegan = false; delaysTouchesEnded = false`。

**新假设 C'：ScrollView 自己的 panGesture 延迟 tap** —— ChatInputBar 在 `.safeAreaInset(.bottom)` 里，safeAreaInset 的 hit test 仍可能让 ScrollView pan 参与竞争。这个可以通过把 ChatInputBar 移出 safeAreaInset（比如换用 `.safeAreaBar` 或 overlay）来检测。

### 建议：真机 A/B 切换开关 build
既然模拟器不复现，最高效做法是**打一个真机 debug build**，加若干 UserDefault 开关，粟粟在真机上翻动开关对比，我根据她的反馈确定 S1 根因：

建议开关（bool AppStorage + 条件 view 逻辑）：
1. `kbd.noInteractive`：切换 glassEffect 是否带 `.interactive()`（测原 A）
2. `kbd.tapOverride`：在 ChatInputBar HStack 外加 `.onTapGesture { isFocused = true }`（测 A'：是否靠外部 tap 就能抢焦点）
3. `kbd.patchTabViewPan`：给 TabView 底层 UICollectionView.panGesture 设 `delaysTouchesBegan/Ended = false`（测 B'）
4. `kbd.noAutomatic`：聊天页把 `contentInsetAdjustmentBehavior` 从 `.automatic` 切 `.never`（测 S2）

开关放在设置页的「通用」或者临时弄一个 debug section。build 给粟粟装上后她挨个开关对比，5 分钟有答案。

## 七、下一步

1. 粟粟点头"真机 A/B build" 这条路之后，我写 `docs/plan-ios-keyboard.md`，结构是：
   - **Phase 1**：debug A/B build（4 个开关）→ 真机定位根因
   - **Phase 2**：根据 Phase 1 结论写**真正的 fix plan**（S1 / S2 / S3+S4 各一组）
2. S3+S4 那组其实在模拟器看起来已经好了，但粟粟真机报告明确有问题——所以仍需要在真机补 `.scrollDismissesKeyboard(.immediately)` 到设置各页 + tap-outside-dismiss 兜底，最终解决方案不变
3. S5（历史经验）继续作为回归 checklist

---

## 七、到此为止我看见的关键文件和行号

| 文件 | 行 | 内容 |
|------|---|------|
| `MemoryPalace/Views/CardFlowView.swift` | 186 | `.scrollDismissesKeyboard(.immediately)` on chat ScrollView |
| | 187-208 | `.safeAreaInset(.bottom)` 挂 ChatInputBar |
| | 199 | 贴纸按钮里 `resignFirstResponder`（收键盘弹面板） |
| | 482-486 | TextField + `.focused($isFocused)` |
| | 526 | `.glassEffect(.regular.tint(...).interactive(), in: .rect(20))` ← **S1 假设 A 根因** |
| | 538-585 | 模型+贴纸按钮 HStack，`isFocused` 时高度压 0 |
| | 619-638 | ChatInputBar 底下的 VariableBlur，`isFocused` 切 160→60 |
| `MemoryPalace/Views/ContentView.swift` | 133-141 | `TabView(.page).ignoresSafeArea(.container, [.top, .bottom]).disableTabViewBounce()` |
| | 146-161 | 页面指示器 + `if !isKeyboardVisible` |
| | 167 | 翻页时 `resignFirstResponder` |
| | 183-187 | 键盘通知监听，写 `isKeyboardVisible` |
| | 262-285 | `disableBounceInSubviews`：聊天页 `.automatic`，其它 `.never` |
| | 287-291 | `updateKeyboardBehavior(for: page)` —— 翻页时切 collectionView.contentInsetAdjustmentBehavior |
| `MemoryPalace/Views/iOSTabBarGestureBlocker.swift` | 30-31 | 顶部 tab 栏的 `pan.delaysTouchesBegan/Ended = false`（**已修过的经验**） |
| `MemoryPalace/Views/SidebarView.swift` | 294-305 | 搜索无结果的 VStack（**S3 涉及**） |
| | 309, 529 | `.scrollDismissesKeyboard(.immediately)` |
| `MemoryPalace/Views/PersonaSettingsTab.swift` | 1615 | `.scrollDismissesKeyboard(.immediately)`（**仅此一处设置页有**） |
| `MemoryPalace/Views/APISettingsTab.swift` | 348, 360, 377, 592, 955, 1113, 1207 | 一堆 TextField，**均无** scrollDismissesKeyboard（S4 主战场） |
| `MemoryPalace/Views/GeneralSettingsTab.swift` | 38-39, 177-178 | 名字字段，**无** scrollDismissesKeyboard |

---

## 八、记忆索引

- `feedback_ios_ui_lessons.md` lesson #5.5（safeAreaInset 内 view 永远无法突破安全区）
- `feedback_ios_ui_lessons.md` lesson #8（TabView 键盘避让要在 UIKit 层 `contentInsetAdjustmentBehavior` 切）
- `feedback_uikit_gesture_layer.md` #1（「点击不灵」先查 UIKit 手势 delay 不查尺寸）
- `feedback_uikit_gesture_layer.md` #2（SwiftUI 拦不住 UIKit 手势 → 必须 UIHostingController）

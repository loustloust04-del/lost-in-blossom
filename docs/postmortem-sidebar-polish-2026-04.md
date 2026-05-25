# 复盘：iOS 左栏视觉收尾（2026-04）

**时间**: 2026-04-17 ~ 2026-04-18
**commits**: `0cd6c84` → `c0b8fd4`（约 20 个，横跨 tab 栏手势、搜索状态栏、搜索作用域、筛选器样式）

---

## 做了什么

从 tab 栏的 snap/震动/翻页冲突一路收尾到搜索筛选器的纯文字美术。
按阶段分：

1. **tab 栏手势系统**：Clock 式 snap、「全部」锁定、震动、滚到底不回弹、屏蔽 TabView(.page) 翻页手势、Chrome 风格反向圆角
2. **搜索交互**：
   - 搜索状态栏从 tab 下方移到底部 footer（原位置切断 tab↔列表的视觉连续性）
   - 搜索结果卡样式统一成跟普通列表同一张卡（`Theme.mainBg` + `UnevenRoundedRectangle` 动态圆角）
   - 搜索范围跟随当前 tab（收藏/回收站/tag 各自限定）
   - 空结果也用白色卡片包住（不再是裸 VStack）
3. **筛选器（AdvancedSearchPanel）美术**：
   - 所有选项去胶囊 → 纯文字，选中靠 `semibold + 主题绿`，未选中 `regular + textSecondary`
   - 分类名（时间/角色/排序/类型）和选项同一行 `HStack + .firstTextBaseline` 对齐
   - 间距 6 → 18，底部留白 8 → 18

---

## 犯的错 + 教训

### 错 1：误把「按钮卡」当成「hit area 小」

**现象**：粟粟说「按按钮卡卡的」，我第一反应是触摸感应范围不够大，给 tab 和 + 按钮都加了 `frame(minHeight: 44)`。

**粟粟的反应**：「我操我不是说让你变高！（变丑了！）我是说让按按钮灵一点」。

**真相**：UI 视觉没变（尺寸是对的），问题出在 **UIKit 手势层**。`iOSTabBarGestureBlocker` 里的 `UIPanGestureRecognizer` 默认会 `delaysTouchesBegan / delaysTouchesEnded`，导致 Button 的 tap 要等 pan 识别器决策完才响应，手感就是「按下去没反应 → 过一会儿亮」。真正的修复：

```swift
pan.cancelsTouchesInView = false     // 不拦截 Button 点击
pan.delaysTouchesBegan = false       // Button 立刻收到 touchDown
pan.delaysTouchesEnded = false       // tap 不等 pan 决策
```

**教训**：
- 「点击不灵」≠「点击区域小」。先分三种可能：视觉响应延迟（tap → highlight 的时间）、手势识别延迟（pan/tap 的 `delays*`）、命中区域太小（hit area）。哪怕只能缩小到两种也别上来就改尺寸。
- **尺寸变动是破坏性的**（会影响整体视觉平衡），应该是最后才动的手段。
- 粟粟说「灵一点」大概率是 latency 问题，不是几何问题。

### 错 2：SwiftUI 层试图拦 UIKit 层手势

**现象**：tab 栏横滑滚到边界会触发 TabView(.page) 翻页。

**我先试了**：`.simultaneousGesture(DragGesture)`、`.scrollBounceBehavior(.basedOnSize)`、`.scrollTargetBehavior(.viewAligned)`。

**为什么都不行**：SwiftUI 的 gesture 和 UIKit 的 `UIPanGestureRecognizer` 在**两套独立的识别器树**里。SwiftUI 的 `.simultaneousGesture` 根本进不了 UICollectionView pan 的依赖链。

**真解**：`UIViewControllerRepresentable` + `UIHostingController`，让 UIView 真正成为 SwiftUI 内容的 **superview**（不是 sibling！），在上面挂一个 `UIPanGestureRecognizer`，再让 UICollectionView 的 pan `require(toFail:)` 这个 blockerPan。

**教训**：
- SwiftUI 的 `.background` / `.overlay` 在 UIKit 层是 **sibling**，touch 路径不经过它们 → 挂在上面的 gesture 永远收不到事件。
- 想从 SwiftUI 下沉到 UIKit 拦 hit test，**必须**让 UIView 变成 superview。唯一方法是 `UIViewControllerRepresentable` + `UIHostingController`（`UIViewRepresentable` 不行——它的 UIView 还是 sibling）。
- 跨体系的手势冲突，`require(toFail:)` 通常比 `simultaneousRecognizer` 稳，但方向别搞反：被阻止的那个 require 阻止者 fail。

### 错 3：搜索作用域没跟着 UI 的 tab 走

**现象**：在「空 tag」或「回收站」里搜索，依然搜出全库结果。

**根因**：`SearchService` 只认 keyword + dateRange + roles，完全不知道当前用户站在哪个 tab。代码对「当前 tab」的理解只在 SidebarView 层，没传下去。

**修法**：给 `SearchFilter` 加两个字段：
```swift
var conversationIdScope: Set<String>? = nil       // nil = 不限；空 set = 短路返回空
var includeDeletedConversations: Bool = false     // 回收站 tab 才为 true
```
再把 `includeDeleted` **每条 predicate 分支**都穿进去（不是只改一条就完事）。

**教训**：
- **搜索作用域是 UI 状态，不是搜索器的默认行为**。一旦 UI 有「分区/过滤 tab」，搜索参数就必须显式接受 scope。
- SwiftData `#Predicate` 里捕获外部变量必须先 `let wantDeleted = filter.includeDeleted`，不能直接写 `filter.includeDeleted`（会报 key path 错）。
- **空 scope 必须短路**（「切到空 tag → 不搜」）。否则 `id IN []` 这种 predicate 在 SwiftData 里行为不稳定。

### 错 4：搜索卡片样式拍脑袋，没对齐普通列表

**第一版**：搜索结果用了 `opacity(0.6)` 半透明 + 四角 16pt 圆角，跟普通列表（solid `Theme.mainBg` + 跟 tab 连接的 `UnevenRoundedRectangle`）视觉两张皮。

**粟粟一句话**：「搜索列表还是不太对。应该也顶部留边，大小类似我们之前做的普通对话列表」。

**教训**：
- **同一个位置的两种状态（列表 / 搜索结果）视觉要一致**。只有内容变，容器不变。
- 复用样式 > 每次重写。`UnevenRoundedRectangle` 的 `topLeading / topTrailing` 动态圆角逻辑（看 `currentTab == .all` / `== .trash`）应该抽出来共用。

### 错 5：UI 微调时一次改太多

**出现过两次**：
- 第一次想一次性调 tab 按钮「尺寸 + 视觉反馈 + 命中区域」，粟粟看到尺寸变大就否掉整个方向。
- 第二次筛选器改版时我本来打算连带 spacing、padding、字号一起改，好在先只做了去胶囊，粟粟再分步要「加大间距」「同行」「右移 5px」。

**教训**：**UI 改动每次只改一个维度**。粟粟对视觉敏感，一次多改她会整包否掉，连带对的那部分也得回滚。「最小可测变更」原则：
- 先改最核心的一条（这次是「胶囊 → 纯文字」），build + 看截图
- 她说哪不对，再改下一个维度
- 每个 commit 只描述一件事

（这条和 `CLAUDE.md` 里的「宁可小步迭代」是同一个原则，但这次依然踩了，说明需要更强的条件反射。）

### 错 6：筛选器一开始用了「每个分类一个 VStack」

**现象**：分类名单独一行，选项单独一行，加上自定义日期又单独一行，整个面板高度很散，视觉节奏很碎。

**粟粟的指示**：「分类名和选项之间不要换行。[a] A B C / [b] ...」

**教训**：
- 「分类名 → 选项」是一个**信息单元**，不是两个层级。能放一行就放一行（`HStack + .firstTextBaseline`）。
- VStack 默认很容易产生「每个语义都要独占一行」的惯性。每次写 VStack 之前先问：**这些东西是否真的是不同层级？**

---

## 做对的

- **最终的手势方案记在文件顶部大段注释里**（`iOSTabBarGestureBlocker.swift:5-14`）。下次有人看到这段代码会知道「为什么不用 .background / .overlay」—— 未来的自己不用再走一遍坑。
- **每个 commit 只做一件事**（虽然筛选器那几步做到了，tab 栏那几步因为反复调试 commit 有点乱）。commit log 能直接当 changelog 读。
- **粟粟说「变丑了」立刻 revert**，没死磕。方向错了就退，不打补丁，是 `CLAUDE.md` 的原则。

---

## 规则沉淀

这些写到未来行为里，不是只记这一次：

1. **「按钮卡」优先查手势 delay，不先改尺寸。** 视觉尺寸是破坏性的，最后才动。
2. **想从 SwiftUI 拦 UIKit 手势，必须让 UIView 做 superview。** `UIViewControllerRepresentable + UIHostingController` 是唯一路径。`.background / .overlay` 不行。
3. **搜索 = keyword × (scope ∪ 默认全库)**。UI 一旦有分区 tab，搜索 API 必须显式接受 scope 参数。空 scope 要短路。
4. **同一容器的不同状态（正常 / 搜索 / 空）视觉要同一张卡**，只改内容。
5. **UI 改动最小可测变更**。一次一维，每个 commit 一件事。粟粟会分步反馈，别贪多。
6. **「纯文字 + 字重 + 颜色」是这个项目的美学**，不要给状态加胶囊/边框/背景色。`semibold + 主题绿` = 选中，`regular + textSecondary` = 未选中，收敛到 `filterOption` / `categoryLabel` 两个 helper。

---

## 不做

- 不再尝试 SwiftUI-only 方案拦 TabView(.page) 翻页。已证伪。
- 不再把搜索结果单独做一套样式。跟普通列表同构。
- 不在 Button 外包 `frame(minHeight: 44)` 求「更灵」。如果点击不灵，去查 UIKit delay，不是尺寸。

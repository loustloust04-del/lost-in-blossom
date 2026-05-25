# Plan: 设置 / Prompt / 简单 页面卡顿与光标出区（iOS）

日期：2026-04-16

基于：

- [docs/research-prompt-simple-ios-jank-caret-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/research-prompt-simple-ios-jank-caret-2026-04-16.md)
- [docs/research-prompt-simple-ios-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/research-prompt-simple-ios-2026-04-16.md)
- [docs/plan-prompt-simple-ios-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/plan-prompt-simple-ios-2026-04-16.md)

---

## 目标

这一轮不是再证明“输入框能长高”。

这轮的目标是把 iOS `设置 → Prompt → 简单` 收到下面这组体验：

1. 长高 / 缩回时不再明显发黏、卡顿、抢滚动。
2. 连续输入时 caret 不再经常跑出可视区。
3. 保留现在已经修好的行为：
   - 回车正常
   - 内容同步正常
   - 删除后会缩回
4. 不误伤 `iOSGeneralPage`、不顺手改 macOS。

---

## 范围

### 本轮会做

- 只处理 iOS 路径
- 只处理 `设置 → Prompt → 简单`
- 先做有目的的验证，确认卡顿和出区的主因
- 基于验证结果再决定实现落点
- 保持当前 5 个字段、中文文案、全屏入口和 preset 同步逻辑

### 本轮不做

- 不动 macOS Prompt 简单模式
- 不统一整个设置页 spacing system
- 不改 `iOSGeneralPage`
- 不重做 Prompt 页视觉风格
- 不在没有验证结论前直接继续堆 caret 补丁

---

## 关键判断

根据 research，这轮最大的风险不是某一行 UIKit API 写错，而是：

1. 现在的高度回传链路是“多一拍”的。
2. 现在的页面结构是 `List + UITextView` 双滚动容器。
3. 现在的 caret 可见性维护触发过多，而且时机不稳定。

所以本轮 plan 不能再按“哪里出问题补哪里”来做，而要先验证：

- 主因到底更偏 **尺寸回传链路**
- 还是更偏 **双滚动容器打架**
- 还是两者都有，但哪个是决定性矛盾

---

## 验证先行策略

### Step 1：先做运行时验证，不直接下手改结构

先验证 4 个具体问题：

1. `enclosingScrollView()` 在当前 `List` 层级里实际拿到的是哪一层。
2. 一次普通输入会触发多少次 `ensureCaretVisible` 相关滚动。
3. 高度变化时，是否真的发生了 `List` row relayout 抖动。
4. caret 出区发生时，是内层 `UITextView` 没滚到位，还是外层页面没有把当前 field 留在键盘上方。

这一阶段的目标不是修，而是把问题从“体感很怪”变成“知道是哪个容器在失控”。

### Step 2：验证后做路径决策

只保留两个实现方向，不继续发散：

#### 方向 A：保留 `List`，重做输入组件 sizing + scroll 策略

前提：

- 验证结果显示，外层 `List` 不是主要矛盾
- 主要问题来自当前 `UIViewRepresentable` 高度回传和重复滚动

这一路会重点考虑：

- 是否改到 `UIViewRepresentable.sizeThatFits(...)`
- 是否收敛 caret 滚动触发时机
- 是否明确内外两层滚动的分工

#### 方向 B：简单模式脱离 `List`，改为显式可控滚动容器

前提：

- 验证结果显示，`List` 本身就是主矛盾
- 只靠组件内修补很难把体验收稳

这一路会重点考虑：

- 简单模式内容是否改成 `ScrollView + VStack/LazyVStack`
- 每个 field 是否给稳定 id
- 是否用 `ScrollViewReader` / `scrollPosition` 管焦点字段可见性

### Step 3：只在验证结论明确后进入实现

这轮不要一边猜一边改。

标准是：

- 如果 Step 1 不能明确主因，就继续补验证，不进入实现
- 如果 Step 1 已经明确主因，再进入具体实现计划

---

## 我目前倾向的主路线

当前我更倾向：

**优先验证后走方向 B。**

原因不是“B 更高级”，而是：

- 研究里已经看到 `List` 是复杂隐式滚动容器
- 当前截图下键盘占位很大
- 当前问题正是“外层页面滚动”和“内层输入滚动”在抢控制权

如果验证结果支持这个判断，那继续留在 `List` 里磨，很可能只是把 bug 从一种形态换到另一种形态。

但这里我先不把 B 写成既定事实，仍然保留 A 作为备选，只等验证落锤。

---

## 具体实施顺序

1. 验证当前 `List` / `UITextView` 的运行时层级与滚动行为。
2. 验证高度变化链路是否真的是“异步回传导致卡顿”。
3. 验证 caret 出区时，失败点落在内层还是外层。
4. 根据结果，在 A / B 两条路径里只选一条。
5. 选定路径后再写 implementation plan，不直接开改。

---

## 需要的验证手段

### 本地验证

- Xcode / 模拟器运行时观察
- 受控复现同一输入动作：
  - 连续输入短句
  - 回车换行
  - 快速删字
  - 长文接近上限再继续输入

### 文档验证

- 持续对齐 Apple 文档里的：
  - `UIViewRepresentable.sizeThatFits(...)`
  - `UITextView`
  - `UIScrollView.scrollRectToVisible`
  - `List`
  - `ScrollViewReader`
  - `ScrollPosition`

### MCP 验证

当前会话里我已经检查过：

- `list_mcp_resources` 返回空
- `list_mcp_resource_templates` 返回空

所以**这次会话里没有可用的 `mobai MCP` 资源，也看不到任何已配置 MCP server。**

这意味着：

- 现在不能依赖 `mobai MCP` 来做额外诊断或 UI 验证
- 如果后面你希望我用它，需要先把对应 MCP server 接进当前会话

---

## 影响范围

### 下一轮验证会读/看

- `MemoryPalace/Views/IOSPromptTextView.swift`
- `MemoryPalace/Views/SettingsView.swift`
- iOS 模拟器里的 `设置 → Prompt → 简单`
- Apple Developer Documentation

### 明确不应受影响

- `iOSGeneralPage`
- `IOSAppearancePage`
- macOS Prompt 页面
- Prompt 的 slots / raw / assembly / request 模式

---

## 成功标准

只有同时满足下面这些，才算这轮问题真正被收住：

1. 连续输入时，长高 / 缩回不再明显卡顿。
2. 长文输入时 caret 始终保持在可视区。
3. 回车、同步、删字缩回不回退。
4. 键盘弹出后页面不会和输入框互相抢滚动。
5. 编译验证通过：
   - `xcodegen generate`
   - `xcodebuild -scheme MemoryPalace build`
   - `xcodebuild -scheme MemoryPalaceIOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build CODE_SIGNING_ALLOWED=NO`

---

## Todo

- [ ] 运行时验证 `List` / `UITextView` 的实际滚动层级
- [ ] 验证一次输入到底触发了多少次 caret 滚动相关调用
- [ ] 验证高度回传链路是否是卡顿主因
- [x] 判定主路线走 A（保留 `List`）还是 B（脱离 `List`）
- [x] 基于判定结果写 implementation plan
- [ ] 确认 `mobai MCP` 在当前会话不可用，并在需要时等待用户提供接入

---

## 状态

DON'T IMPLEMENT YET

当前处于 plan 阶段。

### 2026-04-17 验证补充

通过用户提供的运行时录像与局部截图，已经能确认下面这些事实：

1. 问题不是单纯“没滚到位”。
2. 文本继续增长时，`角色描述` 的可见高度没有同步长上去。
3. 最后一行与 caret 会被压到输入块底边附近。
4. 在更严重的瞬间，caret 甚至直接出现在输入框外、靠近上方 label 的空白带。

这组证据说明：

- 已经不是单纯的 scroll timing 问题
- 而是动态高度、容器层级、裁切区域、caret 绘制坐标一起失配

### 路线判定

基于现在的证据，主路线正式判定为：

**走 B：简单模式脱离 `List`，改为显式可控滚动容器。**

原因：

- 现有 `List + UITextView` 组合已经表现出几何/层级错位
- 继续在 `List` 里补 caret/scroll 补丁，风险很高
- 用户媒体证据已经把问题从“滚动不顺”升级成“输入层和容器层脱锚”

### 还没完全证死的点

下面这些技术细节还没有被完全 instrumentation 化验证：

- `enclosingScrollView()` 运行时到底命中了哪一层
- 一次输入究竟触发了多少次 caret 滚动尝试
- 每一拍 layout 具体先后顺序是什么

但这已经不影响路线选择，因为用户给出的媒体证据已经足够说明：

- 当前架构本身不稳
- 继续在原容器内补小修小补，收益很可能不成比例

下一步不是直接写代码，而是基于“走 B”的判定，写一份新的 implementation plan。

对应文档：

- [docs/plan-prompt-simple-ios-route-b-2026-04-16.md](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/docs/plan-prompt-simple-ios-route-b-2026-04-16.md)

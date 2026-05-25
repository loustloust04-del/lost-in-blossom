# Research: Pin 消息 + 回底按钮（E6 快速回顶/回底）

> 2026-04-20
> 对应 roadmap **E6 快速回顶/回底**（Phase 1 TestFlight 前）
> 对应讨论：学 Telegram，只做 ↓ 玻璃按钮，回顶用 Pin 消息替代

---

## 一、目标 / 问题

长对话（50+ 条）里想"跳回前面某个关键点"没办法。直接做"回顶按钮"又鸡肋——真正要的是"跳回我标记过的节点"。

抄 Telegram：**顶部 Pin Bar + 右下角 ↓ 玻璃按钮**。不做 ↑ 按钮。

**不做**：
- 独立"回顶"按钮
- Pin 消息的完整列表（TG 的 list view 页面）
- Pin 时的全员通知（我们是单人 app，不需要）
- Pin 排序拖拽

---

## 二、Telegram 的做法（源码速读）

源码在 `~/Desktop/susu-project/记忆宫殿/Telegram-iOS-master/`。

### Pin Bar（`ChatPinnedMessageTitlePanelNode.swift` 1060 行）

- **顶部吸附**：navBar 下方，一条矮 bar（~40pt）
- **布局**：左侧一条 3pt 彩色竖线（accent）+ 标题"Pinned Message"/"#N" + 内容预览；右侧可选"列表"小图标；最右 `×`
- **tap bar**（line 909）：`navigateToMessage(message.message.id, false, true, .pinnedMessage)` — 跳到当前 pin 显示的消息
- **多 pin 轮换**：跳完之后，bar 自动滚动换展示下一条 pin（UI 上有竖向滑动切换动画）
- **`×` 按钮**（line 919）：`unpinMessage(message.message.id, true, nil)` — 注意 **TG 的 X 是取消当前 pin**，不是临时隐藏。（我们会改行为，见方案）

### 回底按钮（`ChatHistoryNavigationButtons.swift` 367 行）

- **双按钮**：`downButton` + `upButton`，我们只做 down
- **显示时机**：`DirectionState(up: ButtonState?, down: ButtonState?)` — nil 表示隐藏，非 nil 淡入
- **玻璃效果**：`preferClearGlass: Bool` 字段直接匹配粟粟的 "玻璃按钮" 要求
- **未读 badge**：`unreadCount` 变化触发右上角小红点（我们**不做**，没有未读概念）
- **动画**：`animated(duration: 0.3, curve: .spring)` 显隐

---

## 三、我们的现状

### 已有基础（全部可复用）

| 基础设施 | 位置 | 用途 |
|---|---|---|
| `ScrollViewReader` + `proxy.scrollTo` | `CardFlowView.swift:96` | 跳到任意消息 |
| `viewModel.scrollToNodeId` | `CardFlowView.swift:166` + `ConversationViewModel` | 程序化滚动 hook |
| `isSearchMatch` 高亮 2 秒 | `CardFlowView.swift:1045-1055` | 跳转后边框发光（复用给 Pin 跳转） |
| `contextMenu` | `CardFlowView.swift:1059` | iOS 长按菜单，加"钉住"一行 |
| `HoverButtons` | `CardFlowView.swift:1129` | macOS hover 按钮，加 pin 按钮 |
| `MessageNode.isFavorite` | `Models/MessageNode.swift` | 字段模式参考（pin 同路） |
| `ContentCleaner.clean` | `Utils/ContentCleaner.swift` | bar 预览文字清洗 |

### 需要新建

| 文件 | 作用 | 行数估计 |
|---|---|---|
| `Views/PinnedMessageBar.swift` | 顶部 Pin bar UI + 多 pin 轮换状态机 | ~150 |
| `Views/ScrollToBottomButton.swift` | 玻璃 `↓` 按钮（`.ultraThinMaterial`） | ~60 |
| `Services/PinRotationState.swift`（或直接放 ViewModel 里） | 当前展示哪条 pin 的索引 | ~30 |

### 需要改

| 文件 | 改动 |
|---|---|
| `Models/MessageNode.swift` | 新增 `isPinned: Bool = false` + `pinnedAt: Date?` |
| `ViewModels/ConversationViewModel.swift` | 新增 `pinnedNodes: [MessageNode]`（按 pinnedAt desc）+ `togglePin(node:)` |
| `Views/CardFlowView.swift` | contextMenu 加"钉住/取消钉住"；HoverButtons 加 pin 按钮；外层套 Pin bar + 回底按钮 overlay；监听 scroll 位置判断回底按钮显隐 |
| `Services/SwiftDataMigration.swift`（或启动处）| 若采用 SwiftData schema 新字段，需迁移 |

---

## 四、方案设计

### 4.1 数据模型

**在 `MessageNode` 上加两个字段**（和 `isFavorite` 一致路径）：

```swift
var isPinned: Bool = false
var pinnedAt: Date? = nil   // 用于排序 + "从新到旧" 轮换顺序
```

默认值让 SwiftData 自动迁移（理论上无需写迁移代码，已有老数据字段为 false/nil）。

**不新建** `Pin` 表：pin 本质是节点的一个状态标记，新建表徒增复杂度。

### 4.2 Pin 入口

**iOS（长按 bubble → contextMenu）**

在 `CardFlowView.swift:1075` 收藏按钮**下方**加一项：

```swift
Button(action: onTogglePin) {
    Label(node.isPinned ? "取消钉住" : "钉住",
          systemImage: node.isPinned ? "pin.slash" : "pin")
}
```

**macOS（hover → HoverButtons）**

在 `HoverButtons` 里收藏按钮 **右边** 加一个按钮。SF Symbol 用 `pin.fill`（已 pin）/ `pin`。

**Pin 上限**：10 条 / 对话。第 11 条 pin 时弹 toast "最多钉 10 条，取消旧的才能钉新的"。不自动替换，用户说了算。

### 4.3 Pin Bar UI

**布局**（`PinnedMessageBar.swift`）：

```
┌─────────────────────────────────────────────┐
│ ▎ Pinned Message #2              [×]       │   ← 约 40pt 高
│ ▎ 节点内容前 40 字的预览...                  │
└─────────────────────────────────────────────┘
```

**细节**：
- 背景：`Theme.cardBg`（暖奶白）+ 下方 1px 分隔线
- 左侧 3pt 竖线：`Theme.accent`（浅灰薄荷）
- 行 1：小号字 "Pinned #N"（N = 当前 index / 总数，比如 "Pinned 2/3"）
- 行 2：正文前 40 字，`ContentCleaner.clean`
- 右侧 `×`：SF `xmark`，点击 = 临时隐藏 bar（**不是取消 pin**）
- 当前对话 pin 列表为空 → 不渲染 bar
- 临时隐藏状态存在 `@State` 里，切换对话 / 新 pin 时重置显示

**交互**：
- **Tap bar 主体** → 跳到当前 pin + 高亮 2 秒 + **轮换到下一条 pin**（index = (index + 1) % pinnedCount，从新到旧循环）
- **长按 bar**（iOS）/ **右键 bar**（macOS）→ 菜单 `取消钉住此条 | 取消所有钉住 | 隐藏 bar`

**轮换动画**：整个 bar 内容向上滑出 + 淡出 → 新内容向上滑入 + 淡入，`0.25s easeInOut`（TG 同款但简化，不抄 AsyncDisplayKit）。

### 4.4 回底按钮

**位置**：右下角，距右边 16pt，距底部 = 输入框顶边 + 16pt（避开输入框）

**造型**：
- 44×44pt 圆
- 背景：`.ultraThinMaterial`（粟粟说要玻璃）+ 外阴影 `radius 8 opacity 0.08`
- 图标：SF `chevron.down` 或 `arrow.down`，18pt，`.primary` 色

**显示时机**：
- 离底部 < 1 屏高：隐藏
- 离底部 ≥ 1 屏高：显示
- 显隐：`withAnimation(.spring(duration: 0.3))` 淡入 + 轻微上移 8pt 起手

**点击**：`proxy.scrollTo(lastId, anchor: .bottom)` + `withAnimation`（复用现有 logic，`CardFlowView.swift:179-180` 已经有同款代码）

**检测滚动位置**：SwiftUI 的 `ScrollView` 没有原生 offset 监听。三个选项：
- **A.** `GeometryReader` + `PreferenceKey` 计算 lastId 是否在可见范围 — 最 SwiftUI 惯用
- **B.** `ScrollViewReader` + 在每条 bubble 的 `onAppear` 记录"最后一条是否可见"—— 简单但精度一般
- **C.** 用 `UIScrollView` 桥接（`UIViewRepresentable`）—— 精准但重

**选 B**：给最后一条 bubble 打一个 `.onAppear/.onDisappear` 标记 `@State isAtBottom`，足够好。不在 scroll 中的时间窗口里用户本来也不会点按钮。

### 4.5 Pin 跳转后的高亮复用

现有 `isSearchMatch` 高亮在 `CardFlowView.swift:1045`。新增一个 `isPinJumpTarget` 走同一条边框 + 背景闪烁路径，或直接复用 `isSearchMatch`（但语义有点歪）。

**推荐**：新增 `@State highlightSource: HighlightSource { case search, pinJump, none }`，复用视觉不复用变量名。

---

## 五、边界情况

| 情况 | 行为 |
|---|---|
| Pin 的节点被软删除 | Pin 列表里该项灰色显示"已删除"；tap 不跳转，弹 toast |
| 导入的旧对话 | 也能 pin（字段都有了） |
| 分支切换后 pin 节点不在当前 path | 跳转时自动切到包含该节点的 path（或提示"该消息在另一分支，切过去？"）|
| Pin 全部取消 | Pin bar 淡出消失 |
| 对话条数很少（< 1 屏）| 回底按钮不显示（没意义） |
| 首次进入对话（默认就在底部）| 回底按钮不显示 |
| streaming 时新增消息 | `isAtBottom` 逻辑不变，用户若已在底部会跟随；离底则按钮出现 |

---

## 六、风险

| 风险 | 缓解 |
|---|---|
| SwiftData 新增字段迁移失败 | 用 Bool 默认 false + Optional Date，SwiftData 自动处理；测试时用老 db 启动 |
| Pin bar 在 iOS 顶部挡 safe area | 放在 navBar 下、chat scroll 上，不碰 safe area |
| 分支切换时 pin 节点可能不在当前 path | 最小版先不处理跨分支跳转，弹 toast 提示；P2 再做自动切 path |
| ScrollView offset 监测掉帧 | 用方案 B（onAppear）零开销，不会掉帧 |
| macOS 和 iOS 的 `.ultraThinMaterial` 观感差异大 | 分平台微调透明度；先实现再看 |
| Pin 数量膨胀（用户真钉很多）| 上限 10，简单直接 |

---

## 七、不做的事

- ❌ "回顶"按钮（用 Pin 替代）
- ❌ Pin 列表完整页面（TG 的 list view）
- ❌ 多选批量取消 pin
- ❌ Pin 的时间戳显示
- ❌ Pin 拖拽排序（始终按 pinnedAt desc）
- ❌ 搜索结果里对 pinned 节点加图标（P2 再考虑）
- ❌ 跨分支自动切换（最小版提示，不自动切）

---

## 八、验证标准

1. iOS 长按消息 → 菜单出现"钉住" → 点完消息带 pin 标记 ✅
2. macOS hover 消息 → 看到 pin 按钮 → 点完状态切换 ✅
3. Pin 完顶部 bar 出现，显示内容预览 ✅
4. Tap bar 跳到该消息 + 高亮 2 秒 ✅
5. Pin 2+ 条时 tap bar 轮换到下一条 ✅
6. Bar 上 `×` 点击临时隐藏（pin 还在，切换对话回来消失再出现）✅
7. 长按 bar / 右键 bar 菜单：取消此条 / 取消全部 / 隐藏 bar ✅
8. 聊天滚到一屏以上时右下出现玻璃 ↓，点击回底 ✅
9. 滚到底时 ↓ 按钮消失 ✅
10. 导入的旧对话 pin 功能正常 ✅
11. build 零 warning ✅

---

## 九、实施顺序（writing 给 plan 用）

1. MessageNode 字段 + ViewModel pinnedNodes（0.5h）
2. Pin 入口：contextMenu + HoverButtons（1h）
3. PinnedMessageBar.swift 静态 UI（1.5h）
4. Pin bar 轮换状态机 + tap 跳转（2h）
5. Pin bar × / 长按菜单（0.5h）
6. ScrollToBottomButton.swift（0.5h）
7. isAtBottom 检测 + 显隐联动（0.5h）
8. 跳转高亮复用（0.5h）
9. 手测 + 清日志（0.5h）

**总预估：~8 小时**（1 整天集中开发）

---

*等粟粟批注后写 plan。*

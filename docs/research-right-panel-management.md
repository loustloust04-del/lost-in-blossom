# Research: 右栏工具管理

> 日期：2026-04-15

---

## 1. 文档声称 vs 代码实际

PROJECT_ROADMAP.md 第 21 行：
```
| F 工具抽屉 | 插件注册制、选中展开 bar、长按网格、橡皮绳动画 | ✅ 新 | 可用 |
```

plan-tool-drawer.md 底部明确写了"Phase 1 不做"的三项：
- 设置页里的工具管理 UI（拖拽排序）
- 工具顺序自定义
- 工具的启用/禁用

**结论：Phase 1 的骨架做了，但管理功能一项都没做。**

---

## 2. 现有代码状态

### 2.1 数据模型 — `RightPanelPlugin.swift`

```swift
struct RightPanelTool: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var icon: String
    var isPinned: Bool = true   // 是否钉在顶栏
    var order: Int = 0          // 排列顺序（只读，没有任何代码改它）
}
```

**缺失：**
- 没有 `isEnabled` 字段 — 不能禁用工具
- `order` 只在 `builtInTools` 硬编码，没有任何 reorder 方法
- `RightPanelToolManager` 只有 `togglePin()`，没有 `move()`、`setEnabled()`

### 2.2 工具栏 — `ToolBarView`

- 显示 `pinnedTools`，选中展开文字 + spring 动画 ✅
- `onLongPressGesture` 打开抽屉 ✅
- **但 long press 在整个 toolbar 上**，不能对单个工具操作
- 单个工具没有 context menu（没有删除/移动选项）

### 2.3 抽屉 — `ToolDrawerView`

- 3 列网格展示所有工具 ✅
- 点击工具 → 切换到该工具并关闭 ✅
- pin 标记（绿色圆点）✅
- context menu 只有一项：pin/unpin ✅
- **没有** enable/disable 开关
- **没有** 拖拽排序
- **没有** 移动位置

### 2.4 右栏内容 — `MemoryPanelView.swift:panelContent`

switch 硬编码 5 个 case：calendar, memory, worldBook, cardLibrary, sticker。
不检查 isEnabled，只要 selectedToolId 匹配就渲染。

### 2.5 设置页 — 无

没有任何设置页面管理右栏工具。

---

## 3. builtInTools（5 个）

| id | name | icon | view |
|---|---|---|---|
| calendar | 日历 | calendar | CalendarPanelView |
| memory | 记忆 | brain | MemoryPanelView |
| worldBook | 世界书 | book.closed | WorldBookPanelView |
| cardLibrary | 卡库 | person.crop.rectangle.stack | CardLibraryPanelView |
| sticker | 贴纸 | star.circle | StickerLibraryView |

---

## 4. 用户需求 vs 差距

### 需求 A：toolbar 单个工具长按操作
- **要**：长按单个工具 → 从顶栏移除 / 向左移 / 向右移
- **现状**：长按整个 bar 打开抽屉，单个工具无 context menu
- **差距**：需要给每个 toolbar 按钮加 `.contextMenu`

### 需求 B：抽屉增强
- **要**：能把未 pin 的工具 pin 回来、能看到所有可用工具
- **现状**：已经能做到（点 context menu toggle pin），但交互不够直观
- **差距**：不大，可以优化

### 需求 C：enable/disable 概念
- **要**：关掉 = 这个工具从右栏彻底消失（toolbar + 抽屉都看不到）
- **现状**：完全没有这个概念
- **差距**：
  1. `RightPanelTool` 加 `isEnabled: Bool`
  2. `pinnedTools` 要过滤 `isEnabled`
  3. `ToolDrawerView` 的 `allTools` 要过滤 `isEnabled`
  4. 或者抽屉里灰显已禁用的工具（让用户知道还能开）

### 需求 D：设置页 "右栏功能管理"
- **要**：设置里列出所有工具，每个有开关。未来放插件。
- **现状**：完全没有
- **差距**：新建页面，macOS 加 tab / iOS 加导航项

### 需求 E：reorder
- **要**：toolbar 工具顺序可调
- **现状**：`order` 字段存在但没有修改入口
- **差距**：
  1. `RightPanelToolManager` 加 `moveLeft(id:)` / `moveRight(id:)`
  2. toolbar context menu 加移动选项
  3. 设置页可拖拽排序

---

## 5. 两层概念模型

```
设置页：启用/禁用 (isEnabled)
  ↓ 只有启用的工具才存在
抽屉/toolbar：pin/unpin (isPinned)
  ↓ pin 的工具才出现在顶栏
toolbar：排序 (order)
```

- 禁用的工具：设置页能看到（灰色 + 开关），抽屉和 toolbar 看不到
- 启用但未 pin：抽屉里能看到，toolbar 不显示
- 启用且 pin：toolbar 上显示

---

## 6. 改动范围

| 文件 | 改动 |
|---|---|
| `Models/RightPanelPlugin.swift` | 加 `isEnabled`、`moveLeft`/`moveRight`/`setEnabled` |
| `Views/ToolBarView.swift` | 单个工具 context menu（移除、左移、右移）；抽屉过滤 disabled |
| `Views/SettingsView.swift` | 加"右栏"设置 tab/导航项 |
| `新 IOSRightPanelPage / macOS section` | 工具列表 + 开关 |
| `Views/MemoryPanelView.swift` | panelContent 检查 isEnabled |

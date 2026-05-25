# Plan: 右栏工具抽屉 — 可扩展的插件式工具栏

> 替换现有 tab 硬编码，改为 icon-only 工具栏 + 选中展开文字 + 长按弹出抽屉
> 日期：2026-04-14

---

## 设计

### 工具栏交互

```
默认：     [📅] [🧠] [📖] [🎭]         ← 只显示图标
点击记忆：  [📅] [🧠 记忆] [📖] [🎭]    ← 选中项展开显示文字，带 spring 动画
长按工具栏：弹出工具抽屉（所有可用工具网格）
```

### 工具抽屉（长按触发）

- 半屏 sheet 或 overlay
- 网格展示所有可用工具（图标 + 名称）
- 每个工具可 pin/unpin（控制是否出现在顶部栏）
- 关闭抽屉回到正常状态

### 工具设置

- 在设置页里加"工具管理"入口
- 可调整顶部栏工具顺序（拖拽排序）
- 可隐藏/显示工具
- 远期功能，Phase 1 不做

---

## Task Checklist

### J1：RightPanelPlugin 协议 + 注册表

- [ ] 新建 `Models/RightPanelPlugin.swift`
- [ ] `struct RightPanelTool: Identifiable`
  - `id: String` — 唯一标识（"calendar", "memory", "worldBook", "cardLibrary"）
  - `name: String` — 显示名称（"日历", "记忆", "世界书", "卡库"）
  - `icon: String` — SF Symbol 名称
  - `isPinned: Bool` — 是否钉在顶部栏（默认 true）
  - `order: Int` — 排列顺序
- [ ] `RightPanelToolManager`（@Observable, UserDefaults 持久化）
  - `tools: [RightPanelTool]` — 所有已注册工具
  - `pinnedTools: [RightPanelTool]` — computed，筛选 isPinned 并按 order 排序
  - `togglePin(id:)`
  - 内置注册 4 个工具：calendar, memory, worldBook, cardLibrary
  - 以后新功能只需在这里加一行注册

### J2：工具栏 View — 选中展开动画

- [ ] 新建 `Views/ToolBarView.swift`（替代现有 tab HStack）
- [ ] 只显示 pinnedTools
- [ ] 未选中：纯图标圆形按钮
- [ ] 选中：图标 + 文字，capsule 背景，带 `.spring()` 动画展开
- [ ] 整体 HStack，居中排列
- [ ] macOS 和 iOS 共用，尺寸用 `isIOSStyle` 区分

### J3：长按弹出工具抽屉

- [ ] 工具栏整体加 `.onLongPressGesture`
- [ ] 弹出方式：iOS 用 `.sheet`（半屏），macOS 用 `.popover`
- [ ] 抽屉内容：`ToolDrawerView`
  - 网格展示所有工具（LazyVGrid 3 列）
  - 每个工具：图标 + 名称 + pin 状态
  - 点击切换 pin/unpin
  - 点击工具直接切换到该工具并关闭抽屉
- [ ] 已 pin 的工具显示 pin 标记

### J4：接入现有右栏

- [ ] 替换 `RightPanelView` 里的 tab HStack 为 `ToolBarView`
- [ ] 替换 `RightPanelTopBar`（iOS）为同一个 `ToolBarView`
- [ ] `selectedTab: RightPanelTab` 改为 `selectedToolId: String`
- [ ] `panelContent` 的 switch 改为按 id 匹配
- [ ] 确保现有 4 个面板（CalendarPanel, MemoryPanel, WorldBookPanel, CardLibraryPanel）不受影响

### J5：build 双平台 + 重启 + commit + push

---

## 不做（Phase 1）

- 设置页里的工具管理 UI（拖拽排序）
- 工具顺序自定义（先用固定顺序）
- 工具的启用/禁用（先全部可用）

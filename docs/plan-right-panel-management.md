# Plan: 右栏工具管理

> 日期：2026-04-15
> 前置：research-right-panel-management.md

---

## 概览

三块工作：
1. **数据模型** — `RightPanelTool` 加 `isEnabled`，`RightPanelToolManager` 加 reorder + enable/disable
2. **toolbar + 抽屉交互** — 单个工具 context menu（移除/左移/右移），抽屉过滤 disabled，抽屉进场动画
3. **设置页** — macOS 加"右栏"tab，iOS 加导航项，列出所有工具 + 开关

---

## Task Checklist

### P1：数据模型扩展 — `RightPanelPlugin.swift`

- [ ] `RightPanelTool` 加 `var isEnabled: Bool = true`
- [ ] `RightPanelToolManager` 加方法：
  - `setEnabled(_ id: String, _ enabled: Bool)` — 禁用时同时 unpin
  - `movePinned(_ id: String, direction: -1 或 +1)` — 交换相邻 pinned 工具的 order
- [ ] `pinnedTools` 过滤条件改为 `isEnabled && isPinned`
- [ ] 新增 computed：`enabledTools` = `tools.filter(\.isEnabled)`（抽屉用）
- [ ] `load()` 合并逻辑：旧数据没有 `isEnabled` 字段时默认 true（Codable 默认值处理）

### P2：toolbar 单工具交互 — `ToolBarView`

- [ ] 每个 pinned tool 按钮加 `.contextMenu`：
  - "从顶栏移除" → `togglePin`
  - "向左移动" → `movePinned(id, -1)`（第一个不显示）
  - "向右移动" → `movePinned(id, +1)`（最后一个不显示）
- [ ] 保留整体 `onLongPressGesture` 打开抽屉（兼容现有习惯）

### P3：抽屉改进 — `ToolDrawerView`

- [ ] 数据源从 `allTools`（全部）改为 `enabledTools`（已启用的）
- [ ] 抽屉 sheet 加进场动画（macOS 改为 `.popover` 或带 transition 的 overlay）
  - iOS：`.sheet` + `.presentationDetents([.medium])` 保持不变（系统自带滑入动画）
  - macOS：sheet 改为带 `.transition(.move(edge: .top).combined(with: .opacity))` 的 overlay，从工具栏下方滑出
- [ ] context menu 保留 pin/unpin，已经够用

### P4：设置页 — 右栏功能管理

- [ ] `SettingsView.swift`：
  - `SettingsTab` enum 加 `case rightPanel = "右栏"`（放在 sticker 和 data 之间）
  - macOS tab 内容：新 section `RightPanelSettingsSection`
  - iOS：`settingsButton` + `IOSRightPanelPage`
- [ ] macOS `RightPanelSettingsSection`（直接写在 SettingsView 或独立文件）：
  - 标题"右栏工具"
  - 每个工具一行：icon + 名称 + Toggle（绑定 isEnabled）
  - 禁用的工具行灰显
  - 底部小字"关闭的工具不会出现在右栏工具栏和抽屉中。未来可在此管理插件。"
- [ ] iOS `IOSRightPanelPage`：
  - `List + Section` 模式（同其他 iOS 设置页）
  - Section "工具管理"：每个工具一行 Toggle
  - 底部小字同上

### P5：panelContent 防护 — `MemoryPanelView.swift`

- [ ] 如果当前 `selectedToolId` 对应的工具被禁用了，自动切换到第一个 enabled + pinned 的工具
- [ ] 避免右栏显示"未知工具"

### P6：build + 验证 + commit

- [ ] macOS build 通过
- [ ] iOS build 通过
- [ ] 验证：
  - toolbar 长按单个工具出 context menu
  - context menu 移除/左移/右移正常
  - 抽屉只显示启用的工具
  - 设置页开关能禁用/启用工具
  - 禁用后 toolbar + 抽屉都看不到该工具
  - 重启 app 后状态保持
- [ ] git commit + push

---

## 不改的

- panelContent 的 switch case 不动（工具 view 注册方式不变）
- 抽屉内不做拖拽排序（用 toolbar context menu 的左移右移就够了）
- 不做插件加载机制（预留位置，等有插件再做）

---

## 文件变动预估

| 文件 | 改动类型 |
|---|---|
| `Models/RightPanelPlugin.swift` | 修改（加 isEnabled、reorder 方法） |
| `Views/ToolBarView.swift` | 修改（单工具 context menu、抽屉数据源） |
| `Views/SettingsView.swift` | 修改（加 tab/导航项） |
| `Views/MemoryPanelView.swift` | 小改（selectedToolId 防护） |
| `新建或内联` | RightPanelSettingsSection / IOSRightPanelPage |

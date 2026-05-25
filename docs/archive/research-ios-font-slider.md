# Research: iOS 字号调整滑块

## 背景
macOS 用 cmd+/- 调字号缩放，iOS 没有入口。需要在设置页加滑块。

## 现有机制

### fontScale 链路
- **存储**: `UserDefaults "fontScale"` (Double, 默认 1.0)
- **读取**: `@AppStorage("fontScale")` 在 CardFlowView、SettingsView
- **应用**: `FontManager.font(size:weight:)` 乘以 scale；MarkdownTheme 传入 scale；行距也乘 scale
- **范围**: 0.5 ~ 2.0（macOS cmd+/- 按 0.1 步进）

### macOS 快捷键
- `MemoryPalaceApp.swift:399-421`
- cmd+ 放大 0.1，cmd- 缩小 0.1，cmd0 重置 1.0
- 被 `#if os(macOS)` 包裹，iOS 不可用

### fontScale 影响范围
- `FontManager.font()` — 只被 CardFlowView 2 处使用（聊天气泡正文）
- `MarkdownTheme` — assistant 气泡 Markdown 渲染
- 行距计算 — `lineSpacing(4 * fontScale)`
- **不影响**: UI 控件字号（搜索框、按钮、标签等都是 raw `.system(size:)`）

所以 fontScale 滑块 = **调整聊天内容字号**，不影响 UI 框架字号。符合预期。

### SettingsView 插入点
- `SettingsView.swift:340-348` — 当前 macOS 显示 "当前缩放：XX%" + 快捷键提示
- 在同一位置，用 `#if os(iOS)` 替换为滑块

## 结论
改动很小：只需在 SettingsView 加一个 iOS 条件编译的滑块，绑定已有的 `@AppStorage("fontScale")`。不需要新建任何模型或改动 FontManager。

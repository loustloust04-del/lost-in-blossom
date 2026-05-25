# Research: iOS 设置页字号审计

> 2026-04-14

## 问题

设置页字号从 Mac 端搬过来，iPhone 上普遍太小。大量 9-10pt 文字在手机上几乎看不清。

## 当前字号分布

| 字号 | 出现次数 | 典型用途 |
|------|---------|---------|
| 7-8pt | ~10 | 插槽 marker 文字、内容编辑器标签 |
| 9pt | ~20 | 测试连接状态、JSON 预览、记忆 badge、拖拽手柄 |
| 10pt | ~60 | 参数值标签、按钮文字、预设管理按钮、记忆内容 |
| 11pt | ~30 | monospaced 输入框、简单模式标签、记忆说明 |
| 12pt | ~20 | section 标签、API 表单标签、确认按钮 |
| 13pt | ~10 | section header（字体/气泡标签/消息显示等）|
| 14pt | ~5 | 采样参数折叠 header、插槽名称 |
| 16pt | 2 | 设置列表行（已改过）|

## iOS HIG 推荐

| 语义 | 推荐字号 | 我们当前 |
|------|---------|---------|
| Large Title | 34pt | 无 |
| Title | 28pt | 无 |
| Body | 17pt | 10-13pt |
| Callout | 16pt | 无 |
| Subheadline | 15pt | 12-13pt |
| Footnote | 13pt | 9-10pt |
| Caption | 11pt | 7-8pt |

## 建议调整方案（只改 iOS）

用 `#if os(iOS)` 区分，不动 macOS。

| 当前 | iOS 改为 | 用途 |
|------|---------|------|
| 7-8pt | 11pt | 最小可读文字（badge、时间戳） |
| 9-10pt | 13pt | 参数值、按钮文字、状态信息 |
| 11pt | 14pt | 输入框文字、说明文字 |
| 12pt | 15pt | 表单标签、section 标签 |
| 13pt | 16pt | section header |
| 14pt | 17pt | 可折叠 header |

## 实施方式

两种选择：

### A. 逐行加 `#if os(iOS)`（准确但冗长）
每个 `.font(.system(size: X))` 都加平台判断。改 100+ 处。

### B. 定义 iOS 字号常量（推荐）
在 Theme.swift 或 SettingsView 里定义一组常量：

```swift
private enum SettingsFont {
    #if os(iOS)
    static let sectionHeader: CGFloat = 16
    static let label: CGFloat = 15
    static let body: CGFloat = 14
    static let secondary: CGFloat = 13
    static let caption: CGFloat = 11
    #else
    static let sectionHeader: CGFloat = 13
    static let label: CGFloat = 12
    static let body: CGFloat = 11
    static let secondary: CGFloat = 10
    static let caption: CGFloat = 9
    #endif
}
```

然后把所有硬编码字号替换为 `SettingsFont.body` 等。改动面大但后续维护方便。

## 风险

- 字号变大后布局可能挤压，需要调间距
- 双列布局（采样参数 HStack）可能放不下，需要改单列
- monospaced 字体放大后 API Key 等长文本可能溢出

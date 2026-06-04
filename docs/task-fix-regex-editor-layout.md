# 正则编辑器 UI 适配 — iPhone 标签被截断

## Bug

正则编辑器（编辑正则 sheet）在 iPhone 上所有标签文字左边被截掉一个字：
- "脚本名称" → 显示"本名称"
- "查找正则" → 显示"找正则"
- "替换模板" → 显示"换模板"
- "应用到" → 显示"用到"
- "用户消息" → 显示"户消息"
- "执行时机" → 显示"行时机"
- "渲染时" → 显示"染时"

截图时间 07:30，iPhone 屏幕。

## 根因

`RegexScriptEditor.swift` 第 118 行：

```swift
.frame(width: 460, height: 520)
```

硬编码 460pt 宽度。iPhone 屏幕宽度：393pt（标准）/ 430pt（Pro Max）。
460 > 430，视图超出屏幕，左侧内容被裁切。

## 修复

去掉固定 width，改为自适应：

```swift
// 方案 A：去掉 width，只保留高度约束
.frame(maxWidth: .infinity, minHeight: 480)

// 方案 B：如果需要在 iPad 上限制最大宽度
.frame(maxWidth: 500, minHeight: 480)
.frame(maxWidth: .infinity)  // 在比 500 窄的屏幕上自适应
```

高度也可以从 520 改成 minHeight，让内容决定高度。

## 文件

`MemoryPalace/Views/RegexScriptEditor.swift`，第 118 行

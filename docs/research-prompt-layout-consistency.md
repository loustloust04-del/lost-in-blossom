# Research: Prompt 简单/插槽页面布局一致性

> 日期：2026-04-16

---

## 问题

简单模式和插槽模式切换时，顶部（预设 + 模式选择器）视觉跳变：圆角、间距、文字位置全都不一样。

## 根本原因

两种模式用了**完全不同的布局系统**：

| | 简单模式 | 插槽模式 |
|---|---|---|
| 容器 | `ScrollView` + `VStack` | `List(.insetGrouped)` |
| 卡片 | 手动 `iOSPromptCard`（RoundedRect 背景） | 系统 Section（自动圆角背景） |
| 圆角 | 手写 10pt | 系统管理（~10pt 但有微妙差异） |
| 水平间距 | 手写 padding 20 | 系统 listRowInsets |
| section 标题 | 在卡片内部 `.padding(16)` | 在卡片外部（系统 section header 位置） |
| 行内 padding | 卡片统一 padding 16 | 每行独立 listRowInsets |

**手动卡片永远无法精确匹配系统 List 的内部 metrics**，因为 Apple 的 insetGrouped 间距会随 iOS 版本微调。调数字只是近似，不是一致。

## 三个方案

### A: 简单模式也改用 List（推荐）

把简单模式也放进 `List(.insetGrouped)` 里：
- 预设 section → 和插槽模式完全相同
- 模式选择器 section → 完全相同
- 五个字段 → 放在一个 Section 里，每个字段是一个 List row

**优点**：
- 两种模式共享同一个 List，只是 section 内容不同
- 圆角、间距、标题位置 100% 一致
- 不用维护 `iOSPromptCard`

**风险**：
- `IOSPromptTextView`（UIViewRepresentable）在 List row 里的行为
- 需要测试 `sizeThatFits` 在 List 里是否正常工作
- ScrollViewReader 改为在 List 上使用

**风险缓解**：
- `IOSPromptTextView` 已实现 `sizeThatFits`，List row 会尊重这个返回值
- `.scrollDismissesKeyboard` 在 List 上也有效
- List 内嵌 ScrollViewReader 是支持的

### B: 插槽模式也改用 ScrollView + 卡片

把插槽模式从 List 迁出来，用和简单模式一样的 ScrollView + 手动卡片。

**缺点**：丢掉 List 的 swipe actions（删除插槽）、onMove（拖拽排序）、系统样式。工作量大，方向不对。

### C: 共享顶部，底部分开

把预设 + 模式选择器提到 List/ScrollView 外面，作为固定顶部。

```
VStack {
    SharedTopBar(预设 + picker)  ← 只写一次
    if simple { ScrollView { ... } }
    else { List { ... } }
}
```

**缺点**：
- 顶部不随内容滚动（或需要特殊处理让它随着滚动）
- 插槽模式的 List 失去前两个 section 的系统样式
- 固定顶部 + List 的组合在 iOS 上有奇怪的 safe area 问题

## 结论

**方案 A 最干净**。把 `iOSPromptSimplePage` 从 ScrollView 改成 List，共享预设 + picker section 代码，只有第三个 section 的内容不同。`iOSPromptCard` 可以废弃。

关键改动：
1. `iOSPromptPageContent` 不再分两个完整页面，而是一个 List，section 内容按模式切换
2. 简单模式的字段放在 List row 里，用 `.listRowInsets` 控制 padding
3. `IOSPromptTextView` 在 List row 里用 `sizeThatFits` 自适应高度
4. 删除 `iOSPromptCard`

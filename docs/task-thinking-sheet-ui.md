# 任务：思考链 Sheet UI 改版（对齐 Claude 风格）

读 CLAUDE.md。不引入 regression。只改 UI 外观，不改交互逻辑（拉上拉下的行为保持不变）。

## 当前样式
- 标题 "Thought process" 左对齐
- 关闭按钮（X 圆形）在右上角
- 整体比较简陋

## 目标样式（参考 Claude iOS App）
- 标题 "Thought process" **居中**，加粗，字号略大
- 关闭按钮（X）移到**左上角**，用简洁的 X 图标（不需要圆形背景）
- 顶部布局：`HStack { X按钮, Spacer, 标题, Spacer, 等宽占位 }`（让标题视觉居中）
- 内容区域的 padding 和间距跟 Claude 对齐——上下左右 20pt padding
- 文字样式保持当前的即可，不需要改字体

## 找到文件

思考链 Sheet 的 View 应该在 `CardFlowView.swift` 或者附近的组件里。搜索 "Thought process" 或 "思考" 或 "thinking" 相关的 Sheet/弹窗视图。

## 改动范围

只改 header 区域的布局：
1. 标题从左对齐改为居中
2. 关闭按钮从右上角移到左上角
3. 用 SF Symbol `xmark`，font size 16，foregroundStyle(.secondary)
4. 保持 presentationDetents 和 presentationDragIndicator 不变

---

一个 commit：`ui: thinking sheet header — title centered, close button left (Claude style)`

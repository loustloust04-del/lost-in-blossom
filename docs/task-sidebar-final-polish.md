# 任务：侧边栏最终收尾 — 三项修复

一个分支，做完再 push，不要一个个来。

---

## Task 1: New Chat 按钮固定在侧边栏底部

**问题**：New Chat 按钮现在跟在对话列表尾部，需要滚到底才能看到。应该始终固定在侧边栏底部可见。

**修复**：

把 New Chat 按钮从 ScrollView 内部移出来，用 VStack + Spacer 或 ZStack overlay 的方式固定在侧边栏底部。

参考 Claude App 的布局：
- 按钮始终在侧边栏最底部可见，不随列表滚动
- 居中，宽度保持当前的 50%
- 底部留 24pt 的 padding（在 safe area 之上）
- 按钮和最后一个可见的对话条目之间有自然的间距

在 `SidebarView.swift` 中，找到 `// ── New Chat 胶囊按钮` 那段代码，把它从当前的 ScrollView/VStack 中移出来，放到外层 VStack 或 ZStack 的底部。

---

## Task 2: 消息文本可选中复制

**问题**：之前的 commit `fix(ui): enable text selection on message bubbles` 没有生效。用户无法长按或双击选中助手/用户的消息文本进行复制。

**修复**：

在 `CardFlowView.swift` 中找到消息气泡的 Text 组件，确保：
1. Text 使用 `.textSelection(.enabled)` 修饰符（iOS 15+）
2. 如果消息气泡外层有 Button 或 onTapGesture，可能会拦截长按手势——需要确保 textSelection 的手势优先级高于外层的点击手势
3. 同时检查用户消息和助手消息两种气泡

测试：长按消息文本应该弹出系统的选中光标和复制菜单。

---

## Task 3: 震动反馈校准

**最终方案**（用户实机对比 ChatGPT 和 Claude 后确认）：

| 事件 | 反馈类型 |
|------|----------|
| 思考脉搏（AI 思考中的持续脉冲）| UISelectionFeedbackGenerator `.selectionChanged` |
| 思考开始 | UINotificationFeedbackGenerator `.success` |
| 思考结束 / 回复完成 | UINotificationFeedbackGenerator `.warning` |

在 `CardFlowView.swift` 或相关的 ViewModel 中，找到触发震动的代码，按上面的表格修改。

**注意**：
- 思考脉搏应该在 AI 思考期间每隔 ~1.5 秒触发一次 selectionChanged
- 不要在每个 streaming token 都触发——只在思考状态变化和固定间隔触发
- 发送消息的震动保持不变

---

三个任务做完，一个 commit：`fix(sidebar): pin New Chat button + enable text selection + calibrate haptics`

读 CLAUDE.md 里的"猫的蠢事大全"。不要再犯。

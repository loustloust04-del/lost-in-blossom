# 任务：剩余修复与打磨

## Task 1: 消息文本可选中复制

在聊天气泡的文本视图上加 `.textSelection(.enabled)`。

找到 CardFlowView.swift 中渲染助手消息文本的 View（可能是 Text 或 MarkdownUI 组件），加上这个 modifier。用户应该能长按消息文本来选择和复制。

## Task 2: 震动反馈校准

找到思考状态相关的震动反馈代码（HapticManager 或类似的工具类），校准三个触发点：

- **思考脉搏**（AI正在思考时的持续反馈）：使用 `.selectionChanged`
- **思考开始**：使用 `.success`（notification feedback）
- **思考结束**：使用 `.warning`（notification feedback）

如果当前代码用了其他类型（如 `.soft`、`.medium`），替换为上述指定类型。

## Task 3: scroll-to-bottom 优化

1. 确保 `scrollToLastMessage` 使用平滑动画：`withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(...) }`
2. AI streaming 时的自动滚动：如果每个 token 都触发 scrollTo，加节流（throttle）——最多每 0.3 秒滚动一次，避免帧卡顿
3. `isAtBottom` 的判断阈值检查——确保用户往上滑了一小段距离后按钮就出现，不要等滑很远才出现

## Task 4: 标签删除修复

当前侧边栏中的标签列表（猫上一轮添加的 List + ForEach + swipeActions 区域）存在两个问题：

### 4a: swipe-to-delete 不工作
检查 `.swipeActions` 是否正确绑定了 `deleteTag(id:)` 方法。确保：
- `deleteTag` 被调用时真的从数据库/数组中移除了标签
- 列表在删除后刷新（标签从UI上消失）
- 如果 List 的 `.listStyle` 导致 swipeActions 不生效，换一种 listStyle 或改用 `onDelete`

### 4b: 选中标签后无法取消
当用户点击一个已选中的标签时，应该取消选中（回到"全部对话"视图）。检查 `selectTab(.tag(id:))` 的逻辑——如果当前已经选中了这个 tag，再次点击应该切换回 `selectTab(.all)` 或类似的默认状态。

---

四个 task 一个 commit：`fix: text selection, haptic calibration, scroll-to-bottom, tag delete`

读 CLAUDE.md。不要引入新的 regression。

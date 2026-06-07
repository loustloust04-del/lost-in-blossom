# 第四批修复任务 — CC 执行

> 日期：2026-06-07
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`

---

## Task 1: CC 切换模型后思考链 UI 残留

**症状**: 选择 CC Bridge 后切换成别的模型（如 Claude via OpenRouter），CC 的思考链 UI（CCThinkingView）仍然显示在消息上方，正常的 thinking 折叠面板出现在它下面，形成重复
**查找路径**:
- `MemoryPalace/Views/CardFlowView.swift` — 搜索 `CCThinkingView`
- 检查 CCThinkingView 的显示条件：是不是只看了 `isLastAssistant` 没检查当前 provider 类型？
- 应该加 provider type 检查：只有当前 provider == .ccBridge 时才显示 CCThinkingView
**commit**: `fix(cc): hide CCThinkingView when provider is not CC Bridge`

---

## Task 2: 群聊长按删除

**症状**: 群聊列表里没有长按删除功能，创建了群聊后无法删除
**查找路径**:
- `MemoryPalace/Views/ChatroomListView.swift` — 群聊列表 View
- 参考 SidebarView.swift 里对话列表的长按删除实现（搜索 `.contextMenu` 或 `.swipeActions`）
- 需要调用 `ChatroomService.deleteChatroom(id:)` 或类似方法
**修复方向**: 给群聊列表项加 `.swipeActions` 或 `.contextMenu` 带删除按钮
**commit**: `feat(chatroom): add swipe-to-delete for chatroom list items`

---

## Task 3: 群聊退出按钮不灵敏

**症状**: 群聊界面里的退出按钮点击反馈不好，有时需要多次点击
**查找路径**:
- `MemoryPalace/Views/ChatroomView.swift` — 搜索退出/离开/关闭按钮
- 检查按钮的 hit area 是否太小（至少 44x44pt）
- 检查按钮 action 是否有异步操作阻塞了 UI
**commit**: `fix(chatroom): improve exit button responsiveness`

---

## Task 4: 群聊模型列表不刷新

**症状**: 群聊创建页面的模型列表没有更新，之前的动态模型获取没生效
**查找路径**:
- `MemoryPalace/Views/CreateChatroomView.swift` — 搜索 `fetchModels` 或 `availableModels`
- `MemoryPalace/Services/ChatroomService.swift` — 搜索 `fetchModels` 或 `/v1/models`
- 确认 fetchModels 是否在 View 出现时被调用（`.task` 或 `.onAppear`）
- 确认 Gateway 的 `/v1/models` 端点是否返回了最新模型列表
**commit**: `fix(chatroom): refresh model list on create sheet appear`

---

## 规则

- 每个 Task 完成后单独 commit + push
- commit message 格式：fix(模块): 简述
- 改完先 grep 确认没有语法错误再 commit
- 卡住超过 30 分钟跳下一个，在本文件标注原因

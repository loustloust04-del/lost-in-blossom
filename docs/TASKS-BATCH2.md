# 第二批修复任务 — CC 执行

> 日期：2026-06-06
> 前置：先 `git pull origin main` 拿最新代码

---

## Task 1: 开屏自定义主题背景不载入

**症状**: 用自定义主题时，直接点击"开始对话"，背景颜色白屏闪一下再载入
**根因推测**: ContentView 首帧渲染时 AppTheme/Theme 的颜色还没从 UserDefaults 加载完
**查找路径**:
- `MemoryPalace/Models/AppTheme.swift` — 主题初始化逻辑
- `MemoryPalace/Views/ContentView.swift` — onAppear / task 里的主题加载
- 关键词搜索：`backgroundColor`、`Theme.mainBg`、`customTheme`、`onAppear`
**修复方向**: 确保 Theme 的颜色在第一帧渲染前就已加载（init 或 .task 优先于 .onAppear）
**commit**: `fix(theme): load custom theme colors before first frame render`

---

## Task 2: 群聊模型不动态显示

**症状**: 绑定预设后，群聊创建页面的模型选择器不跟着 Preset 的 model 字段变化
**查找路径**:
- `MemoryPalace/Views/ChatroomListView.swift` — 群聊创建 Sheet
- `MemoryPalace/Views/ChatroomView.swift`
- 搜索：`ai_a_model`、`ai_b_model`、`Picker`、`preset`
**修复方向**: Preset 选择变化时，同步更新 model 字段的绑定值
**commit**: `fix(chatroom): sync model picker with preset selection`

---

## Task 3: CC 思考链只显示当前轮

**症状**: CCThinkingView 只显示最新一条 thinking，上一轮对话的 thinking 不显示
**查找路径**:
- `MemoryPalace/Services/CCBridgeWebSocketClient.swift` — `thinkingBlocks` 字典
- `MemoryPalace/Views/CCThinkingView.swift` — 显示逻辑
- 搜索：`thinkingBlocks`、`latestThinking`、`CCThinkingBlock`
**修复方向**: 检查 thinkingBlocks 是否在新任务开始时被清空了。如果是，改为追加而不是清空，或者按 session 分组保留历史
**commit**: `fix(cc): preserve thinking blocks across conversation turns`

---

## Task 4: 搜索内容慢/搜不到

**症状**: 搜索标题和标签正常，搜索消息内容很慢（几秒到十几秒）或搜不到
**查找路径**:
- `MemoryPalace/Services/SearchService.swift` — 全文搜索逻辑
- 搜索：`searchContent`、`LIKE`、`fullText`、`NSPredicate`、`FetchDescriptor`
**排查步骤**:
1. 确认搜索是否在主线程跑（应该在后台线程）
2. 确认 SwiftData 查询是否用了 LIKE '%xxx%'（全表扫描，很慢）
3. 如果是全表扫描，考虑加 `#Index` 或改用 `contains` 优化
**commit**: `fix(search): optimize message content search performance`

---

## Task 5: HealthKit 注入 UI 未显示

**症状**: HealthKit 授权成功，但注入的健康数据没在聊天 UI 上显示
**前置**: 读 `docs/` 目录下猫之前写的 HealthKit 任务文档
**查找路径**:
- 搜索：`HealthKit`、`healthData`、`injectHealth`、`HKHealthStore`
- 检查注入逻辑是否在 system prompt 或消息前缀里
**修复方向**: 确认 HealthKit 数据注入到了 system prompt / 消息内容里，并在 UI 上有指示
**commit**: `fix(healthkit): display injected health data in chat UI`

---

## 规则

- 每个 Task 完成后单独 commit + push
- 改完先 grep 确认没有语法错误
- 如果某个 Task 卡住超过 30 分钟，跳到下一个，在本文件对应 Task 下标注卡住原因
- 不要动第三批（重活）的任务

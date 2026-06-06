# 第三批调查任务 — CC 侦察，不动手

> 日期：2026-06-06
> ⚠️ 这批任务只做调查，不改代码，不 commit。把调查结果写回本文件对应位置。

---

## Recon 1: 聊天流式输出白屏 + 弹跳 + 对话间距突增

**症状**:
- 流式输出时向上滑动会出现白屏
- 向上滑会反复弹跳到最底端
- 对话过程中对话之间的间距会突然增大

**调查方向**:
1. 找到聊天列表的 ScrollView / LazyVStack 实现位置（CardFlowView.swift）
2. 记录 ScrollView 的 scrollTo 逻辑 — 是否在每个 token 到达时都强制滚到底部？
3. MessageContentWebView 的 dynamicHeight 变化频率 — 是否每次高度变化都触发 ScrollView 重新布局？
4. 间距突增可能是 WebView 高度突然从 0 跳到实际值，或 spacing 在某个条件下翻倍
5. 列出所有涉及 `scrollTo`、`ScrollViewReader`、`onChange(of: dynamicHeight)` 的代码位置和行号

**输出**: 在下方写调查结果
```
调查人: CC  日期: 2026-06-06  (只读调查，未改代码)

文件: MemoryPalace/Views/CardFlowView.swift

【列表结构】
- L152  ScrollViewReader { proxy in
- L153  ScrollView { ... }
- L161  LazyVStack(spacing: bubbleSpacing)   ← 间距来自 AppStorage
- L162  ForEach(viewModel.currentPath, id: \.id) { ... .id(node.id) }
- L174-177 底部哨兵 Color.clear.frame(height:1).id("__bottom_sentinel__")

【scrollTo / 触发点】
- L112-126 scrollToLastMessage(proxy:)  三段式回底：
    L115 proxy.scrollTo(lastId, anchor:.bottom) 立即
    L119 0.05s 后 scrollTo("__bottom_sentinel__") 带 .easeOut(0.25) 动画
    L124 0.5s 后再 scrollTo("__bottom_sentinel__") 无动画
- L235 onChange(of: viewModel.isLoading) → scrollToLastMessage（载入时）
- L247/L250 onChange(of: scrollToNodeId) → scrollTo(nodeId, anchor:.center)
- L256-271 onChange(of: viewModel.streamingText)  ← 流式核心：
    L257-259 流式结束(newText 空) → scrollToLastMessage
    L264 节流 guard: 距上次 >= 0.3s 才滚
    L265 lastStreamingScrollTime = now
    L268 proxy.scrollTo(lastId, anchor:.bottom) 带 .easeOut(0.25) 动画
- L290 手动回底按钮 → scrollToLastMessage

【弹跳根因】
L256-271 的流式 onChange 每 0.3s 强制 scrollTo(底部)，且**没有判断用户是否正在
手动上滑**（没有 isAtBottom / 用户交互 gate）。用户上滑时下一个 token(>0.3s) 到达
就被拽回底部 → 反复弹跳。L35 有 isAtBottom 但只读用于检测，没用来拦截流式回底。

【WebView 高度 / 白屏 / 间距突增】
文件: MemoryPalace/Views/MessageContentWebView.swift
- L7  @Binding var dynamicHeight: CGFloat
- L59-66 heightChanged 回调：每次 HTML 渲染 + 每次图片 load 都回传 scrollHeight
  （NSNumber→CGFloat，>0 才写）
- HTML 端 message-renderer.html notifyHeight() + MutationObserver：任意 DOM 变化都通知高度
CardFlowView 侧：
- L1283 @State messageWebViewHeight: CGFloat = 44   ← 默认 44pt
- L1502 dynamicHeight: $messageWebViewHeight
- L1504 .frame(height: messageWebViewHeight)        ← 高度直接驱动 frame

间距突增机制：assistant 气泡用 WebView，高度从默认 44pt 跳到真实值（流式时分段
44→N→M 增长）。每次 messageWebViewHeight 变化 → L1504 frame 变 → LazyVStack
(L161, spacing=bubbleSpacing 默认 31) 重新布局。视觉上相邻气泡间距随高度跳变忽大忽小，
看起来像“间距突然增大”。本质是 WebView 高度阶跃 + frame 重排，不是 spacing 翻倍。

白屏：上滑时 LazyVStack 回收/重测量 cell，与流式高度变化 + L268 带动画 scrollTo
同帧竞争，SwiftUI 丢失内容高度测量，未测量区域先露出 → 白屏。

【结论 / 三症状对应】
- 弹跳: L256-271 流式每 0.3s 无条件回底，未拦截用户上滑（缺 isAtBottom gate）
- 白屏: L268 动画 scrollTo 与 WebView 高度变化(L1504)同帧，LazyVStack 测量竞争
- 间距突增: WebView 高度 44→真实值阶跃(L1283/L1504) 驱动 LazyVStack(L161) 重排
```

**症状**: CC 的流式输出根本不工作

**调查方向**:
1. CC 流式走的是 WebSocket 还是 SSE？找到 CCBridgeWebSocketClient.swift 里的消息处理逻辑
2. 服务端（cc-bridge/）的流式输出格式是什么？对比 App 端的解析逻辑
3. 检查 WebSocket 连接状态 — 是否连接成功但消息格式不匹配？
4. 在 VPS 上运行 `tail -50 /tmp/chatroom.log` 和 cc-bridge 的日志，看有没有报错
5. 对比能工作的场景（如果有）和不能工作的场景

**输出**: 在下方写调查结果
```
调查人: CC  日期: 2026-06-06  (只读调查)

【传输方式】CC 流式走 WebSocket（不是 SSE）。
App: URLSessionWebSocketTask；hub: ws 库，MP 客户端连 /cc。
（chatroom/server.ts 的 SSE 是群聊那条独立管线，与 CC 流式无关。）

【App 端消息处理】MemoryPalace/Services/CCBridgeWebSocketClient.swift
- L236 func handleIncoming(_ text:)  switch obj["type"]：
    reply(L242) / ack / error / spawn_cc_ok / spawn_cc_err(L280) /
    cc_thinking(L289) / cc_stream(L304) / cc_stream_end(L315) / list_sessions_result(L320)
- cc_stream 解析(L305): 读 obj["content"]；L308-312 若 !isCCStreaming 先清空 streamContent，
  再 streamContent += content，isCCStreaming = true
- cc_stream_end(L315-318): isCCStreaming=false，不清空 streamContent
- 观察属性: L38 streamContent / L40 isCCStreaming

【后端生产】cc-bridge/hub.ts
- L6  TMUX_SESSION = process.env.MP_CC_TMUX_SESSION ?? "mp-cc"
- L145 captureTimer setInterval(500ms)
- L146 mpClients.size === 0 → return（无客户端不轮询）
- L149 gate: if (tmux.hasSession(TMUX_SESSION))  ← 必须存在名为 mp-cc 的 tmux session
- L151-152 tmux capture-pane -t mp-cc -p -S -50
- L160 if(newContent.trim()) 才发
- L161-166 广播 { type:"cc_stream", content:newContent, timestamp }
- L172-180 连续 3s(IDLE_THRESHOLD_MS) 无变化 → { type:"cc_stream_end" }

【字段对比】后端发 content，App 读 obj["content"] → 字段名一致，无 mismatch。

【根因（关键）】
1. ❌ 没有任何 View 消费 streamContent / isCCStreaming。
   grep MemoryPalace/Views/ 对二者 0 命中（只在 client 内被赋值）。
   对比 thinkingBlocks/latestThinking 在 CardFlowView 有渲染。
   → 即使 cc_stream 正常到达并写入 observable，UI 也永远不显示 → 用户看到的“完全失败”。
2. 生产端三重 gate，任一不满足就一条都不发：
   - L146 必须有 MP 客户端连在 /cc
   - L149 必须存在 tmux session（名字默认 mp-cc，可被 MP_CC_TMUX_SESSION 覆盖）。
     若实际 CC 跑在别的 session 名 → hasSession 为 false → 永不推送。
   - L160 delta 去 ANSI 后非空白才发。
3. L172 空闲 3s 即 cc_stream_end；CC 输出慢会被误判停止。

【VPS 日志佐证】
- /tmp/chatroom.log：群聊编排器在 3300，正常 listening（与 CC 流式无关）。
- pm2：只有 mcp-bridge 在线（hub）；out.log 正常 supergateway ready，无 cc_stream 相关报错
  → 说明 hub 没在推 cc_stream（多半是无 tmux mp-cc session 或无 /cc 客户端）。

【最可能结论】两层都断：①前端没有任何 UI 渲染 streamContent（数据黑洞）；
②后端 cc_stream 受 tmux session 名/客户端连接 gate，平时根本不产出。
先补 UI 消费 + 确认 tmux session 名，才能验证链路。
```

**症状**: API 设置页面的显示逻辑有问题，可能代码已耦合需要重写

**调查方向**:
1. `MemoryPalace/Views/APISettingsTab.swift` 的完整结构 — 列出所有主要 section 和它们的行号范围
2. 哪些 provider 类型共享了不该共享的 UI 逻辑？（比如 OpenAI 和 Anthropic 和 CC Bridge）
3. 哪些状态变量是全局的但应该是 per-provider 的？
4. 文件总行数，哪些 section 可以拆分成独立 View

**输出**: 在下方写调查结果
```
调查人: CC  日期: 2026-06-06  (只读调查)

文件: MemoryPalace/Views/APISettingsTab.swift  总行数 1218

【主要 section / 行号范围】
- L1-8    import + @Environment(ProviderManager)
- L10-33  @State / @AppStorage 声明
- L35-38  自定义 provider id 常量
- L40-75  计算属性 (isCustomSelection / selectedProvider / effectiveProviderId 等)
- L84-140 macOS body（保留但实际走 iOS）
- L150-225 iOS body（主 List 布局）
- L235-264 当前生效 API Picker
- L266-294 已保存 API 列表 (savedAPIRow)
- L310-330 provider 选择 Picker
- L332-383 自定义字段 (name / baseURL / 手动 model id)
- L385-415 API Key 区（SecureField 或 CC Bridge 状态分叉）
- L418-452 CC Bridge 连接状态面板（type 专属）
- L454-517 连接测试行（测试/删除按钮 + 结果）
- L519-564 模型列表 header（fetch 按钮 / 错误 / 搜索）
- L567-570 预算 section（委托 BudgetSection）
- L572-594 iCloud Keychain 同步
- L598-666 模型搜索 + 列表 + 分组/行
- L668-750 按厂商分组 + 单条 model 行
- L764-959 actions (loadAPIKeys / fetchModels / testConnection / saveCustomProvider 等)
- L964-1086 SavedAPIRow（独立 struct）
- L1092-1218 BudgetSection（独立 struct）

【provider 类型耦合点】三类型 openaiCompatible / anthropic / ccBridge 共用一个 View：
- L385-415 主耦合：单个 if/else 决定 ccBridgeStatusContent(L388) vs 标准 SecureField(L391-413)
- L109(macOS)/L181(iOS) section 标题按 type 三元：ccBridge→“连接状态”否则“API Key”
- L113-115 / L183-185 连接测试行对 ccBridge 隐藏 (type != .ccBridge)
- L774-783 fetchModels：ccBridge 直接返回失败；openai/anthropic 请求签名不同
- L872-904 testConnection：三个 case 各自构造请求
- L856 saveCustomProvider：customAnthropicId ? .anthropic : .openaiCompatible

【全局但应 per-provider 的状态】
- L12 savedProvider:String?  单一“刚保存”id，存后闪烁，应瞬时/按 provider
- L14 testingProvider:String?  同一时刻只能测一个
- L17 apiSelectedProviderId(@AppStorage) 全局“正在编辑”的 provider，切换即重置下方所有 UI 状态
- L22 apiFetchedModels / L23 apiIsFetchingModels / L24 apiFetchError / L25 apiModelSearch
   → 单一编辑缓冲，切 provider 时清空(L785-787)，三类型共用一份
- L28-31 customName/customBaseURL/customSavedId/customManualModelId
   → 同一组字段被“新建自定义”和“已存自定义”两种语义复用(L791-804)，切换时含义漂移
- L418 ccHubURLDraft 藏在 ccBridgeStatusContent 函数内、非 view 级，直接写 UserDefaults(L442)
正确全局的（无需改）：L18 selectedChatModelId / L19 memoryExtractModelId / L20 apiKeyCloudSync

【可拆分的独立 View（按优先级，仅建议）】
1. CC Bridge 状态面板 (L418-452) → 隔离 ccBridge 分支，消掉 L385-388 / L181-185 条件
2. API Key 输入 (L391-413) → 与 ccBridge 面板二选一，type 分叉收敛到一个组合点
3. 模型列表+fetch (L519-666) → ModelListSection(传 models/fetching/error/search/回调)
4. 自定义 provider 表单 (L332-383) → 拆“新建 vs 已存”两种语义
5. 连接测试行 (L454-517) → ConnectionTestRow，消掉 L113/L183 的 type 条件
6. provider Picker(L310-330) / 当前生效 Picker(L235-264) / 已保存列表(L266-294) 也可各自抽出

【结论】1218 行单文件，3 类型靠 ~8 处 type 条件 + 9 个全局编辑缓冲耦合在一起；
重写思路 = 按上面 6 块抽子 View，把 type 分叉收敛到组合边界，编辑缓冲下沉到各子 View。
```

- **只调查，不改代码，不 commit**
- 把发现写在对应的代码块里
- 记录具体文件名 + 行号
- 如果发现了明确的 bug 原因，直接写出来

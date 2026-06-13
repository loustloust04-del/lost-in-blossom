# CC ↔ API 上下文共享方案（CC-API-CONTEXT-SHARING）

> 日期：2026-06-13
> 任务：让 CC Bridge 会话和普通 API 会话不再是两个"失忆的脑子"。
> 原则：**只做摘要层互通，不做全量历史互灌**（token 爆炸 + 两边消息模型不同构）。
> 涉及：`cc-bridge/hub.ts`、`MemoryPalace/Services/ContextSummarizer.swift`、
> `CCBridgeProvider.swift`、`CCBridgeWebSocketClient.swift`、`MemoryService.swift`。

---

## 0. 现状（为什么是两个脑子）

- **API 会话**：`ChatService` 走 provider 发请求；超出 `contextDepth` 的旧消息由
  `ContextSummarizer` 压成一份「累计记忆」存 UserDefaults（key=`ctxSummary_<conversationId>`，
  含 `summary` + `coveredCount`）。这份摘要只注入 API 请求，CC 永远看不到。
- **CC 会话**：App 把 user 消息经 hub WS（`type:"chat"`）→ `buildChannelTag` 包成
  `<channel source="memorypalace" …>content</channel>` → tmux 注入到 `claude --continue` 进程。
  CC 用自己 tmux 会话里的上下文 + `.mcp.json` 的 imprint-memory 工具，**不知道 API 会话聊过什么**。
- 反向同样割裂：CC 的回复以独立 `MessageNode` 落进对话（`appendCCMessage`），但这些
  transcript 不会进入 API 侧的 `ContextSummarizer` / `MemoryService` 记忆体系。

两条链路在「同一个 conversation（chatId）」里已经天然交汇——CC 回复和 API 回复都挂在同一
`conversation.id` 下。这给了最便宜的打通点：**以 conversationId 为锚，让摘要双向流过。**

---

## 1. 目标与非目标

**目标**
1. **正向**（API → CC）：发往 CC 的 `<channel>` 消息携带「该对话 API 侧已压缩的摘要」，
   让 CC 接话时知道之前发生了什么。
2. **反向**（CC → 记忆）：把 CC 会话的 transcript 周期性摘要，落成 App 侧记忆，
   让后续 API 会话也能召回 CC 聊过的事实。

**非目标**
- 不把 API 的全量 message 数组塞给 CC，也不把 CC 的全量 transcript 灌进 API 请求。
- 不做实时逐 token 同步；摘要层是**最终一致**的，延迟到下一轮即可。
- 不引入新的跨会话存储系统；复用 `ContextSummarizer` + `MemoryService` 既有机件。

---

## 2. 正向：API 摘要 → CC（本方案先落地）

### 2.1 数据流
```
ConversationViewModel(发 CC 消息)
  → CCBridgeProvider.sendStreaming
      payload["context"] = ContextSummarizer.load(conversationId: chatId)?.summary   // 新增
  → wsClient.send(payload)
  → hub.ts: ChatMessage.context（新增字段）
  → buildChannelTag: 把 context 作为〔历史摘要〕块嵌进 channel tag 可见文本
  → tmux 注入 → CC 接话时看到摘要
```

### 2.2 协议改动（hub.ts）
- `ChatMessage` 接口加 `context?: string`。
- `buildChannelTag(msg, ts, attachments)`：若 `msg.context` 非空，在可见 content 前面拼一段
  `〔历史摘要〕<context>〔/历史摘要〕`（同样做换行压平 + 长度截断，默认上限 1500 字，
  避免 tmux `send-keys -l` 失败）。摘要本身 ≤800 字（ContextSummarizer 的硬约束），留足余量。
- 选择"嵌进可见文本"而非"channel 属性"：CC 读的是 tag 里的自然语言，属性它不会主动看；
  作为前缀文本，CC 接话时天然把它当背景。

### 2.3 App 端改动（CCBridgeProvider）
- `sendStreaming` 组 payload 时，按 chatId 取本对话已有摘要并附带：
  ```swift
  if let ctx = ContextSummarizer.load(conversationId: chatId)?.summary, !ctx.isEmpty {
      payload["context"] = ctx
  }
  ```
- 锚点是 `chatId`（= conversation.id）。同一对话里 API turns 产生的摘要直接复用，零额外计算。
- **可行性**：摘要已存在 UserDefaults，load 是同步 O(1)；不新增网络/模型调用。✅

### 2.4 跨会话扩展（P2，不在本期）
若要把"主 API 会话 A 的摘要"注入"独立 CC 会话 B"，需要 App 维护"当前主会话指针"
并允许用户选择来源对话。本期只做**同对话**共享，已覆盖"对话中途从 API 切到 CC"的主场景。

---

## 3. 反向：CC transcript → 记忆（设计确认，App 侧实现待 Xcode 验证）

### 3.1 思路
CC 的回复已经作为 `MessageNode`（role=assistant）落进对话（`appendCCMessage`）。复用既有
两条机件之一，**不新造系统**：

- **路径 A（推荐，复用 ContextSummarizer）**：CC 会话的 MessageNode 和 API 的一视同仁，
  本就会被 `ContextSummarizer` 在超窗时压进同一份 `ctxSummary_<conversationId>`。
  也就是说——**只要 CC transcript 进了 conversation 的 message 列表，正向链路 2 下一轮就会
  把它一起压进摘要再带回 CC**，反向其实"免费"打通了一半（CC 说过的话进了下一轮给 CC 的摘要）。
- **路径 B（落成长期 Memory）**：要让 CC 聊的事实进入**跨对话**的 `MemoryService` 记忆库，
  在 `appendCCMessage` 后，把 (上一条 user, 这条 CC reply) 喂给现有的记忆提取管线
  （`MemoryService.extract` / gateway `/memory/extract`），`source` 标记为 `cc`。
  提取是异步、带 gatekeeper 过滤的，不阻塞 UI。

### 3.2 触发与去重
- 不是每条都提取（成本）：按 N 条 CC 回复或对话空闲触发一次批量提取。
- 复用 MemoryService 既有的写时近似去重（sim>0.75 同款只强化不新增），避免 CC/API 重复落库。

### 3.3 可行性
- 路径 A：零代码（已天然成立，靠正向链路）。✅
- 路径 B：约 20~30 行 App 代码，挂在 `appendCCMessage` 后调用既有 extract；
  无新依赖。需在 Xcode 编译验证（本设计在无 Swift 编译环境的会话里只确认可行、不盲推）。⚠️

---

## 4. 实施顺序与状态

| 步骤 | 内容 | 状态 |
|---|---|---|
| 2.2 | hub.ts `ChatMessage.context` + `buildChannelTag` 注入 | ✅ 本次随方案落地（VPS 可测） |
| 2.3 | CCBridgeProvider 正向附带摘要 | ✅ 本次落地（小改动） |
| 3.1A | CC transcript 经 ContextSummarizer 自动回流 | ✅ 既有行为，无需改动 |
| 3.1B | CC transcript → MemoryService 长期记忆 | ⏳ 设计已确认，App 侧实现待 Xcode 验证 |
| 2.4 | 跨会话摘要共享 | ⏳ P2，本期不做 |

---

## 5. 风险

- **R1 摘要时效**：context 用的是"上一轮压缩游标"时的摘要，可能落后最近 ~20 条（compressionChunk）。
  可接受——摘要本就是"窗外历史"，最近消息 CC 在 tmux 里还能看到。
- **R2 长度**：context + content 同走一条 tmux 行。已做压平 + 1500 字截断；摘要硬上限 800 字，安全。
- **R3 隐私串台**：摘要按 conversationId 隔离，不会把别的对话/楼层（profileId）的摘要带进来。
- **R4 反向重复**：CC 和 API 可能对同一句话各提一次记忆；靠 MemoryService 写时去重兜底。

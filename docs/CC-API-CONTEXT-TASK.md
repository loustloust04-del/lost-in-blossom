# CC↔API 上下文共享 — 排查与完善任务

## 背景
设计文档：`docs/CC-API-CONTEXT-SHARING.md`
Day 20 已做了部分实现，需要验证和完善。

## 当前状态

### 正向（API→CC）✅ 已实现
- `CCBridgeProvider.sendStreaming` 发消息时附带 `ContextSummarizer.load()` 的摘要
- `hub.ts` 的 `buildChannelTag` 把 context 注入 channel tag
- **需要验证**：实际发给CC的消息里摘要是否可见、格式是否正确

### 反向（CC→记忆）⚠️ 部分实现
- `ConversationViewModel+Chat.swift` 的 `installCCFollowUpHandler` 里，CC回复后调 `extractMemoriesIfNeeded`
- **需要验证**：
  1. providerManager 是否正确传递（参数是 optional）
  2. extractMemoriesIfNeeded 实际被调用时，currentPath 里有没有CC的消息
  3. 记忆提取是否真的触发了（看日志）

## 需要读的文件

### 正向链路
- `MemoryPalace/Services/CCBridgeProvider.swift` — 看 sendStreaming 里 context 怎么附带的
- `cc-bridge/hub.ts` — 看 buildChannelTag 怎么注入 context
- `MemoryPalace/Services/ContextSummarizer.swift` — 看 load/save 的 key 格式

### 反向链路
- `MemoryPalace/ViewModels/ConversationViewModel+Chat.swift` — 看 installCCFollowUpHandler 和 appendCCMessage
- `MemoryPalace/Services/MemoryService.swift` — 看 extract 的触发条件

## 排查任务

### 1. 正向验证
- 在VPS上找一个有API摘要的对话，切到CC模式发消息
- 检查hub日志：buildChannelTag 输出的 tag 里有没有摘要内容
- 检查CC tmux：CC 收到的消息里能不能看到历史摘要

### 2. 反向验证
- 用CC回复一条消息
- 检查 extractMemoriesIfNeeded 是否被调用（加 print 日志）
- 检查 MemoryService 是否真的提取了记忆
- 检查提取的记忆 source 是否标记为 cc

### 3. 边界情况
- 新对话（没有API摘要）切到CC → context 应该为空，不应该报错
- CC proactive 消息 → 反向提取应该也能触发（走 unhandledReplyHandler）
- providerManager 为 nil 时 → 反向提取应该优雅跳过

### 4. 路径3.1A验证
- CC回复的 MessageNode 是否被 ContextSummarizer 纳入压缩
- 下一轮API调用时，摘要里有没有CC说过的内容

## 代码改进建议
- installCCFollowUpHandler 的 providerManager 从 loadConversation 调用时是 nil，考虑存为 ViewModel 属性
- 反向提取加日志：`print("[CC→Memory] extracting from CC reply: \(chatId)")`
- 考虑是否需要对CC回复做频率限制（不是每条都提取，设计文档建议 N 条触发一次）

## 期望输出
1. 验证正向和反向链路是否真的端到端通了
2. 修复发现的问题
3. 加必要的日志方便后续 debug
4. 不要改动群聊相关代码（另一个任务在排查）

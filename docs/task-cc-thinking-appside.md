# CC 思考链 App 端修复

> CC 思考链的后端管线已通（Stop hook → extract → hub 广播）。
> 这个任务修 App 端的接收和显示。

---

## 问题

1. `latestThinking` 是单值属性，新 thinking 覆盖旧的，导致只有最新一条消息有思考链
2. CC 流式输出（cc_stream）App 端没有集成显示

---

## Commit 1: thinking 存储改为按消息关联

### CCBridgeWebSocketClient.swift

当前：
```swift
private(set) var latestThinking: CCThinkingBlock?
```

改成按 chat_id 存储的字典：
```swift
private(set) var thinkingBlocks: [String: CCThinkingBlock] = [:]
```

在 `handleIncoming` 里处理 `cc_thinking` 消息时，改成：
```swift
case "cc_thinking":
    if let thinking = obj["thinking"] as? String,
       let sessionId = obj["session_id"] as? String {
        let block = CCThinkingBlock(thinking: thinking, sessionId: sessionId, timestamp: Date())
        DispatchQueue.main.async { [weak self] in
            self?.thinkingBlocks[sessionId] = block
        }
    }
```

同时保留 `latestThinking` 作为快捷访问（向后兼容）：
```swift
private(set) var latestThinking: CCThinkingBlock? {
    thinkingBlocks.values.sorted(by: { $0.timestamp > $1.timestamp }).first
}
```

不对，@Observable 的计算属性不能有 private(set)。改成：
```swift
var latestThinking: CCThinkingBlock? {
    thinkingBlocks.values.max(by: { $0.timestamp < $1.timestamp })
}
```

同时把 `private(set) var latestThinking: CCThinkingBlock?` 这行删掉。

### CardFlowView.swift

找到所有引用 `latestThinking` 的地方（如果有的话），确认它们仍然能工作。
如果 CardFlowView 通过 CCBridgeWebSocketClient.shared.latestThinking 访问，
现在变成了计算属性，行为不变。

如果 CardFlowView 里有按 chat_id 显示 thinking 的逻辑，
可以改成从 `thinkingBlocks[chatId]` 获取对应消息的 thinking。

---

## Commit 2: CC 流式输出集成

### CCBridgeWebSocketClient.swift

添加流式输出的 observable 属性：
```swift
/// CC 终端的最新流式输出（hub 通过 cc_stream 推送）
private(set) var streamContent: String = ""
/// CC 是否正在输出
private(set) var isCCStreaming: Bool = false
```

在 `handleIncoming` 里添加 cc_stream 和 cc_stream_end 的处理：
```swift
case "cc_stream":
    if let content = obj["content"] as? String {
        DispatchQueue.main.async { [weak self] in
            self?.streamContent += content
            self?.isCCStreaming = true
        }
    }
case "cc_stream_end":
    DispatchQueue.main.async { [weak self] in
        self?.isCCStreaming = false
        // 不清空 streamContent，等下一次 cc_stream 开始时再清
    }
```

在 `handleIncoming` 的 `cc_stream` case 里，如果 `isCCStreaming` 是 false（新的一轮输出开始），先清空 streamContent：
```swift
case "cc_stream":
    if let content = obj["content"] as? String {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.isCCStreaming {
                self.streamContent = ""  // 新一轮，清空旧内容
            }
            self.streamContent += content
            self.isCCStreaming = true
        }
    }
```

### 注意

CC 流式输出的 UI 展示（在哪里显示、怎么显示）暂时不做。
先把数据通道打通，App 能接收到 cc_stream 数据即可。
UI 展示后续再设计。

---

## 执行顺序

1. Commit 1 — `fix: store CC thinking blocks by session ID`
2. Commit 2 — `feat: receive CC stream output in app`
3. Push all to main

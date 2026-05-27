# 任务：思考链流式输出

## 当前行为
reasoning_content 被累积到 streamingThinking 缓冲区 → [DONE] 时一次性拼到 content 前面。
思考内容一整块出现，不是逐字的。

## 目标行为
思考链也要逐字流式显示——跟正文一样一个字一个字涌出来。
用户能实时看到 AI 正在"想什么"。

## 实现方案

### 1. ChatService 加 onThinkingToken 回调

```swift
// ChatService.swift
var onThinkingToken: ((String) -> Void)?

// 在 resetState 里初始化
func resetState(onToken:..., onThinkingToken: ((String) -> Void)? = nil, ...) {
    self.onThinkingToken = onThinkingToken
    ...
}

// 在 parseOpenAIChunk 里，收到 reasoning_content 时：
if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
    streamingThinking += reasoning
    DispatchQueue.main.async { [self] in
        onThinkingToken?(reasoning)  // 实时发送每个 chunk
    }
}
```

### 2. ConversationViewModel 加 streamingThinking 属性

```swift
@Published var streamingThinkingText: String = ""
@Published var isThinking: Bool = false

// 在调用 ChatService 时传入 onThinkingToken：
chatService.sendStreaming(
    ...
    onThinkingToken: { [weak self] token in
        self?.streamingThinkingText += token
        if !self?.isThinking ?? false {
            self?.isThinking = true
        }
    },
    onToken: { [weak self] token in
        if self?.isThinking ?? false {
            self?.isThinking = false  // content 开始了，thinking 结束
        }
        // 正常处理 content token
    }
)
```

### 3. UI：流式思考区域

在助手消息气泡里——当 `isThinking == true` 或 `streamingThinkingText` 非空时——显示一个实时更新的"思考过程"折叠区域：

```swift
if !viewModel.streamingThinkingText.isEmpty {
    DisclosureGroup("思考过程") {
        Text(viewModel.streamingThinkingText)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

思考进行中时——折叠区域默认展开——让用户看到文字在涌出。
思考结束后——自动折叠——正文开始流式显示。

### 4. 思考→正文的过渡

当 reasoning_content 停止、content 开始时：
- `isThinking = false`
- 思考区域折叠
- 同时触发震动反馈（转折震）
- streamingThinkingText 保留——用户可以展开查看

### 5. 最终保存

流式结束时（[DONE]）——streamingThinkingText 的内容已经通过 [thinking] 标记保存在消息内容里（现有逻辑不变）。下次打开对话——思考链从消息内容的 [thinking] 标记解析——跟现在一样。

---

注意：这个改动涉及三层——ChatService、ConversationViewModel、UI。每层单独 commit。

---

## 思考链 UI — Claude App 风格

参考 Claude iOS App 的思考链 UI（天奕截图）。

### 1. 灰色小字预览行
在助手消息上方——显示一行灰色小字：
- 思考进行中："思考中…"（带呼吸动画）
- 思考完成：截取思考链前 40 个字 + "…" 作为预览
- 字号 13px，色 #9B8E7E，左侧加 🕐 小图标
- 点击 → 弹出思考面板

### 2. 思考面板（Bottom Sheet）
```swift
.sheet(isPresented: $showThinkingPanel) {
    ThinkingPanelView(content: thinkingText)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

面板内容：
- 顶部标题 "Thought process" + 关闭按钮
- 下方是滚动的思考链全文
- 字号 15px，行间距 1.5

### 3. 橙色进度线（思考进行中）
在思考面板顶部——当 `isThinking == true` 时——显示一条橙色的流动线：

```swift
// 橙色流动线
if isThinking {
    GeometryReader { geo in
        Rectangle()
            .fill(Color.orange)
            .frame(width: geo.size.width * 0.3, height: 2)
            .offset(x: animateProgress ? geo.size.width * 0.7 : -geo.size.width * 0.3)
            .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: animateProgress)
            .onAppear { animateProgress = true }
    }
    .frame(height: 2)
}
```

思考完成 → 进度线消失。

### 4. 替换现有的 DisclosureGroup
现在的思考链用 DisclosureGroup 折叠。改为：
- 消息上方显示灰色小字预览
- 点击 → 底部 sheet 弹出完整思考链
- 删除 DisclosureGroup 方式

---

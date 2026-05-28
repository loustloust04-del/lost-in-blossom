# 任务：支持 Claude 通过 OpenRouter 的思考链

## 问题
当前代码只处理 DeepSeek 的 reasoning_content。Claude 通过 OpenRouter 需要在请求里加 `reasoning` 参数才会返回思考链。

## 修复

### 1. 请求端：加 reasoning 参数

在 `OpenAICompatibleProvider` 的 `sendStreaming` 方法里，构建 body 时，检测模型名是否包含 "claude"，如果是则加 reasoning 参数：

```swift
// 在 body 构建完成后、发送请求前加入：
let modelLower = model.lowercased()
if modelLower.contains("claude") {
    body["reasoning"] = ["effort": "high"]
}
```

### 2. 响应端：解析 reasoning_content 或 reasoning_details

OpenRouter 可能用两种方式返回 Claude 的思考链：

方式A：跟 DeepSeek 一样在 streaming delta 里用 `reasoning_content` 字段
→ 现有代码已支持，无需修改

方式B：在 streaming delta 里用 `reasoning` 字段
→ 需要额外解析：

```swift
// 在 parseOpenAIChunk 里，已有的 reasoning_content 解析之后加：
if let reasoningObj = delta["reasoning"] as? [String: Any],
   let reasoningText = reasoningObj["content"] as? String,
   !reasoningText.isEmpty {
    DispatchQueue.main.async { [self] in
        streamingThinking += reasoningText
        onThinkingToken?(reasoningText)
    }
}
```

也检查 delta 里是否有 `reasoning_content`（有些 OpenRouter 版本用这个字段）：
```swift
// 这部分代码已存在（DeepSeek），确保对 Claude 也生效即可
if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
    // 已有代码...
}
```

### 3. 测试
- 用 OpenRouter + Claude Opus 4.6 发一条需要思考的消息
- 确认思考链出现在 [thinking] 标记里
- 确认正文正常流式显示

一个 commit。

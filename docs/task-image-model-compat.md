# 任务：切换模型时自动过滤不支持的内容类型

读 CLAUDE.md。不引入 regression。

## 问题

对话上下文中有图片时，如果用户切换到不支持图片的模型，API 会报错导致对话卡死，无法继续使用。

## 方案

在构建 messages 数组发送给 API 之前，检查目标模型是否支持图片。如果不支持，自动过滤掉历史消息里的 image content block，只保留 text content。

## 实现

### Step 1: 模型能力标记

在 `ProviderModel`（或 `APIProvider`）里加一个属性标记模型是否支持图片输入：

```swift
var supportsImageInput: Bool {
    // Anthropic Claude 系列、OpenAI GPT-4o 系列支持图片
    // DeepSeek 等纯文本模型不支持
    // 根据 provider type 和 model id 判断
    switch provider.type {
    case .anthropic, .openRouter:
        return true // 大部分都支持
    case .openAI:
        return modelId.contains("gpt-4") // GPT-4 系列支持，GPT-3.5 不支持
    case .deepSeek:
        return false
    default:
        return false
    }
}
```

或者更简单：在 ProviderModel 的定义里加一个 `supportsVision: Bool` 字段，在模型列表里手动标记。

### Step 2: 发送前过滤

在 ChatService 或 PromptAssembler 构建 messages 数组的地方，发送前检查：

```swift
// 如果模型不支持图片，过滤掉 image content blocks
if !currentModel.supportsImageInput {
    messages = messages.map { msg in
        // 如果 content 是数组格式（包含 image + text blocks）
        // 只保留 text blocks，把 image block 替换为 "[图片]"
        return filterImageContent(msg)
    }
}
```

### Step 3: 用户提示（可选）

切换到不支持图片的模型时，如果当前对话包含图片，显示一个轻提示（toast）：
"此模型不支持图片，历史消息中的图片将被忽略"

---

一个 commit：`fix: auto-filter image content when switching to text-only model`

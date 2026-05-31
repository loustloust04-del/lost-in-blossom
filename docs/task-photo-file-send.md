# 任务：图片/文件发送功能完善

## 背景
App 已有基础的照片发送功能（commit 2e285f1），但需要确保可以向 API 发送图片和文件，让模型能看到用户上传的内容。

## Task 1: 图片发送到 API

确保用户选择的图片在发送消息时作为 base64 编码的 image content block 一起发给 API。

检查 ChatService / PromptAssembler 里构建 messages 数组的逻辑：
- 用户选了图片 → 消息的 content 应该是数组格式：`[{type: "image", ...}, {type: "text", ...}]`
- 而不是只发文本
- 图片需要压缩到合理大小（最大 1MB 或 1024px 长边），避免 API 超限
- 支持的格式：JPEG, PNG, GIF, WebP

参考 Anthropic Messages API 的 image content block 格式：
```json
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/jpeg",
    "data": "<base64>"
  }
}
```

## Task 2: 文件发送（PDF）

如果 App 有文件选择入口（或需要新增），支持用户发送 PDF：
- PDF 作为 document content block 发给 API
- 格式：`{type: "document", source: {type: "base64", media_type: "application/pdf", data: "<base64>"}}`
- 大小限制：最大 10MB

## Task 3: UI 反馈

- 发送图片时在输入框上方显示缩略图预览（如果还没有）
- 上传/编码过程中显示 loading 状态
- 发送成功后图片在聊天气泡里显示

---

读 CLAUDE.md。一个 commit：`feat: image and file send to API`

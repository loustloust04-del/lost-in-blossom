# 聊天记录解析指令

## 目标

做一个网页工具：导入 ChatGPT / Claude 的聊天导出文件 → 自动拆分成一个一个对话窗口 → 用小模型浏览每个窗口生成摘要 → 点击摘要可检索原文。

## 一、ChatGPT 导出格式

### 文件
`conversations.json`（从 ChatGPT Settings → Export data 拿到的 zip 里解压出来）

### 数据结构
```json
[
  {
    "id": "对话ID",
    "title": "对话标题",
    "create_time": 1700000000.0,
    "mapping": {
      "node_id_1": {
        "id": "node_id_1",
        "message": {
          "id": "msg_id",
          "author": { "role": "user|assistant|system|tool" },
          "content": { "content_type": "text", "parts": ["文本内容"] },
          "create_time": 1700000000.0
        }
      }
    }
  }
]
```

### 关键逻辑
1. **树状结构**：mapping 是 node 字典，不是线性数组。
2. **提取文本**：`message.content.parts` 取字符串元素，跳过图片对象。
3. **过滤**：role=system 跳过。
4. **时间戳**：浮点 Unix 秒 → `new Date(ts * 1000)`。

### 解析伪代码
```javascript
for (const conv of conversations) {
  const title = conv.title || "无标题"
  const messages = Object.values(conv.mapping)
    .filter(n => n.message?.author?.role !== "system")
    .map(n => ({
      role: n.message.author.role,
      content: (n.message.content?.parts || []).filter(p => typeof p === "string").join("\n"),
      time: n.message.create_time
    }))
    .filter(m => m.content.trim())
    .sort((a, b) => (a.time || 0) - (b.time || 0))
}
```

---

## 二、Claude 导出格式

### 文件
`conversations.json`（从 Claude.ai Settings → Export data）

### 数据结构
```json
[
  {
    "uuid": "对话UUID",
    "name": "对话标题",
    "created_at": "2024-01-01T00:00:00Z",
    "chat_messages": [
      {
        "uuid": "消息UUID",
        "text": "纯文本（旧格式 fallback）",
        "content": [
          { "type": "text", "text": "消息文本" },
          { "type": "thinking", "thinking": "思考链" },
          { "type": "tool_use", "name": "工具名", "input": {} },
          { "type": "tool_result", "content": "返回内容" }
        ],
        "sender": "human|assistant",
        "created_at": "ISO 8601",
        "parent_message_uuid": "父消息UUID"
      }
    ]
  }
]
```

### 关键逻辑
1. **基本线性**：chat_messages 按时间排，parent_message_uuid 可构建树但通常线性够用。
2. **多 block**：一条消息可能同时有 text + thinking + tool_use。
3. **提取文本**：优先 content 数组里 type=text 的 .text，fallback 到顶层 .text。
4. **思考链**：type=thinking 的 .thinking 字段。
5. **sender**：human=用户，assistant=Claude。

### 解析伪代码
```javascript
for (const conv of conversations) {
  const title = conv.name || "无标题"
  const messages = (conv.chat_messages || []).map(msg => {
    let text = "", thinking = ""
    if (msg.content?.length) {
      for (const b of msg.content) {
        if (b.type === "text" && b.text) text += b.text + "\n"
        if (b.type === "thinking" && b.thinking) thinking += b.thinking + "\n"
      }
    }
    if (!text && msg.text) text = msg.text
    return { role: msg.sender === "human" ? "user" : "assistant", content: text.trim(), thinking: thinking.trim(), time: new Date(msg.created_at) }
  }).filter(m => m.content)
}
```

---

## 三、格式自动检测
```javascript
function detectFormat(data) {
  if (Array.isArray(data) && data[0]?.mapping) return "chatgpt"
  if (Array.isArray(data) && data[0]?.chat_messages) return "claude"
  return "unknown"
}
```

## 四、源代码参考
- `MemoryPalace/Services/ConversationImporter.swift` (567行) — ChatGPT
- `MemoryPalace/Services/ClaudeImporter.swift` (848行) — Claude
- `MemoryPalace/Services/ImportSupport.swift` (376行) — 共享

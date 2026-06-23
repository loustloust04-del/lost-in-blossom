# CC任务：claude -p 包装成 API Provider

## 目标
把 `claude -p` 包装成一个 OpenAI 兼容的 API 端点，让 App 把它当作普通模型使用。切换到这个模型时，共享同一份对话历史，跟切 Sonnet/Opus 一样无缝。

## 已验证
VPS 上 `claude -p --output-format stream-json --verbose` 能跑，输出格式：
```json
{"type":"system","subtype":"init",...}
{"type":"assistant","message":{"content":[{"type":"text","text":"OK"}],"usage":{...}}}
{"type":"result","subtype":"success","result":"OK",...}
```
模型是 claude-opus-4-6，走 Pro/Max 订阅不花 API 钱。

## 实现方案

### 1. Gateway 加端点

在 `gateway/src/app.ts` 加 OpenAI 兼容的 `/v1/chat/completions` 处理分支。
当 model 字段是 `claude-code` 或 `claude-p` 时，走本地 claude -p 子进程而非外部 API。

```typescript
import { spawn } from "child_process"

// 检测到 claude-code 模型时走本地 -p
if (model === "claude-code" || model === "claude-p") {
  return handleClaudeP(messages, stream, res)
}
```

### 2. handleClaudeP 函数

```typescript
async function handleClaudeP(messages, stream, res) {
  // 1. 把 messages 数组格式化成 prompt
  //    system → --system-prompt 参数
  //    user/assistant 交替 → 拼成对话文本
  
  // 2. spawn claude -p
  const proc = spawn("claude", [
    "-p",
    "--output-format", "stream-json",
    "--verbose",
    "--model", "claude-opus-4-6",  // 或从请求参数取
  ], { cwd: "/root/projects/BunnyPalace" })
  
  // 3. 写入 prompt 到 stdin
  proc.stdin.write(formattedPrompt)
  proc.stdin.end()
  
  // 4. 如果 stream=true，逐行读 stdout
  //    解析 type=assistant 的 message
  //    转换成 OpenAI SSE 格式：
  //    data: {"choices":[{"delta":{"content":"OK"}}]}
  //    ...
  //    data: [DONE]
  
  // 5. 如果 stream=false，等完整结果返回
}
```

### 3. 消息格式化

OpenAI messages 数组 → claude -p prompt：
```
messages = [
  {role: "system", content: "你是Caelum"},
  {role: "user", content: "你好"},
  {role: "assistant", content: "你好呀"},
  {role: "user", content: "今天吃了什么"}
]

→ system prompt: "你是Caelum"
→ stdin prompt: "以下是对话历史：\n用户: 你好\nCaelum: 你好呀\n用户: 今天吃了什么\n\n请回复最后一条用户消息。"
```

或者更好的方式：用 `--resume` 和 conversation history 参数（如果 claude -p 支持的话）。

### 4. stream-json → OpenAI SSE 转换

```typescript
// claude -p 输出的每一行
line = '{"type":"assistant","message":{"content":[{"type":"text","text":"OK"}]}}'

// 转换成 OpenAI SSE
sseChunk = `data: ${JSON.stringify({
  id: "chatcmpl-" + uuid,
  object: "chat.completion.chunk", 
  model: "claude-code",
  choices: [{
    index: 0,
    delta: { content: parsed.message.content[0].text },
    finish_reason: null
  }]
})}\n\n`
```

注意：`claude -p` 的 stream-json 不是逐 token 的 delta，而是整条消息一次性返回。如果需要真逐字流式，要加 `--include-partial-messages` 参数（已验证 claude 支持）。

### 5. App端（模型列表）

Gateway 的 `/v1/models` 里加上 claude-code 模型：
```typescript
{ id: "claude-code", object: "model", owned_by: "local" }
```

App 端不需要任何改动——它已经从 `/v1/models` 拉列表，选了 claude-code 就走 Gateway，Gateway 内部分发到 claude -p。

### 6. 注意事项

- `claude -p` 每次是独立进程，**没有持久上下文**，靠 messages 数组传历史
- 走 Pro/Max 订阅，有 rate limit，不是无限的
- 子进程的 cwd 要设对（影响 CLAUDE.md 加载）
- system prompt 不要太长（算在 input tokens 里，影响 rate limit）
- 考虑加进程池或队列防止并发过多

## 需要读的文件
- `gateway/src/app.ts` — 现有的 /v1/chat/completions 路由
- `gateway/src/providers/` — 现有的 provider 实现参考
- `gateway/src/tools/builtin.ts` — BUILTIN_TOOLS 定义（/v1/models 在这附近）

## 验证
1. curl 测试非流式：
```bash
curl http://localhost:4567/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-code","messages":[{"role":"user","content":"你好"}]}'
```
2. curl 测试流式（stream:true）
3. App 里选 claude-code 模型发消息，验证回复正常
4. 在同一对话里切 DeepSeek → claude-code → DeepSeek，验证上下文连续

## 参考
- 教程仓库：https://github.com/sanqianzilanyue-commits/claude-p-thinking-stream
- VPS上已验证命令：`echo "test" | claude -p --output-format stream-json --verbose`

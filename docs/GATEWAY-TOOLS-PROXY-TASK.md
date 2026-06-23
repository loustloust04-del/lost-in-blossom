# CC任务：Gateway工具代理 — 让CC能调用所有Gateway工具

## 目标
在 `cc-bridge/mcp-server.ts` 里加代理工具，CC调用时转发到Gateway执行。完成后CC拥有和API一样的全部工具能力。

## 需要代理的工具

| 工具名 | 功能 | 定义在 |
|--------|------|--------|
| exec | 执行shell命令 | gateway/src/tools/builtin.ts |
| recall | 语义搜索长期记忆 | gateway/src/tools/builtin.ts |
| remember | 存储记忆 | gateway/src/tools/builtin.ts |
| gmail_inbox | 获取收件箱 | gateway/src/tools/gmail.ts |
| gmail_read | 读邮件 | gateway/src/tools/gmail.ts |
| gmail_send | 发邮件 | gateway/src/tools/gmail.ts |
| gmail_search | 搜索邮件 | gateway/src/tools/gmail.ts |
| vitals_water | 喝水记录 | gateway/src/vitals.ts |
| vitals_food | 吃饭记录 | gateway/src/vitals.ts |
| vitals_meds | 药物记录 | gateway/src/vitals.ts |
| get_phone_status | 手机状态 | gateway/src/phone-status.ts |

## 实现方案

### 1. Gateway端：加内部工具调用端点

在 `gateway/src/app.ts` 里加一个内部端点：

```typescript
// 内部工具调用（只允许本机）
app.post("/internal/tool-call", async (c) => {
  const { name, input } = await c.req.json()
  const result = await callBuiltinTool(name, input)
  return c.json({ result: result ?? "工具未找到或执行失败" })
})
```

安全性：nginx不暴露/internal/*，只有127.0.0.1能访问。

### 2. CC端：mcp-server.ts加代理工具

在 `cc-bridge/mcp-server.ts` 里：

```typescript
// Gateway工具代理
const GATEWAY_URL = "http://127.0.0.1:4567"

// 工具定义（从builtin.ts复制schema，或启动时从Gateway拉取）
const PROXY_TOOLS = [
  { name: "exec", description: "执行shell命令", input_schema: { type: "object", properties: { command: { type: "string" } }, required: ["command"] } },
  { name: "recall", description: "搜索长期记忆", input_schema: { type: "object", properties: { query: { type: "string" }, exact: { type: "boolean" } }, required: ["query"] } },
  { name: "remember", description: "存储记忆", input_schema: { type: "object", properties: { content: { type: "string" }, category: { type: "string" }, tier: { type: "number" } }, required: ["content"] } },
  // ... gmail, vitals, phone_status 同理
]

// 注册到MCP server的tools/list
// 调用时转发到Gateway
async function proxyToGateway(toolName: string, input: any): Promise<string> {
  const res = await fetch(`${GATEWAY_URL}/internal/tool-call`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name: toolName, input })
  })
  const data = await res.json()
  return data.result
}
```

### 3. 认证
Gateway的 `/internal/tool-call` 端点跳过auth（只监听127.0.0.1）。或者用环境变量里已有的GATEWAY_TOKEN做内部认证。

## 需要读的文件
- `cc-bridge/mcp-server.ts` — 你自己的MCP server，在这里加工具
- `gateway/src/tools/builtin.ts` — Gateway工具定义和schema
- `gateway/src/tools/gmail.ts` — Gmail工具schema
- `gateway/src/vitals.ts` — Vitals工具schema
- `gateway/src/phone-status.ts` — Phone工具schema
- `gateway/src/app.ts` — 加内部端点

## 验证
1. CC里调 `recall("兔兔")` → 应返回记忆搜索结果
2. CC里调 `exec("uptime")` → 应返回VPS运行时间
3. CC里调 `gmail_inbox()` → 应返回最近邮件
4. 确认Gateway日志里能看到内部调用记录

## 注意
- 不要改动Gateway对外的API行为
- 工具schema要和Gateway原始定义一致
- exec工具有安全风险，CC已经有VPS访问权限所以可以开放
- 完成后重启CC让新的MCP工具生效（/login不需要，退出重进mp-cc就行）

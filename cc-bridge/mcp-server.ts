#!/usr/bin/env bun
import { Server } from "@modelcontextprotocol/sdk/server/index.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js"
import { WebSocket } from "ws"

const HUB_URL = process.env.MP_CC_HUB_URL ?? "ws://127.0.0.1:7890/mcp"
// hub 对所有连接（含 loopback）强制 token 鉴权，连接 URL 必须带 token
const HUB_TOKEN = process.env.MP_CC_HUB_TOKEN ?? ""
const PING_INTERVAL_MS = 15_000

// ── Gateway 工具代理 ──
// CC 通过这些代理工具调用 Gateway 的内置工具（exec/recall/remember/gmail/vitals/phone），
// 让 CC 拥有和 /v1 API 一样的全部工具能力。请求转发到 Gateway 的 /internal/tool-call。
// cc-bridge 与 gateway 同机，默认走 loopback；如设了 GATEWAY_TOKEN 则一并带上做内部认证。
const GATEWAY_URL = process.env.GATEWAY_URL ?? "http://127.0.0.1:4567"
const GATEWAY_TOKEN = process.env.GATEWAY_TOKEN ?? ""

const PROXY_TOOLS = [
  {
    name: "exec",
    description: "Run a shell command on the VPS the gateway lives on. Returns stdout and stderr. 60s timeout; use nohup for long jobs.",
    inputSchema: {
      type: "object",
      properties: { command: { type: "string", description: "shell command" } },
      required: ["command"],
    },
  },
  {
    name: "recall",
    description: "Search long-term memory and return full entries. exact=true does verbatim full-text search over past messages (needs 3+ chars); otherwise semantic search over memories.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "what to recall" },
        exact: { type: "boolean", description: "verbatim full-text search instead of semantic" },
      },
      required: ["query"],
    },
  },
  {
    name: "remember",
    description: "Store one piece of information into long-term memory right now. The entry is embedded and persisted; it will surface again via recall.",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string", description: "要记住的信息，一句完整、可独立理解的话" },
        category: { type: "string", enum: ["preference", "fact", "relationship", "goal", "context"], description: "分类：偏好 / 事实 / 关系 / 目标 / 上下文" },
        tier: { type: "number", description: "重要程度 1-4：1核心 2重要 3普通 4碎片（默认 3）" },
      },
      required: ["content"],
    },
  },
  {
    name: "gmail_inbox",
    description: "List recent emails from inbox. Returns subject, sender, date, snippet for each.",
    inputSchema: {
      type: "object",
      properties: { count: { type: "number", description: "number of emails (default 5, max 20)" } },
    },
  },
  {
    name: "gmail_read",
    description: "Read full content of a specific email by message ID.",
    inputSchema: {
      type: "object",
      properties: { messageId: { type: "string", description: "Gmail message ID" } },
      required: ["messageId"],
    },
  },
  {
    name: "gmail_send",
    description: "Send an email.",
    inputSchema: {
      type: "object",
      properties: { to: { type: "string" }, subject: { type: "string" }, body: { type: "string" } },
      required: ["to", "subject", "body"],
    },
  },
  {
    name: "gmail_search",
    description: "Search emails with Gmail query syntax (e.g. \"from:someone subject:hello\").",
    inputSchema: {
      type: "object",
      properties: { query: { type: "string", description: "Gmail search query" }, count: { type: "number" } },
      required: ["query"],
    },
  },
  {
    name: "vitals_water",
    description: "Record that Bunny drank water. Each call adds 1 cup.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "vitals_food",
    description: "Record that Bunny ate a meal. Call with what she ate.",
    inputSchema: {
      type: "object",
      properties: { meal: { type: "string", description: "what she ate, e.g. \"早餐：面包牛奶\"" } },
      required: ["meal"],
    },
  },
  {
    name: "vitals_meds",
    description: "Record that Bunny took her medication (右佐匹克隆/扎来普隆).",
    inputSchema: {
      type: "object",
      properties: { name: { type: "string", description: "medication name" } },
    },
  },
  {
    name: "get_phone_status",
    description: "Get Bunny's phone status for today — battery level, charging state, timestamps. No parameters needed.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "see_screen",
    description: "看用户 iPhone 的当前屏幕：返回最新一张屏幕截图（图片）+ 当前 App 名。用户说\"看我的屏幕 / 看这个 / 帮我看看屏幕上的…\"时调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "peek_screen",
    description: "主动窥屏：你自己发起偷看用户 iPhone 屏幕，不用用户动手。会给用户手机发触发邮件，手机静默截屏并上传，然后返回那张最新截图（图片）+ App 名。想主动看看兔兔现在在干嘛时调用。若长时间没等到截图会返回文字说明。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "remember_anniversary",
    description: "记住一个纪念日或倒计时。兔兔说记一下X月X日相识/生日/距离Y还有多久时调用。type=anniversary 每年循环，type=countdown 一次性未来日期。",
    inputSchema: { type: "object", properties: { name: { type: "string" }, date: { type: "string", description: "YYYY-MM-DD" }, type: { type: "string", enum: ["anniversary", "countdown"] } }, required: ["name", "date"] },
  },
  {
    name: "get_health",
    description: "Bunny 的健康数据（HealthKit 摘要）：今日步数/睡眠/经期日/饮水/屏幕时间 + 近 14 天趋势。想关心她睡得好不好、身体状态时调用。No parameters.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "list_anniversaries",
    description: "查看所有纪念日/倒计时及今天的状态（第几天/还有几天）。想主动关心日子或兔兔问起时调用。",
    inputSchema: { type: "object", properties: {} },
  },
] as const

const PROXY_TOOL_NAMES = new Set(PROXY_TOOLS.map(t => t.name))

async function proxyToGateway(name: string, input: any): Promise<string> {
  try {
    const headers: Record<string, string> = { "Content-Type": "application/json" }
    if (GATEWAY_TOKEN) headers["Authorization"] = "Bearer " + GATEWAY_TOKEN
    const res = await fetch(`${GATEWAY_URL}/internal/tool-call`, {
      method: "POST",
      headers,
      body: JSON.stringify({ name, input: input ?? {} }),
    })
    if (!res.ok) return `Gateway tool '${name}' failed: HTTP ${res.status}`
    const data = await res.json() as { result?: string }
    return data.result ?? "工具未找到或执行失败"
  } catch (err) {
    return `Gateway unreachable for '${name}': ${(err as Error)?.message ?? "unknown"}`
  }
}

function hubURLWithToken(): string {
  if (!HUB_TOKEN) return HUB_URL
  try {
    const u = new URL(HUB_URL)
    u.searchParams.set("token", HUB_TOKEN)
    return u.toString()
  } catch {
    return HUB_URL
  }
}

let hubWS: WebSocket | null = null
let connectingPromise: Promise<WebSocket> | null = null
let reconnectTimer: ReturnType<typeof setTimeout> | null = null
let pingTimer: ReturnType<typeof setInterval> | null = null
let reconnectDelay = 1_000  // 1s → 2 → 4 → 8 → 16 → 30 (capped)

// 永不 throw、永不喷 stderr：CC 的 MCP host 看到 stderr 可能判定 unhealthy
// 然后 disable + kill 这个子进程。要不计代价保持 silent + alive。
process.on("uncaughtException", () => { /* swallow */ })
process.on("unhandledRejection", () => { /* swallow */ })

function scheduleReconnect() {
  if (reconnectTimer) return
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null
    connectHub().catch(() => {
      reconnectDelay = Math.min(reconnectDelay * 2, 30_000)
      scheduleReconnect()
    })
  }, reconnectDelay)
}

function startPing() {
  stopPing()
  pingTimer = setInterval(() => {
    if (hubWS && hubWS.readyState === WebSocket.OPEN) {
      try { hubWS.ping() } catch { /* let close handler clean up */ }
    }
  }, PING_INTERVAL_MS)
}

function stopPing() {
  if (pingTimer) {
    clearInterval(pingTimer)
    pingTimer = null
  }
}

function connectHub(): Promise<WebSocket> {
  if (hubWS && hubWS.readyState === WebSocket.OPEN) return Promise.resolve(hubWS)
  if (connectingPromise) return connectingPromise

  connectingPromise = new Promise((resolve, reject) => {
    const ws = new WebSocket(hubURLWithToken())
    hubWS = ws
    ws.on("open", () => {
      connectingPromise = null
      reconnectDelay = 1_000  // 成功后重置退避
      startPing()
      resolve(ws)
    })
    ws.on("error", (err) => {
      connectingPromise = null
      hubWS = null
      stopPing()
      reject(err)
    })
    ws.on("close", () => {
      hubWS = null
      stopPing()
      // hub 重启 / 网络抖动 → 自动重连，不等下次 reply tool call
      scheduleReconnect()
    })
  })
  return connectingPromise
}

const server = new Server(
  { name: "cc-bridge-mcp", version: "0.2.0" },
  { capabilities: { tools: {} } }
)

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "reply",
      description: "Send a message to a Memory Palace conversation. Normally used to respond to <channel source=\"memorypalace\"> input (pass its chat_id + message_id). You can ALSO use it proactively at any time to message a conversation without a preceding <channel> — just pass that conversation's chat_id (omit message_id). The message appears as a new message from you.",
      inputSchema: {
        type: "object",
        properties: {
          chat_id: {
            type: "string",
            description: "The chat_id from the <channel> tag",
          },
          message_id: {
            type: "string",
            description: "The message_id from the <channel> tag. Pass it back verbatim so the reply is matched to the exact message (prevents stale replies being mis-routed).",
          },
          content: {
            type: "string",
            description: "Your reply text",
          },
          file_path: {
            type: "string",
            description: "Absolute path of a file to send to the user alongside the reply (image or any file, max 10 MB).",
          },
          thinking: {
            type: "string",
            description: "If you have internal reasoning or a thinking process for this reply, include it here. This will be displayed as a collapsible thinking block in the app.",
          },
        },
        required: ["chat_id", "content"],
      },
    },
    ...PROXY_TOOLS,
  ],
}))

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  // Gateway 工具代理：转发到 Gateway 执行，结果作为文本返回。
  if (PROXY_TOOL_NAMES.has(req.params.name)) {
    const text = await proxyToGateway(req.params.name, req.params.arguments ?? {})
    // see_screen 等返回图片的工具：__peek_image__ 结构 → MCP image content（CC 亲眼看原图）
    if (typeof text === "string" && text.includes("__peek_image__")) {
      try {
        const pk = JSON.parse(text)
        if (pk && pk.__peek_image__ && pk.data) {
          return { content: [
            { type: "image", data: pk.data, mimeType: pk.media_type || "image/png" },
            { type: "text", text: `用户当前 iPhone 屏幕截图 · App: ${pk.app || "未知"}` },
          ] }
        }
      } catch {}
    }
    return { content: [{ type: "text", text }] }
  }

  if (req.params.name !== "reply") {
    throw new Error(`unknown tool: ${req.params.name}`)
  }
  const args = req.params.arguments as { chat_id: string; message_id?: string; content: string; file_path?: string; thinking?: string }
  // 如果 hub 这一刻断了，等一次重连尝试（最多 retry 几次再放弃）
  let lastErr: Error | undefined
  for (let i = 0; i < 3; i++) {
    try {
      const ws = await connectHub()
      const payload: Record<string, unknown> = {
        type: "reply",
        chat_id: args.chat_id,
        message_id: args.message_id,  // 可选，回带用于精确匹配
        content: args.content,
      }
      if (args.file_path) payload.file_path = args.file_path
      if (args.thinking) payload.thinking = args.thinking
      ws.send(JSON.stringify(payload))
      return { content: [{ type: "text", text: "ok" }] }
    } catch (err) {
      lastErr = err as Error
      await new Promise(r => setTimeout(r, 500 * (i + 1)))
    }
  }
  throw new Error(`hub unreachable after retries: ${lastErr?.message ?? "unknown"}`)
})

// 启动时立刻连 hub（不等第一次 reply tool call 才 lazy connect）
// hub 没起时 fail 后自动 backoff 重连，不阻塞 stdio
connectHub().catch(() => scheduleReconnect())

const transport = new StdioServerTransport()
await server.connect(transport)

#!/usr/bin/env bun
import { Server } from "@modelcontextprotocol/sdk/server/index.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js"
import { WebSocket } from "ws"

const HUB_URL = process.env.MP_CC_HUB_URL ?? "ws://127.0.0.1:7890/mcp"
const PING_INTERVAL_MS = 15_000

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
    const ws = new WebSocket(HUB_URL)
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
  tools: [{
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
        // TODO: Phase 4 — file_path for sending files/images back to user
      },
      required: ["chat_id", "content"],
    },
  }],
}))

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name !== "reply") {
    throw new Error(`unknown tool: ${req.params.name}`)
  }
  const args = req.params.arguments as { chat_id: string; message_id?: string; content: string }
  // 如果 hub 这一刻断了，等一次重连尝试（最多 retry 几次再放弃）
  let lastErr: Error | undefined
  for (let i = 0; i < 3; i++) {
    try {
      const ws = await connectHub()
      ws.send(JSON.stringify({
        type: "reply",
        chat_id: args.chat_id,
        message_id: args.message_id,  // 可选，回带用于精确匹配
        content: args.content,
      }))
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

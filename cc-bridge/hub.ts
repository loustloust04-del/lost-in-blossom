import { WebSocketServer, WebSocket } from "ws"
import { execFileSync } from "node:child_process"

const PORT = 7890
const TMUX_SESSION = process.env.MP_CC_TMUX_SESSION ?? "mp-cc"

export interface MPMessage {
  type: "send"
  chat_id: string
  message_id: string
  content: string
  user: string
}

interface MPAck {
  type: "ack"
  message_id: string
}

export function buildChannelTag(msg: MPMessage, ts: string): string {
  const safe = msg.content.replace(/\n/g, " ")
  return `<channel source="memorypalace" chat_id="${msg.chat_id}" message_id="${msg.message_id}" user="${msg.user}" ts="${ts}">${safe}</channel>`
}

export interface TmuxRunner {
  send(text: string): void
}

export const realTmuxRunner: TmuxRunner = {
  send(text: string) {
    execFileSync("tmux", ["send-keys", "-t", TMUX_SESSION, "-l", text])
    execFileSync("tmux", ["send-keys", "-t", TMUX_SESSION, "Enter"])
  }
}

let tmux: TmuxRunner = process.env.MP_CC_TMUX_DRY_RUN ? { send: () => {} } : realTmuxRunner
export function setTmuxRunner(runner: TmuxRunner) { tmux = runner }

// MP 客户端集合（/cc 路径连接的 MP 客户端）
const mpClients = new Set<WebSocket>()
// MCP 客户端集合（/mcp 路径连接的 MCP server）
const mcpClients = new Set<WebSocket>()

export function startHub(): WebSocketServer {
  const wss = new WebSocketServer({ host: "127.0.0.1", port: PORT })

  wss.on("connection", (ws, req) => {
    if (req.url === "/cc") {
      mpClients.add(ws)
      console.log(`[hub] MP connected (total ${mpClients.size})`)

      ws.on("message", (raw) => {
        let msg: MPMessage
        try {
          msg = JSON.parse(raw.toString())
        } catch {
          ws.send(JSON.stringify({ type: "error", reason: "invalid_json" }))
          return
        }

        if (msg.type === "send") {
          try {
            const ts = new Date().toISOString()
            const tag = buildChannelTag(msg, ts)
            tmux.send(tag)
            ws.send(JSON.stringify({ type: "ack", message_id: msg.message_id }))
          } catch (err: any) {
            ws.send(JSON.stringify({
              type: "error",
              message_id: msg.message_id,
              reason: `tmux: ${err.message}`,
            }))
          }
        }
      })

      ws.on("close", () => {
        mpClients.delete(ws)
        console.log(`[hub] MP disconnected (total ${mpClients.size})`)
      })
    } else if (req.url === "/mcp") {
      mcpClients.add(ws)
      console.log(`[hub] MCP connected (total ${mcpClients.size})`)

      ws.on("message", (raw) => {
        let msg: any
        try { msg = JSON.parse(raw.toString()) } catch { return }

        if (msg.type === "reply" && typeof msg.chat_id === "string" && typeof msg.content === "string") {
          const payload = JSON.stringify({
            type: "reply",
            chat_id: msg.chat_id,
            content: msg.content,
          })
          for (const mp of mpClients) {
            if (mp.readyState === mp.OPEN) {
              try { mp.send(payload) } catch { /* 死 socket，等 close 事件清理 */ }
            }
          }
        } else if (msg.type === "tool_event" && typeof msg.chat_id === "string") {
          // 转发 tool_event 给所有 MP 客户端，让 iOS 渲染 ToolCallCardView
          const payload = JSON.stringify({
            type: "tool_event",
            chat_id: msg.chat_id,
            tool_name: msg.tool_name ?? "",
            input_json: msg.input_json ?? "{}",
            result: msg.result ?? "",
          })
          for (const mp of mpClients) {
            if (mp.readyState === mp.OPEN) {
              try { mp.send(payload) } catch { /* 死 socket，等 close 事件清理 */ }
            }
          }
        }
      })

      ws.on("close", () => {
        mcpClients.delete(ws)
        console.log(`[hub] MCP disconnected (total ${mcpClients.size})`)
      })
    } else {
      ws.close(1008, "unknown path")
    }
  })

  console.log(`[hub] listening on ws://127.0.0.1:${PORT}/cc and /mcp`)
  return wss
}

// Auto-start only when this file is the entry point (bun run hub.ts)
if (import.meta.main) {
  startHub()
}

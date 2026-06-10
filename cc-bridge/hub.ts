import { WebSocketServer, WebSocket } from "ws"
import { execFileSync, spawn } from "node:child_process"
import type { ChildProcessWithoutNullStreams } from "node:child_process"
import { mkdtempSync, unlinkSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const PORT = Number(process.env.MP_CC_HUB_PORT) || 7890
const TMUX_SESSION = process.env.MP_CC_TMUX_SESSION ?? "mp-cc"
const HUB_HOST = process.env.MP_CC_HUB_HOST ?? "127.0.0.1"
const HUB_TOKEN = process.env.MP_CC_HUB_TOKEN

export function isLoopback(addr: string | undefined): boolean {
  if (!addr) return false
  return addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1"
}

// App→Hub message (type "chat" preferred; "send" accepted for backward compat)
export interface ChatMessage {
  type: "chat" | "send"
  chat_id: string
  message_id: string
  content: string
  user?: string
  session_name?: string  // route to specific tmux session; defaults to TMUX_SESSION
}

export function buildChannelTag(msg: ChatMessage, ts: string): string {
  let safe = msg.content.replace(/\n/g, " ")
  // 防御：超长 content 让 tmux send-keys -l 失败。截断到安全长度。
  if (safe.length > 4000) safe = safe.slice(0, 4000) + " …[截断]"
  const user = msg.user ?? "user"
  return `<channel source="memorypalace" chat_id="${msg.chat_id}" message_id="${msg.message_id}" user="${user}" ts="${ts}">${safe}</channel>`
}

// ── tmux helpers ──────────────────────────────────────────────────────────────
// execFileSync 不走 shell，避免 shell 转义问题（特殊字符/中文）

export interface TmuxRunner {
  send(text: string, session: string): void
  hasSession(session: string): boolean
  list(): string[]
  spawn(session: string, cwd: string, mcpConfigPath: string): void
}

export const realTmuxRunner: TmuxRunner = {
  send(text: string, session: string) {
    execFileSync("tmux", ["send-keys", "-t", session, "-l", text])
    execFileSync("tmux", ["send-keys", "-t", session, "Enter"])
  },
  hasSession(session: string): boolean {
    try {
      execFileSync("tmux", ["has-session", "-t", session], { stdio: "ignore" })
      return true
    } catch { return false }
  },
  list(): string[] {
    try {
      const raw = execFileSync("tmux", ["ls", "-F", "#{session_name}"], { encoding: "utf-8" })
      return raw.split("\n").filter(s => s)
    } catch {
      return []  // tmux ls 在无 session 时 exit 1
    }
  },
  spawn(session: string, cwd: string, mcpConfigPath: string) {
    execFileSync("tmux", [
      "new-session", "-d",
      "-s", session,
      "-c", cwd,
      `claude --continue --dangerously-skip-permissions --mcp-config '${mcpConfigPath}'`,
    ])
  },
}

// DRY_RUN: 测试用，所有 tmux 调用 noop
export const dryRunRunner: TmuxRunner = {
  send: () => {},
  hasSession: () => true,
  list: () => [],
  spawn: () => {},
}

let tmux: TmuxRunner = process.env.MP_CC_TMUX_DRY_RUN ? dryRunRunner : realTmuxRunner
export function setTmuxRunner(runner: TmuxRunner) { tmux = runner }

// ── App clients (/ws) + MCP clients (/mcp) ───────────────────────────────────
const appClients = new Set<WebSocket>()
const mcpClients = new Set<WebSocket>()

// 60s reply buffer — replay to App clients that reconnect mid-reply
interface BufferedReply {
  chat_id: string
  message_id?: string
  content: string
  reply_id: string
  ts: number
}
const REPLY_BUFFER_TTL_MS = 60_000
const recentReplies: BufferedReply[] = []

// ── Terminal attachment (Phase 2) ─────────────────────────────────────────────
export interface TerminalAttachment {
  sessionName: string
  fifoPath: string
  catProc: ChildProcessWithoutNullStreams
  mpClients: Set<WebSocket>
}

const terminalAttachments = new Map<string, TerminalAttachment>()
const resizeDebounce = new Map<string, ReturnType<typeof setTimeout>>()

// ── Focus tracking (Phase 3) ──────────────────────────────────────────────────
// Maps each App WebSocket to the chat_id it currently has open (null = backgrounded).
// Used to decide: if no client is watching a chat, push an APNs notification.
const focusByClient = new Map<WebSocket, string | null>()

function createTerminalAttachment(sessionName: string): TerminalAttachment {
  const fifoDir = mkdtempSync(join(tmpdir(), "cc-bridge-"))
  const fifoPath = join(fifoDir, "pane.pipe")
  execFileSync("mkfifo", [fifoPath])
  execFileSync("tmux", ["pipe-pane", "-t", sessionName, "-o", `cat > ${fifoPath}`])
  const catProc = spawn("cat", [fifoPath])
  const att: TerminalAttachment = { sessionName, fifoPath, catProc, mpClients: new Set() }
  catProc.stdout.on("data", (chunk: Buffer) => {
    const payload = JSON.stringify({
      type: "terminal_chunk",
      session_name: sessionName,
      bytes: chunk.toString("base64"),
    })
    for (const c of att.mpClients) {
      if (c.readyState === c.OPEN) {
        try { c.send(payload) } catch {}
      }
    }
  })
  catProc.on("exit", () => {
    console.log(`[hub] terminal cat exited for ${sessionName}`)
    closeTerminalAttachment(sessionName)
  })
  terminalAttachments.set(sessionName, att)
  return att
}

function closeTerminalAttachment(sessionName: string): void {
  const att = terminalAttachments.get(sessionName)
  if (!att) return
  try { execFileSync("tmux", ["pipe-pane", "-t", sessionName]) } catch {}
  try { att.catProc.kill() } catch {}
  try { unlinkSync(att.fifoPath) } catch {}
  terminalAttachments.delete(sessionName)
}

function pruneReplyBuffer(): void {
  const cutoff = Date.now() - REPLY_BUFFER_TTL_MS
  while (recentReplies.length > 0 && recentReplies[0].ts < cutoff) {
    recentReplies.shift()
  }
}

export function startHub(): WebSocketServer {
  if (!HUB_TOKEN) {
    console.error("[hub] MP_CC_HUB_TOKEN env required (use start_hub.sh)")
    process.exit(1)
  }

  const wss = new WebSocketServer({ host: HUB_HOST, port: PORT })

  wss.on("connection", (ws, req) => {
    const reqUrl = new URL(req.url ?? "", "http://localhost")
    const pathname = reqUrl.pathname
    const remote = req.socket.remoteAddress

    // Auth: non-loopback connections must supply correct token
    if (!isLoopback(remote)) {
      const provided = reqUrl.searchParams.get("token")
      if (provided !== HUB_TOKEN) {
        console.warn(`[hub] auth failed from ${remote} (path=${pathname})`)
        ws.close(1008, "auth")
        return
      }
    }

    if (pathname === "/ws") {
      // ── App client ──────────────────────────────────────────────────────────
      appClients.add(ws)
      console.log(`[hub] App connected (total ${appClients.size}) from ${remote}`)

      // Replay recent replies so reconnecting clients don't miss anything
      pruneReplyBuffer()
      for (const r of recentReplies) {
        try {
          ws.send(JSON.stringify({
            type: "reply",
            chat_id: r.chat_id,
            message_id: r.message_id,
            content: r.content,
            reply_id: r.reply_id,
          }))
        } catch { /* dead socket, will get cleaned up on close */ }
      }

      ws.on("message", (raw) => {
        let msg: any
        try { msg = JSON.parse(raw.toString()) } catch {
          ws.send(JSON.stringify({ type: "error", reason: "invalid_json" }))
          return
        }

        // ── Chat → tmux send-keys ──────────────────────────────────────────────
        if (msg.type === "chat" || msg.type === "send") {
          const targetSession = (typeof msg.session_name === "string" && msg.session_name)
            ? msg.session_name
            : TMUX_SESSION
          if (!tmux.hasSession(targetSession)) {
            ws.send(JSON.stringify({
              type: "error",
              message_id: msg.message_id,
              reason: `session_not_found: ${targetSession}`,
            }))
            return
          }
          try {
            const ts = new Date().toISOString()
            const tag = buildChannelTag(msg as ChatMessage, ts)
            tmux.send(tag, targetSession)
            console.log(`[hub] chat → tmux:${targetSession} chat_id=${String(msg.chat_id ?? "").slice(0, 8)} "${String(msg.content ?? "").slice(0, 60)}"`)
            ws.send(JSON.stringify({ type: "ack", message_id: msg.message_id }))
          } catch (err: any) {
            ws.send(JSON.stringify({
              type: "error",
              message_id: msg.message_id,
              reason: `tmux: ${err?.message ?? "unknown"}`,
            }))
          }
        }

        // ── Spawn CC session ──────────────────────────────────────────────────
        else if (msg.type === "spawn_cc") {
          const sessionName = typeof msg.session_name === "string" ? msg.session_name : ""
          if (!/^[A-Za-z0-9_.-]{1,32}$/.test(sessionName)) {
            ws.send(JSON.stringify({ type: "spawn_cc_err", session_name: sessionName, reason: "invalid_name" }))
            return
          }
          if (tmux.hasSession(sessionName)) {
            ws.send(JSON.stringify({ type: "spawn_cc_err", session_name: sessionName, reason: "session_exists" }))
            return
          }
          const cwd = process.env.MP_CC_WORKDIR ?? `${process.env.HOME}/Desktop/cc-rp`
          const mcpConfigPath = `${process.cwd()}/.mcp.json`
          try {
            tmux.spawn(sessionName, cwd, mcpConfigPath)
            ws.send(JSON.stringify({ type: "spawn_cc_ok", session_name: sessionName }))
            console.log(`[hub] spawned tmux:${sessionName} cwd=${cwd}`)
          } catch (err: any) {
            ws.send(JSON.stringify({
              type: "spawn_cc_err",
              session_name: sessionName,
              reason: err?.message ?? "spawn failed",
            }))
          }
        }

        // ── List CC sessions ──────────────────────────────────────────────────
        else if (msg.type === "list_sessions") {
          const sessions = tmux.list().filter(s => s.startsWith("mp-cc"))
          ws.send(JSON.stringify({ type: "list_sessions_result", sessions }))
        }

        // ── Terminal attach ───────────────────────────────────────────────────
        else if (msg.type === "terminal_attach") {
          const sessionName = typeof msg.session_name === "string" ? msg.session_name : TMUX_SESSION
          let att = terminalAttachments.get(sessionName)
          if (!att) {
            try {
              att = createTerminalAttachment(sessionName)
            } catch (err: any) {
              ws.send(JSON.stringify({ type: "error", reason: `terminal_attach: ${err?.message ?? "unknown"}` }))
              return
            }
          }
          att.mpClients.add(ws)
          // Send current screen snapshot to the newly attached client
          try {
            const snapshot = execFileSync("tmux", ["capture-pane", "-p", "-e", "-t", sessionName], { encoding: "utf-8" })
            ws.send(JSON.stringify({ type: "terminal_init", session_name: sessionName, snapshot }))
          } catch { /* no snapshot if session gone */ }
          console.log(`[hub] terminal_attach session=${sessionName} clients=${att.mpClients.size}`)
        }

        // ── Terminal detach ───────────────────────────────────────────────────
        else if (msg.type === "terminal_detach") {
          for (const [sessionName, att] of terminalAttachments) {
            if (att.mpClients.has(ws)) {
              att.mpClients.delete(ws)
              console.log(`[hub] terminal_detach session=${sessionName} clients=${att.mpClients.size}`)
              if (att.mpClients.size === 0) {
                closeTerminalAttachment(sessionName)
              }
            }
          }
        }

        // ── Terminal input ────────────────────────────────────────────────────
        else if (msg.type === "terminal_input") {
          const sessionName = typeof msg.session_name === "string" ? msg.session_name : TMUX_SESSION
          if (typeof msg.data === "string" && msg.data.length > 0) {
            try {
              execFileSync("tmux", ["send-keys", "-t", sessionName, "-l", msg.data])
            } catch (err: any) {
              ws.send(JSON.stringify({ type: "error", reason: `terminal_input: ${err?.message ?? "unknown"}` }))
            }
          }
        }

        // ── Terminal resize ───────────────────────────────────────────────────
        else if (msg.type === "terminal_resize") {
          const sessionName = typeof msg.session_name === "string" ? msg.session_name : TMUX_SESSION
          const cols = typeof msg.cols === "number" ? msg.cols : 0
          const rows = typeof msg.rows === "number" ? msg.rows : 0
          if (cols > 0 && rows > 0) {
            const existing = resizeDebounce.get(sessionName)
            if (existing) clearTimeout(existing)
            const t = setTimeout(() => {
              resizeDebounce.delete(sessionName)
              try {
                execFileSync("tmux", ["resize-window", "-t", sessionName, "-x", String(cols), "-y", String(rows)])
                try {
                  const snapshot = execFileSync("tmux", ["capture-pane", "-p", "-e", "-t", sessionName], { encoding: "utf-8" })
                  const att = terminalAttachments.get(sessionName)
                  if (att) {
                    const payload = JSON.stringify({ type: "terminal_init", session_name: sessionName, snapshot })
                    for (const c of att.mpClients) {
                      if (c.readyState === c.OPEN) try { c.send(payload) } catch {}
                    }
                  }
                } catch {}
              } catch (err: any) {
                console.warn(`[hub] resize failed: ${err?.message}`)
              }
            }, 200)
            resizeDebounce.set(sessionName, t)
          }
        }

        // ── Focus / blur ──────────────────────────────────────────────────────
        else if (msg.type === "focus") {
          const chatId = typeof msg.chat_id === "string" ? msg.chat_id : null
          focusByClient.set(ws, chatId)
        }

        else if (msg.type === "blur") {
          focusByClient.set(ws, null)
        }
      })

      ws.on("close", (code) => {
        appClients.delete(ws)
        focusByClient.delete(ws)
        console.log(`[hub] App disconnected (total ${appClients.size}) code=${code}`)
        // Clean up terminal attachments for this client
        for (const [sessionName, att] of terminalAttachments) {
          if (att.mpClients.has(ws)) {
            att.mpClients.delete(ws)
            if (att.mpClients.size === 0) {
              closeTerminalAttachment(sessionName)
            }
          }
        }
      })

    } else if (pathname === "/mcp") {
      // ── MCP Server client ───────────────────────────────────────────────────
      mcpClients.add(ws)
      console.log(`[hub] MCP connected (total ${mcpClients.size})`)

      ws.on("message", (raw) => {
        let msg: any
        try { msg = JSON.parse(raw.toString()) } catch { return }

        if (msg.type === "reply" && typeof msg.chat_id === "string" && typeof msg.content === "string") {
          const reply_id = crypto.randomUUID()
          const payload = JSON.stringify({
            type: "reply",
            chat_id: msg.chat_id,
            message_id: msg.message_id,  // echo back for precise matching on App side
            content: msg.content,
            reply_id,
          })
          // Buffer for reconnect replay
          pruneReplyBuffer()
          recentReplies.push({
            chat_id: msg.chat_id,
            message_id: msg.message_id,
            content: msg.content,
            reply_id,
            ts: Date.now(),
          })
          // Broadcast to all connected App clients
          let count = 0
          for (const app of appClients) {
            if (app.readyState === WebSocket.OPEN) {
              try { app.send(payload); count++ } catch { /* dead, wait for close */ }
            }
          }
          // Focus check: if no client is watching this chat → push notification needed
          const isFocused = [...focusByClient.values()].some(id => id === msg.chat_id)
          console.log(`[hub] reply ← mcp → broadcast to ${count}/${appClients.size} App clients chat_id=${String(msg.chat_id).slice(0, 8)} focused=${isFocused}`)
          if (!isFocused) {
            // TODO: Phase 3.2 — sendPush(deviceToken, title, body) when not focused
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

  console.log(`[hub] listening on ws://${HUB_HOST}:${PORT}  /ws = App  /mcp = MCP`)
  return wss
}

// Auto-start only when this file is the entry point (bun run hub.ts)
if (import.meta.main) {
  startHub()
}

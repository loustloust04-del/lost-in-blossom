import { WebSocketServer, WebSocket } from "ws"
import { createServer } from "node:http"
import { getStatus, forge, startAutoForge } from "./session-manager.ts"
import { execFileSync, spawn } from "node:child_process"
import type { ChildProcessWithoutNullStreams } from "node:child_process"
import { mkdtempSync, unlinkSync, mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, copyFileSync, statSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, basename, extname } from "node:path"
import { sendPush } from "./apns.ts"

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
  context?: string       // API 会话的 ContextSummarizer 摘要，注入 channel tag 供 CC 接话
}

export function buildChannelTag(msg: ChatMessage, ts: string, attachments: string[] = []): string {
  let safe = msg.content.replace(/\n/g, " ")
  // 防御：超长 content 让 tmux send-keys -l 失败。截断到安全长度。
  if (safe.length > 4000) safe = safe.slice(0, 4000) + " …[截断]"
  // CC↔API 上下文共享（可通过环境变量 CC_INJECT_SUMMARY=0 关闭）
  const injectSummary = (process.env.CC_INJECT_SUMMARY ?? "1") !== "0"
  if (injectSummary && typeof msg.context === "string" && msg.context.trim().length > 0) {
    let ctx = msg.context.replace(/\n/g, " ")
    if (ctx.length > 1500) ctx = ctx.slice(0, 1500) + " …[截断]"
    safe = `〔历史摘要〕${ctx}〔/历史摘要〕 ${safe}`
  }
  if (attachments.length > 0) {
    safe += ` [附件 ${attachments.length} 个，已存到本机，用 Read 工具查看/处理：${attachments.join(" ; ")}]`
  }
  const user = msg.user ?? "user"
  const attrsExtra = attachments.length > 0 ? ` attachments="${attachments.join(";")}"` : ""
  return `<channel source="memorypalace" chat_id="${msg.chat_id}" message_id="${msg.message_id}" user="${user}" ts="${ts}"${attrsExtra}>${safe}</channel>`
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

// Maps each App WebSocket to its APNs device token (registered via register_device).
// Track which clients are backgrounded (should receive push instead of WS).
const backgroundedClients = new Set<WebSocket>()
const deviceTokenByClient = new Map<WebSocket, string>()

// Persistent device tokens (token → last-seen ms). iOS suspends the WebSocket on
// background — exactly when push is needed — so token lifetime must NOT be tied
// to the connection. Survives WS close and hub restart.
const DEVICE_TOKENS_PATH = join(process.cwd(), "cc-bridge", "device-tokens.json")

function loadDeviceTokens(): [string, number][] {
  try {
    if (!existsSync(DEVICE_TOKENS_PATH)) return []
    return Object.entries(JSON.parse(readFileSync(DEVICE_TOKENS_PATH, "utf-8")) as Record<string, number>)
  } catch { return [] }
}

function saveDeviceTokens(): void {
  try {
    writeFileSync(DEVICE_TOKENS_PATH, JSON.stringify(Object.fromEntries(knownDeviceTokens), null, 2), "utf-8")
  } catch (err: any) {
    console.warn(`[hub] saveDeviceTokens failed: ${err?.message}`)
  }
}

const knownDeviceTokens = new Map<string, number>(loadDeviceTokens())
if (knownDeviceTokens.size > 0) console.log(`[hub] loaded ${knownDeviceTokens.size} persisted device token(s)`)

// ── Offline message durability (Phase 4.1) ────────────────────────────────────

interface OfflineMessage {
  content: string
  message_id?: string
  reply_id: string
  timestamp: string
}

const OFFLINE_DIR = join(process.cwd(), "cc-bridge", "offline")
const OFFLINE_MAX = 50

function offlinePath(chatId: string): string {
  return join(OFFLINE_DIR, `${chatId}.json`)
}

function loadOffline(chatId: string): OfflineMessage[] {
  try {
    const path = offlinePath(chatId)
    if (!existsSync(path)) return []
    return JSON.parse(readFileSync(path, "utf-8")) as OfflineMessage[]
  } catch { return [] }
}

function saveOffline(chatId: string, messages: OfflineMessage[]): void {
  try {
    mkdirSync(OFFLINE_DIR, { recursive: true })
    writeFileSync(offlinePath(chatId), JSON.stringify(messages, null, 2), "utf-8")
  } catch (err: any) {
    console.warn(`[hub] saveOffline failed chat_id=${chatId}: ${err?.message}`)
  }
}

function appendOffline(chatId: string, msg: OfflineMessage): void {
  const messages = loadOffline(chatId)
  messages.push(msg)
  // Keep at most OFFLINE_MAX most-recent messages
  if (messages.length > OFFLINE_MAX) messages.splice(0, messages.length - OFFLINE_MAX)
  saveOffline(chatId, messages)
}

function clearOffline(chatId: string): void {
  try {
    const path = offlinePath(chatId)
    if (existsSync(path)) unlinkSync(path)
  } catch { /* ignore */ }
}

// ── Inbound file handling — user→CC (Phase 4.2) ───────────────────────────────

const INBOUND_DIR = join(process.cwd(), "inbound")
const MAX_FILE_BYTES = 10 * 1024 * 1024  // 10 MB

function mimeToExt(mime?: string): string {
  switch (mime) {
    case "image/png":  return "png"
    case "image/gif":  return "gif"
    case "image/webp": return "webp"
    case "image/heic": return "heic"
    default:           return "jpg"
  }
}

function extToMime(ext: string): string {
  switch (ext.toLowerCase().replace(/^\./, "")) {
    case "jpg": case "jpeg": return "image/jpeg"
    case "png":  return "image/png"
    case "gif":  return "image/gif"
    case "webp": return "image/webp"
    case "heic": return "image/heic"
    case "pdf":  return "application/pdf"
    case "txt": case "md": case "log": case "csv": return "text/plain"
    case "json": return "application/json"
    case "zip":  return "application/zip"
    case "html": case "htm": return "text/html"
    default:     return "application/octet-stream"
  }
}

function isImageMime(mime: string): boolean {
  return mime.startsWith("image/")
}

// S4: 消毒 chatId，避免 ../ 路径穿越逃出 inbound/outbound 目录
function safeChatSeg(chatId: string): string {
  const seg = (chatId || "").replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 16)
  return seg.length > 0 ? seg : "default"
}

function saveInboundImages(chatId: string, images: any[]): string[] {
  const dir = join(INBOUND_DIR, safeChatSeg(chatId))
  const paths: string[] = []
  try { mkdirSync(dir, { recursive: true }) } catch {}
  let i = 0
  for (const img of images) {
    if (typeof img?.b64 !== "string") continue
    const buf = Buffer.from(img.b64, "base64")
    if (buf.length === 0 || buf.length > MAX_FILE_BYTES) continue
    const p = join(dir, `${Date.now()}_${i}.${mimeToExt(img.mime)}`)
    try { writeFileSync(p, buf); paths.push(p); i++ }
    catch (e: any) { console.warn(`[hub] saveInboundImage fail: ${e.message}`) }
  }
  return paths
}

function saveInboundFiles(chatId: string, files: any[]): string[] {
  const dir = join(INBOUND_DIR, safeChatSeg(chatId))
  const paths: string[] = []
  try { mkdirSync(dir, { recursive: true }) } catch {}
  let i = 0
  for (const f of files) {
    if (typeof f?.b64 !== "string") continue
    const buf = Buffer.from(f.b64, "base64")
    if (buf.length === 0 || buf.length > MAX_FILE_BYTES) continue
    const rawName = typeof f.name === "string" && f.name ? f.name : `file_${i}`
    const safeName = rawName.replace(/[/\\'"]/g, "_")
    const p = join(dir, `${Date.now()}_${i}_${safeName}`)
    try { writeFileSync(p, buf); paths.push(p); i++ }
    catch (e: any) { console.warn(`[hub] saveInboundFile fail: ${e.message}`) }
  }
  return paths
}

// ── Outbound file staging — CC→user (Phase 4.2) ──────────────────────────────

const OUTBOUND_DIR = join(process.cwd(), "outbound")

interface StagedFile {
  name: string
  mime: string
  data_base64: string
  isImage: boolean
}

function stageOutboundFile(chatId: string, srcPath: string): StagedFile | null {
  try {
    if (!existsSync(srcPath)) {
      console.warn(`[hub] outbound file not found: ${srcPath}`)
      return null
    }
    const size = statSync(srcPath).size
    if (size === 0 || size > MAX_FILE_BYTES) {
      console.warn(`[hub] outbound file size out of range (${size}): ${srcPath}`)
      return null
    }
    // Stage a copy in outbound dir for audit / replay safety
    const dir = join(OUTBOUND_DIR, safeChatSeg(chatId))
    try { mkdirSync(dir, { recursive: true }) } catch {}
    const name = basename(srcPath)
    const dest = join(dir, `${Date.now()}_${name}`)
    copyFileSync(srcPath, dest)
    const mime = extToMime(extname(srcPath))
    return {
      name,
      mime,
      data_base64: readFileSync(dest).toString("base64"),
      isImage: isImageMime(mime),
    }
  } catch (e: any) {
    console.warn(`[hub] stageOutboundFile fail: ${e.message}`)
    return null
  }
}

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
  if (HUB_HOST !== "127.0.0.1" && HUB_HOST !== "::1" && HUB_HOST !== "localhost") {
    console.warn(`[hub] WARNING: binding non-loopback host ${HUB_HOST} — hub is reachable from the network; make sure this is intended`)
  }
  // CC Session 续命：HTTP 端点 /cc/status (GET) + /cc/forge (POST)，与 WS 同端口共存。
  const httpServer = createServer(async (req, res) => {
    const u = new URL(req.url ?? "", "http://localhost")
    const token = (req.headers["authorization"]?.replace("Bearer ", "")) || u.searchParams.get("token")
    if (token !== HUB_TOKEN) { res.writeHead(401); res.end("unauthorized"); return }
    const sess = u.searchParams.get("session") || TMUX_SESSION
    if (u.pathname === "/cc/status" && req.method === "GET") {
      res.writeHead(200, { "Content-Type": "application/json" })
      res.end(JSON.stringify(getStatus(sess))); return
    }
    if (u.pathname === "/cc/forge" && req.method === "POST") {
      const result = await forge(sess)
      res.writeHead(result.ok ? 200 : 500, { "Content-Type": "application/json" })
      res.end(JSON.stringify(result)); return
    }
    if (u.pathname === "/cc/settings" && req.method === "GET") {
      res.writeHead(200, { "Content-Type": "application/json" })
      res.end(JSON.stringify({ injectSummary: (process.env.CC_INJECT_SUMMARY ?? "1") !== "0" }))
      return
    }
    if (u.pathname === "/cc/settings" && req.method === "POST") {
      let body = ""
      req.on("data", (c: Buffer) => { body += c.toString() })
      req.on("end", () => {
        try {
          const s = JSON.parse(body)
          if (typeof s.injectSummary === "boolean") process.env.CC_INJECT_SUMMARY = s.injectSummary ? "1" : "0"
          res.writeHead(200, { "Content-Type": "application/json" })
          res.end(JSON.stringify({ ok: true, injectSummary: process.env.CC_INJECT_SUMMARY !== "0" }))
        } catch { res.writeHead(400); res.end("bad json") }
      })
      return
    }
    res.writeHead(404); res.end("not found")
  })
  const wss = new WebSocketServer({ server: httpServer })
  httpServer.listen(PORT, HUB_HOST)
  startAutoForge(TMUX_SESSION)

  wss.on("connection", (ws, req) => {
    const reqUrl = new URL(req.url ?? "", "http://localhost")
    const pathname = reqUrl.pathname
    // 鉴权：所有连接（含 loopback）必须带正确 query token。
    // 部署上 hub 绑 127.0.0.1、由反向代理转发外部流量，此时外部连接的
    // remoteAddress 也是 loopback——若 loopback 免鉴权，token 形同虚设。
    const remote = req.socket.remoteAddress
    const provided = reqUrl.searchParams.get("token")
    if (provided !== HUB_TOKEN) {
      console.warn(`[hub] auth failed from ${remote} (path=${pathname})`)
      ws.close(1008, "auth")
      return
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
        }
 catch { /* dead socket, will get cleaned up on close */ }
      }

      // Replay offline messages persisted while no clients were connected
      try {
        if (existsSync(OFFLINE_DIR)) {
          const files = readdirSync(OFFLINE_DIR).filter(f => f.endsWith(".json"))
          for (const file of files) {
            const chatId = file.replace(/\.json$/, "")
            const messages = loadOffline(chatId)
            let delivered = 0
            for (const m of messages) {
              try {
                ws.send(JSON.stringify({
                  type: "reply",
                  chat_id: chatId,
                  message_id: m.message_id,
                  content: m.content,
                  reply_id: m.reply_id,
                }))
                delivered++
              } catch { break }
            }
            if (delivered > 0) {
              clearOffline(chatId)
              console.log(`[hub] offline replay: ${delivered} messages for chat_id=${chatId.slice(0, 8)}`)
            }
          }
        }
      } catch (err: any) { /* offline dir absent or read failed, skip */ }

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
            // Save any attached images/files to disk; inject paths into channel tag
            const attachments: string[] = []
            if (Array.isArray(msg.images) && msg.images.length > 0) {
              attachments.push(...saveInboundImages(String(msg.chat_id), msg.images))
            }
            if (Array.isArray(msg.files) && msg.files.length > 0) {
              attachments.push(...saveInboundFiles(String(msg.chat_id), msg.files))
            }
            const tag = buildChannelTag(msg as ChatMessage, ts, attachments)
            tmux.send(tag, targetSession)
            console.log(`[hub] chat → tmux:${targetSession} chat_id=${String(msg.chat_id ?? "").slice(0, 8)} attachments=${attachments.length} "${String(msg.content ?? "").slice(0, 60)}"`)
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

        // ── APNs device token registration ────────────────────────────────────
        else if (msg.type === "app_state") {
          const state = typeof msg.state === "string" ? msg.state : ""
          if (state === "background") {
            backgroundedClients.add(ws)
            console.log(`[hub] app_state=background`)
          } else if (state === "foreground") {
            backgroundedClients.delete(ws)
            console.log(`[hub] app_state=foreground`)
          }
        }

        else if (msg.type === "register_device") {
          const token = typeof msg.device_token === "string" ? msg.device_token : ""
          if (token) {
            deviceTokenByClient.set(ws, token)
            knownDeviceTokens.set(token, Date.now())
            saveDeviceTokens()
            console.log(`[hub] register_device token=...${token.slice(-8)} (persisted)`)
          }
        }
      })

      ws.on("close", (code) => {
        appClients.delete(ws)
      backgroundedClients.delete(ws)
        focusByClient.delete(ws)
        deviceTokenByClient.delete(ws)
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
          // Attach outbound file if CC provided a file_path
          let fileField: StagedFile | undefined
          if (typeof msg.file_path === "string" && msg.file_path) {
            fileField = stageOutboundFile(String(msg.chat_id), msg.file_path) ?? undefined
          }
          const replyObj: Record<string, unknown> = {
            type: "reply",
            chat_id: msg.chat_id,
            message_id: msg.message_id,  // echo back for precise matching on App side
            content: msg.content,
            reply_id,
          }
          if (fileField) {
            replyObj.file = {
              name: fileField.name,
              mime: fileField.mime,
              data: fileField.data_base64,
              is_image: fileField.isImage,
            }
          }
          // If CC included thinking, broadcast cc_thinking first (App consumes it before reply)
          if (typeof msg.thinking === "string" && msg.thinking) {
            const thinkingPayload = JSON.stringify({
              type: "cc_thinking",
              thinking: msg.thinking,
              session_id: TMUX_SESSION,
              chat_id: msg.chat_id,
            })
            for (const app of appClients) {
              if (app.readyState === WebSocket.OPEN) {
                try { app.send(thinkingPayload) } catch { /* dead */ }
              }
            }
          }
          const payload = JSON.stringify(replyObj)
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
          let activeCount = 0
          for (const app of appClients) {
            if (app.readyState === WebSocket.OPEN) {
              try { app.send(payload); count++ } catch { /* dead, wait for close */ }
              if (!backgroundedClients.has(app)) activeCount++
            }
          }
          // If no ACTIVE (foreground) App clients, persist for later delivery
          if (activeCount === 0) {
            appendOffline(msg.chat_id, {
              content: msg.content,
              message_id: msg.message_id,
              reply_id,
              timestamp: new Date().toISOString(),
            })
            console.log(`[hub] reply offline-queued chat_id=${String(msg.chat_id).slice(0, 8)}`)
          }
          // Focus check: if no client is watching this chat → push notification needed
          const isFocused = [...focusByClient.values()].some(id => id === msg.chat_id)
          console.log(`[hub] reply ← mcp → broadcast to ${count}/${appClients.size} App clients chat_id=${String(msg.chat_id).slice(0, 8)} focused=${isFocused}`)
          // Push to all known devices. Tokens outlive the WebSocket (iOS kills the
          // socket on background — exactly when push is needed), so iterate the
          // persistent set; skip only devices with a live, foregrounded connection
          // currently focused on this chat.
          for (const token of knownDeviceTokens.keys()) {
            let liveAndFocused = false
            for (const [appWs, t] of deviceTokenByClient) {
              if (t !== token) continue
              if (focusByClient.get(appWs) === msg.chat_id && !backgroundedClients.has(appWs)) {
                liveAndFocused = true
                break
              }
            }
            if (liveAndFocused) continue
            const preview = String(msg.content).slice(0, 100)
            sendPush(token, "MemoryPalace", preview, msg.chat_id).then(result => {
              if (!result.ok) {
                console.warn(`[hub] APNs push failed: ${result.error} (status=${result.status})`)
                // Prune tokens APNs reports as dead so we don't retry them forever.
                if (result.status === 410 || result.error === "Unregistered" || result.error === "BadDeviceToken") {
                  knownDeviceTokens.delete(token)
                  saveDeviceTokens()
                  console.log(`[hub] pruned dead device token ...${token.slice(-8)}`)
                }
              }
              else console.log(`[hub] push sent to ...${token.slice(-8)}`)
            })
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

// TODO: Phase 4.2 — image/file transfer (deferred until writing system + file library ready)

// Auto-start only when this file is the entry point (bun run hub.ts)
if (import.meta.main) {
  startHub()
}

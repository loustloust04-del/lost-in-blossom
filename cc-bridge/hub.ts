import { WebSocketServer, WebSocket } from "ws"
import { createServer } from "node:http"
import { getStatus, forge, startAutoForge } from "./session-manager.ts"
import { execFileSync, spawn } from "node:child_process"
import type { ChildProcessWithoutNullStreams } from "node:child_process"
import { mkdtempSync, unlinkSync, mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, copyFileSync, statSync, renameSync } from "node:fs"
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
  context?: string       // API 会话最近的原始对话（缺省 fallback 摘要），注入 channel tag 供 CC 接话
}

export function buildChannelTag(msg: ChatMessage, ts: string, attachments: string[] = []): string {
  let safe = msg.content.replace(/\n/g, " ")
  // CC↔API 上下文共享（可通过环境变量 CC_INJECT_SUMMARY=0 关闭）
  const injectSummary = (process.env.CC_INJECT_SUMMARY ?? "1") !== "0"
  if (injectSummary && typeof msg.context === "string" && msg.context.trim().length > 0) {
    let ctx = msg.context.replace(/\n/g, " ")
    if (ctx.length > 4000) ctx = ctx.slice(0, 4000) + " …[截断]"
    safe = `〔最近对话〕${ctx}〔/最近对话〕 ${safe}`
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


// ── 门铃排队：她正在输入时不抢输入框 ──────────────────────────────
// tmux 的 send-keys 是往输入框敲字再回车，如果她打到一半，会把她的话一起发出去。
const eventQueue: string[] = []
let queueTimer: ReturnType<typeof setInterval> | null = null

/// 输入框里有没有她没发完的字（读 tmux 最后一屏的提示行）
function inputBusy(session: string): boolean {
  try {
    const out = execFileSync("tmux", ["capture-pane", "-t", session, "-p"], { encoding: "utf-8" })
    const lines = out.split("\n")
    // 提示符行形如 "❯ 内容"；内容非空 = 她正在打字
    for (let i = lines.length - 1; i >= 0 && i >= lines.length - 12; i--) {
      const l = lines[i]
      const m = l.match(/^\s*❯\s*(.*)$/)
      if (m) return m[1].trim().length > 0
    }
  } catch { /* 读不到就当不忙 */ }
  return false
}

function queueEvent(tag: string): void {
  eventQueue.push(tag)
  if (queueTimer) return
  queueTimer = setInterval(() => {
    if (!eventQueue.length) {
      if (queueTimer) { clearInterval(queueTimer); queueTimer = null }
      return
    }
    if (inputBusy(TMUX_SESSION)) return   // 还在打字，继续等
    const tag = eventQueue.shift()!
    try { realTmuxRunner.send(tag, TMUX_SESSION) } catch { /* 下轮再试 */ }
  }, 4000)
}

export const realTmuxRunner: TmuxRunner = {
  send(text: string, session: string) {
    execFileSync("tmux", ["send-keys", "-t", session, "-l", text])
    // ⚠️ 文本已注入输入框——Enter 失败不能外抛：调用方 catch 回 error 帧，
    // app 端会当整体失败重发整条 → 文本注入 tmux 两遍（粟粟"发两遍"雷一的变体）。
    // Enter 抖动最坏结果 = 消息留在输入框等手按，绝不重。注入本身失败仍抛（重发安全）。
    try {
      execFileSync("tmux", ["send-keys", "-t", session, "Enter"])
    } catch (e: any) {
      console.error(`[hub] post-inject Enter 失败（文本已在输入框，不重发）: ${e?.message}`)
    }
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
      `IS_SANDBOX=1 claude --continue --dangerously-skip-permissions --mcp-config '${mcpConfigPath}'`,
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
/// reply 幂等（mcp-server 重试帧带同 mp_msg_id）——Set 插入序即最老在前，超上限剔一批。
/// 导出供测试；生产只经 markReplySeen 使用。
export const seenMpMsgIds = new Set<string>()
export function markReplySeen(mpMsgId: string | undefined): boolean {
  if (!mpMsgId) return false          // 老 CC 不带 id → 不去重（容旧，宁重勿丢由 app 端兜）
  if (seenMpMsgIds.has(mpMsgId)) return true
  seenMpMsgIds.add(mpMsgId)
  if (seenMpMsgIds.size > 600) {
    const it = seenMpMsgIds.values()
    for (let i = 0; i < 100; i++) { const v = it.next(); if (!v.done) seenMpMsgIds.delete(v.value) }
  }
  return false
}

// ── Terminal attachment (Phase 2) ─────────────────────────────────────────────
export interface TerminalAttachment {
  sessionName: string
  fifoPath: string
  catProc: ChildProcessWithoutNullStreams
  mpClients: Set<WebSocket>
  teardownTimer?: ReturnType<typeof setTimeout>
}

const TERMINAL_GRACE_MS = 30_000  // keep pipe alive 30s after last client disconnects

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

// ── 共读：App 推来的「她正在读的这一章」──────────────────────────────
// App 早就在推 reading_context，但 hub 从来没接过（线断在中间）。
// 存成单文件而非追加：Caelum 关心的永远是"她现在读到哪"，历史无意义。
// ⚠️ 原为 join(process.cwd(), "cc-bridge", ...)——hub 本来就跑在 cc-bridge 目录里，
// 于是写到了 cc-bridge/cc-bridge/ 下，而 mcp-server 去 cc-bridge/ 找，永远读不到。
// 兔兔实测「PDF 推上去了但他看不到」就是这个：内容一直在，只是写错了地方。
const READING_PATH = process.env.MP_CC_BRIDGE_DIR
  ? join(process.env.MP_CC_BRIDGE_DIR, "reading-context.json")
  : "/root/projects/BunnyPalace/cc-bridge/reading-context.json"

function saveReadingContext(m: any): void {
  try {
    mkdirSync(join(process.cwd(), "cc-bridge"), { recursive: true })
    const payload = {
      bookName: String(m.bookName ?? m.safeName ?? "").slice(0, 200),
      chapter: Number(m.chapter ?? 0),
      totalChapters: Number(m.totalChapters ?? 0),
      chapterTitle: String(m.chapterTitle ?? "").slice(0, 200),
      text: String(m.text ?? "").slice(0, 60_000),
      userNotes: String(m.userNotes ?? "").slice(0, 8_000),
      userName: String(m.userName ?? "兔兔").slice(0, 40),
      updatedAt: new Date().toISOString(),
    }
    writeFileSync(READING_PATH, JSON.stringify(payload, null, 2), "utf-8")
    // 让预读台账知道她追到哪了（他好知道自己领先多少章）
    try {
      const bookName = payload.bookName
      const chapter = payload.chapter
      if (bookName && chapter) {
        fetch("http://127.0.0.1:4567/api/preread/her-chapter", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ book: bookName, chapter }),
          signal: AbortSignal.timeout(3000),
        }).catch(() => { /* 台账没跟上不影响读书 */ })
      }
    } catch { /* ignore */ }
  } catch (e: any) {
    console.error(`[hub] reading_context 落盘失败: ${e?.message}`)
  }
}
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
    try {
      writeFileSync(p, buf)
      // 注意：图片保存函数，不要加 txt 转码——此前误入的转码段引用了本函数
      // 不存在的 safeName，运行时 ReferenceError 使 paths.push 永远执行不到：
      // 图落盘但 attachments=[]，CC 收不到附件路径提示。
      paths.push(p); i++
    }
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
    try {
      writeFileSync(p, buf)
      // txt文件自动转UTF-8（处理GBK等编码）
      if (safeName.endsWith('.txt') || safeName.endsWith('.md')) {
        try {
          const text = buf.toString('utf-8')
          if (text.includes('�')) {
            // 有乱码，尝试用iconv转码
            const { execSync } = require('child_process')
            // 原为 shell 模板拼 execSync（审查报告 cc-bridge P0 #2）：文件名带单引号即注入。
            // 当前 safeName 过滤了引号所以风险低，但过滤规则一改就漏——改走 execFileSync 不经 shell。
            execFileSync("iconv", ["-f", "GBK", "-t", "UTF-8", p, "-o", `${p}.utf8`])
            renameSync(`${p}.utf8`, p)
            console.log('[hub] converted', safeName, 'from GBK to UTF-8')
          }
        } catch {}
      }
      paths.push(p); i++
    }
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

function spawnCatForAttachment(att: TerminalAttachment): void {
  const catProc = spawn("cat", [att.fifoPath])
  att.catProc = catProc
  catProc.stdout.on("data", (chunk: Buffer) => {
    const payload = JSON.stringify({
      type: "terminal_chunk",
      session_name: att.sessionName,
      bytes: chunk.toString("base64"),
    })
    for (const c of att.mpClients) {
      if (c.readyState === c.OPEN) {
        try { c.send(payload) } catch {}
      }
    }
  })
  catProc.on("exit", (code) => {
    // Auto-restart cat if the attachment still exists (i.e. not intentionally torn down)
    const current = terminalAttachments.get(att.sessionName)
    if (!current || current !== att) return  // attachment was torn down, do nothing
    console.log(`[hub] terminal cat exited (code=${code}) for ${att.sessionName}, auto-restarting`)
    try {
      // Re-wire tmux pipe-pane in case it dropped, then restart cat
      try { execFileSync("tmux", ["pipe-pane", "-t", att.sessionName, "-o", `cat > ${att.fifoPath}`]) } catch {}
      spawnCatForAttachment(att)
    } catch (err: any) {
      console.error(`[hub] cat restart failed for ${att.sessionName}: ${err?.message}`)
    }
  })
}

function createTerminalAttachment(sessionName: string): TerminalAttachment {
  const fifoDir = mkdtempSync(join(tmpdir(), "cc-bridge-"))
  const fifoPath = join(fifoDir, "pane.pipe")
  execFileSync("mkfifo", [fifoPath])
  execFileSync("tmux", ["pipe-pane", "-t", sessionName, "-o", `cat > ${fifoPath}`])
  const att: TerminalAttachment = { sessionName, fifoPath, catProc: null as any, mpClients: new Set() }
  spawnCatForAttachment(att)
  terminalAttachments.set(sessionName, att)
  return att
}

function teardownTerminalAttachment(sessionName: string): void {
  const att = terminalAttachments.get(sessionName)
  if (!att) return
  if (att.teardownTimer) { clearTimeout(att.teardownTimer); att.teardownTimer = undefined }
  terminalAttachments.delete(sessionName)
  try { execFileSync("tmux", ["pipe-pane", "-t", sessionName]) } catch {}
  try { att.catProc.kill() } catch {}
  try { unlinkSync(att.fifoPath) } catch {}
  console.log(`[hub] terminal attachment torn down for ${sessionName}`)
}

/** Schedule teardown after grace period; cancelled if a client re-attaches in time. */
function scheduleTerminalTeardown(sessionName: string): void {
  const att = terminalAttachments.get(sessionName)
  if (!att) return
  if (att.mpClients.size > 0) return  // still has clients, don't schedule
  if (att.teardownTimer) return        // already scheduled
  console.log(`[hub] scheduling terminal teardown for ${sessionName} in ${TERMINAL_GRACE_MS / 1000}s`)
  att.teardownTimer = setTimeout(() => {
    att.teardownTimer = undefined
    if (att.mpClients.size === 0) {
      teardownTerminalAttachment(sessionName)
    }
  }, TERMINAL_GRACE_MS)
}

/** Cancel a pending teardown (called when a client re-attaches). */
function cancelTerminalTeardown(sessionName: string): void {
  const att = terminalAttachments.get(sessionName)
  if (att?.teardownTimer) {
    clearTimeout(att.teardownTimer)
    att.teardownTimer = undefined
    console.log(`[hub] cancelled pending teardown for ${sessionName} (client reconnected)`)
  }
}

function pruneReplyBuffer(): void {
  const cutoff = Date.now() - REPLY_BUFFER_TTL_MS
  while (recentReplies.length > 0 && recentReplies[0].ts < cutoff) {
    recentReplies.shift()
  }
}

/// 笔记本变更 → 广播给所有在线 App，让它自己去重拉 /api/notebook。
/// 刻意不进 recentReplies、不进 offline 队列：这只是一句"去刷新"的口信，
/// 丢了下次进页面照样拉得到最新列表，落盘只会白白撑大 offline 文件。
function broadcastNotebookChanged(path: string, op: string): number {
  const payload = JSON.stringify({ type: "notebook_changed", path, op })
  let count = 0
  for (const app of appClients) {
    if (app.readyState === WebSocket.OPEN) {
      try { app.send(payload); count++ } catch { /* dead, wait for close */ }
    }
  }
  return count
}

// 共读取章：CC 要某章 → 转给 App → App 回 chapter_result → 原样转回 CC（按 req_id 认领）
function requestChapter(m: any): number {
  const payload = JSON.stringify({
    type: "fetch_chapter",
    req_id: String(m.req_id ?? ""),
    book: String(m.book ?? ""),
    chapter: Number(m.chapter ?? 0),
  })
  let n = 0
  for (const app of appClients) {
    if (app.readyState === WebSocket.OPEN) {
      try { app.send(payload); n++ } catch { /* dead */ }
    }
  }
  return n
}

/// Caelum 递来的书页批注 → 广播给 App（阅读器里展示）
function broadcastBookNote(m: any): number {
  const payload = JSON.stringify({
    type: "book_note",
    bookName: String(m.bookName ?? ""),
    chapter: Number(m.chapter ?? 0),
    note: String(m.note ?? "").slice(0, 1000),
    quote: String(m.quote ?? "").slice(0, 500),
    ts: String(m.ts ?? new Date().toISOString()),
  })
  let count = 0
  for (const app of appClients) {
    if (app.readyState === WebSocket.OPEN) {
      try { app.send(payload); count++ } catch { /* dead */ }
    }
  }
  return count
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
    // 笔记本变更通知：gateway 是另一个进程，落盘后 POST 到这里，由 hub 转成 WS 帧。
    // 单独放在 token 校验之前——gateway 手上不一定有 HUB_TOKEN(start_all.sh 只给 hub
    // 和 CC 传)，所以这里额外接受「同机直连」。光看 remoteAddress 不够：nginx :8890 把
    // /cc/ 剥前缀反代到 7890，外部请求进来 remoteAddress 也是回环——但那种请求必带
    // X-Real-IP / X-Forwarded-For，据此把反代来的流量挡在门外。
    if (u.pathname === "/internal/notify" && req.method === "POST") {
      const viaProxy = !!(req.headers["x-real-ip"] || req.headers["x-forwarded-for"])
      const tokenOk = !!HUB_TOKEN && token === HUB_TOKEN
      if (!tokenOk && (viaProxy || !isLoopback(req.socket.remoteAddress))) {
        res.writeHead(403); res.end("forbidden"); return
      }
      let body = ""
      let tooBig = false
      req.on("data", (c: Buffer) => {
        // 一条通知就几十字节，超过 16KB 只可能是恶意/串台流量，直接断开别攒
        if (body.length > 16 * 1024) { tooBig = true; req.destroy(); return }
        body += c.toString()
      })
      req.on("end", () => {
        if (tooBig) return
        let n = 0
        try {
          const m = JSON.parse(body)
          // 只认这一种帧，且字段自己重建——不把外来 JSON 原样转发给 App
          if (m?.type === "notebook_changed") {
            n = broadcastNotebookChanged(String(m.path ?? "").slice(0, 512), String(m.op ?? "write").slice(0, 32))
            console.log(`[hub] notebook_changed ${m.op} ${String(m.path ?? "").slice(0, 60)} → ${n}/${appClients.size} App`)
          } else if (m?.type === "phone_event") {
            // 手机事件（充电开始等）→ 注入 CC 一条 phone 频道消息；CC 自行决定要不要用 reply 跟用户说
            const text = String(m.text ?? "").slice(0, 300)
            if (text) {
              const tag = `<channel source="phone" event="${String(m.event ?? "event").slice(0, 40)}" ts="${new Date().toISOString()}">${text}</channel>`
              try {
                // ⚠️ 兔兔实测：直接 send-keys 会抢输入框——她正打到一半的字被连同门铃一起发出去了，
                // 而且提醒一闪就变成他的输入，她在终端里根本看不见。
                // 改为先检查输入框是否为空：非空就排队等，别踩她的话。
                if (inputBusy(TMUX_SESSION)) {
                  queueEvent(tag)
                  console.log(`[hub] phone_event 排队（她正在输入）: ${text.slice(0, 40)}`)
                } else {
                  realTmuxRunner.send(tag, TMUX_SESSION)
                  console.log(`[hub] phone_event → CC: ${text.slice(0, 60)}`)
                }
                n = 1
              } catch (e: any) {
                console.error(`[hub] phone_event 注入失败: ${e?.message}`)
              }
            }
          }
        } catch { /* 坏 JSON：当没收到，通知本就是可丢的 */ }
        res.writeHead(200, { "Content-Type": "application/json" })
        res.end(JSON.stringify({ ok: true, delivered: n }))
      })
      return
    }
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
  const wss = new WebSocketServer({
    server: httpServer,
    // iPhone 原图 base64 后可达 10-20MB，ws 默认帧上限（实测 5~12MB 之间）会静默断连
    maxPayload: 64 * 1024 * 1024,
  })
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
    // /mcp 原本整个跳过鉴权（审查报告 2026-08-12 cc-bridge P0 #3）：
    // hub 一旦改绑非 loopback，任何人都能连上来注入 reply。
    // 现在 /mcp 也要 token，只有 hub 确实绑在 127.0.0.1 时才免（同机 mcp-server 走这条）。
    const mcpExempt = pathname === "/mcp" && HUB_HOST === "127.0.0.1"
    if (HUB_TOKEN && provided !== HUB_TOKEN && !mcpExempt) {
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
      const replayedIds = new Set<string>()
      for (const r of recentReplies) {
        try {
          ws.send(JSON.stringify({
            type: "reply",
            chat_id: r.chat_id,
            message_id: r.message_id,
            content: r.content,
            reply_id: r.reply_id,
          }))
          replayedIds.add(r.reply_id)
        } catch { /* dead socket, will get cleaned up on close */ }
      }

      // Replay offline messages persisted while no clients were connected
      // (skip any already delivered via the reply buffer to avoid duplicates)
      try {
        if (existsSync(OFFLINE_DIR)) {
          const files = readdirSync(OFFLINE_DIR).filter(f => f.endsWith(".json"))
          for (const file of files) {
            const chatId = file.replace(/\.json$/, "")
            const messages = loadOffline(chatId)
            let delivered = 0
            for (const m of messages) {
              if (replayedIds.has(m.reply_id)) continue
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
            // delivered >= 0 恒真——ws.send 全抛错（0 条投出）也清文件 = 离线消息静默丢失。
            // 改为全部投出才清；部分投递保留文件下次重投，重复由 App 端持久 reply_id 去重挡。
            if (delivered === messages.length) {
              clearOffline(chatId)
              if (delivered > 0) console.log(`[hub] offline replay: ${delivered} messages for chat_id=${chatId.slice(0, 8)}`)
            } else {
              console.warn(`[hub] offline replay partial (${delivered}/${messages.length}) for chat_id=${chatId.slice(0, 8)} — keeping file for retry`)
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
            const rawLen = typeof raw === "string" ? raw.length : (raw as Buffer).length
            // Save any attached images/files to disk; inject paths into channel tag
            const attachments: string[] = []
            if (Array.isArray(msg.images) && msg.images.length > 0) {
              console.log(`[hub] ⚙ images array len=${msg.images.length} frame=${rawLen}B`)
              attachments.push(...saveInboundImages(String(msg.chat_id), msg.images))
            }
            if (Array.isArray(msg.files) && msg.files.length > 0) {
              console.log(`[hub] ⚙ files array len=${msg.files.length} frame=${rawLen}B`)
              attachments.push(...saveInboundFiles(String(msg.chat_id), msg.files))
            }
            const tag = buildChannelTag(msg as ChatMessage, ts, attachments)
            tmux.send(tag, targetSession)
            console.log(`[hub] chat → tmux:${targetSession} chat_id=${String(msg.chat_id ?? "").slice(0, 8)} attachments=${attachments.length} frame=${rawLen}B "${String(msg.content ?? "").slice(0, 60)}"`)
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
          // CC 的家写死为 BunnyBridge（Caelum 主会话所在项目目录）。此前依赖 $HOME 拼接，
          // hub 以精简环境启动时 HOME 缺失 → "undefined/…" → spawn 进错误目录 →
          // --continue 接不上主会话（7/6 失忆事故根因）。
          const cwd = process.env.MP_CC_WORKDIR ?? "/root/projects/BunnyBridge"
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
          if (att) {
            // Reuse existing attachment — cancel any pending teardown
            cancelTerminalTeardown(sessionName)
          } else {
            try {
              att = createTerminalAttachment(sessionName)
            } catch (err: any) {
              ws.send(JSON.stringify({ type: "error", reason: `terminal_attach: ${err?.message ?? "unknown"}` }))
              return
            }
          }
          att.mpClients.add(ws)
          // Always send a fresh screen snapshot so the client sees current state immediately
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
                scheduleTerminalTeardown(sessionName)
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
        else if (msg.type === "choice_answer") {
          const raw = JSON.stringify(msg)
          for (const c of mcpClients) {
            if (c.readyState === WebSocket.OPEN) { try { c.send(raw) } catch {} }
          }
        }

        else if (msg.type === "fetch_chapter") {
          // ⚠️ 同 ask_choice：原本错加在 HTTP /internal/notify 分支里，
          // 而 mcp-server 走 WebSocket —— 所以 read_chapter 一直超时（他根本取不到书）。
          const n = requestChapter(msg)
          console.log(`[hub] 📖 fetch_chapter ${String(msg.book ?? "").slice(0, 20)} 第${msg.chapter}章 → ${n} App`)
        }

        else if (msg.type === "book_note") {
          const n = broadcastBookNote(msg)
          console.log(`[hub] 📖 book_note《${String(msg.bookName ?? "").slice(0, 20)}》第${msg.chapter}章 → ${n}/${appClients.size} App`)
        }

        else if (msg.type === "ask_choice") {
          // ⚠️ 这条原本错加在 HTTP /internal/notify 分支里，而 mcp-server 是走 WebSocket 发的，
          // 两条路接不上 —— 所以卡片永远弹不出来（兔兔实测 ask_choice 一直没反应）。
          const payload = JSON.stringify({
            type: "ask_choice",
            ask_id: String(msg.ask_id ?? ""),
            question: String(msg.question ?? "").slice(0, 500),
            options: (msg.options ?? []).map((o: any) => String(o).slice(0, 100)).slice(0, 6),
            multi: !!msg.multi,
          })
          let n = 0
          for (const app of appClients) {
            if (app.readyState === WebSocket.OPEN) { try { app.send(payload); n++ } catch {} }
          }
          console.log(`[hub] 🗳 ask_choice「${String(msg.question ?? "").slice(0, 30)}」→ ${n} App`)
        }

        else if (msg.type === "chapter_result") {
          // App 把书回来了 → 原样转给等着的 CC（mcp-server 侧按 req_id 认领）
          const raw = JSON.stringify(msg)
          for (const c of mcpClients) {
            if (c.readyState === WebSocket.OPEN) { try { c.send(raw) } catch { /* dead */ } }
          }
        }

        else if (msg.type === "reading_context") {
          saveReadingContext(msg)
          console.log(`[hub] 📖 reading_context: ${String(msg.bookName ?? "").slice(0, 30)} 第${msg.chapter}章`)
        }

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
        // Clean up terminal attachments for this client (grace period before teardown)
        for (const [sessionName, att] of terminalAttachments) {
          if (att.mpClients.has(ws)) {
            att.mpClients.delete(ws)
            if (att.mpClients.size === 0) {
              scheduleTerminalTeardown(sessionName)
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
          // 幂等：mcp-server 的 reply 有 3 次重试（ws.send 抛错≠帧没送达，帧进 OS 缓冲后
          // 连接异常关闭照样抛）——重试帧带同一个 mp_msg_id，这里按它去重。不去重的话
          // 每条重试帧分到新 reply_id，app 端 reply_id dedup 全部失效 → 落两遍。
          if (markReplySeen(typeof msg.mp_msg_id === "string" ? msg.mp_msg_id : undefined)) {
            console.warn(`[hub] duplicate reply dropped (mp_msg_id=${String(msg.mp_msg_id).slice(0, 8)})`)
            return
          }
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
          // Focus check (computed early so offline-queue can use it)
          const isFocused = [...focusByClient.values()].some(id => id === msg.chat_id)
          // Broadcast to all connected App clients
          let count = 0
          let activeCount = 0
          for (const app of appClients) {
            if (app.readyState === WebSocket.OPEN) {
              try { app.send(payload); count++ } catch { /* dead, wait for close */ }
              if (!backgroundedClients.has(app)) activeCount++
            }
          }
          // Persist unconditionally. ws.send() succeeding only means the bytes
          // reached the local buffer — a half-open socket (cell handover, NAT
          // timeout) swallows them silently. Gating this on activeCount/isFocused
          // meant exactly the "client looks online and focused" case wrote no
          // backup, so a silent send failure lost the message for good once the
          // 60s reply buffer pruned it. Duplicates from replay are cheap; the
          // App dedupes on persisted reply_id.
          appendOffline(msg.chat_id, {
            content: msg.content,
            message_id: msg.message_id,
            reply_id,
            timestamp: new Date().toISOString(),
          })
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

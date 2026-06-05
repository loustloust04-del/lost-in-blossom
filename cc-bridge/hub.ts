import { WebSocketServer, WebSocket } from "ws"
import { execFileSync } from "node:child_process"
import { readdirSync, readFileSync, unlinkSync } from "node:fs"

const PORT = 7890
const TMUX_SESSION = process.env.MP_CC_TMUX_SESSION ?? "mp-cc"
const HUB_HOST = process.env.MP_CC_HUB_HOST ?? "127.0.0.1"
const HUB_TOKEN = process.env.MP_CC_HUB_TOKEN

export function isLoopback(addr: string | undefined): boolean {
  if (!addr) return false
  return addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1"
}

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
    // -d detached, 不 --continue（避免多 CC 抢同一个 most-recent jsonl）
    execFileSync("tmux", [
      "new-session", "-d",
      "-s", session,
      "-c", cwd,
      `claude --mcp-config '${mcpConfigPath}'`,
    ])
  }
}

// DRY_RUN: 测试用，所有 tmux 调用 noop；hasSession 默认 true 避免误拒 send
const dryRunRunner: TmuxRunner = {
  send: () => {},
  hasSession: () => true,
  list: () => [],
  spawn: () => {},
}

let tmux: TmuxRunner = process.env.MP_CC_TMUX_DRY_RUN ? dryRunRunner : realTmuxRunner
export function setTmuxRunner(runner: TmuxRunner) { tmux = runner }

// ── CC 输出流式：tmux capture-pane 差量推送辅助 ──────────────
// capture-pane 的输出可能带 ANSI 转义码，推给 App 前清掉。
function stripAnsi(text: string): string {
  return text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "")
}

// 找最长公共前缀（按行），返回 current 相对 prev 新增的尾部行。
// 最简实现，edge case（终端滚动 / 进度条回写）后续再优化。
function extractDelta(prev: string, current: string): string {
  const prevLines = prev.split("\n")
  const currLines = current.split("\n")

  let commonEnd = 0
  for (let i = 0; i < prevLines.length; i++) {
    if (prevLines[i] === currLines[i]) {
      commonEnd = i + 1
    } else {
      break
    }
  }

  return stripAnsi(currLines.slice(commonEnd).join("\n"))
}

// MP 客户端集合（/cc 路径连接的 MP 客户端）
const mpClients = new Set<WebSocket>()
// MCP 客户端集合（/mcp 路径连接的 MCP server）
const mcpClients = new Set<WebSocket>()

// 最近 reply 缓存：iPhone 网络抖动 / reconnect 时 broadcast 撞空，
// 这里保留 60 秒滑动窗口，新 MP client 连上时主动 replay 给它。
// reply_id 用来配合 client 端 dedup（避免重复 deliver）。
interface RecentReply {
  chat_id: string
  content: string
  reply_id: string
  ts: number
}
const REPLY_BUFFER_TTL_MS = 60_000
const recentReplies: RecentReply[] = []

function pruneReplyBuffer() {
  const cutoff = Date.now() - REPLY_BUFFER_TTL_MS
  while (recentReplies.length > 0 && recentReplies[0].ts < cutoff) {
    recentReplies.shift()
  }
}

export function startHub(): WebSocketServer {
  if (!HUB_TOKEN) {
    console.error("[hub] MP_CC_HUB_TOKEN env required (use start_hub.sh or start_hub_lan.sh)")
    process.exit(1)
  }
  const wss = new WebSocketServer({ host: HUB_HOST, port: PORT })

  // ── CC 输出流式轮询 ──────────────────────────────
  // 不依赖 CC 的 reply 行为：直接轮询 CC tmux pane 的终端内容，
  // 跟上一次比对，把新增文字实时广播给 MP 客户端（打字机效果）。
  let lastCapture = ""
  let isStreaming = false
  const POLL_INTERVAL_MS = 500      // 轮询间隔
  const IDLE_THRESHOLD_MS = 3000    // 连续无变化超过此时间认为 CC 停止输出
  let lastChangeTime = Date.now()

  const captureTimer = setInterval(() => {
    if (mpClients.size === 0) return            // 没有客户端连接时不轮询

    // ── cc_stream：tmux capture-pane 差量推送（需要 tmux session）──
    if (tmux.hasSession(TMUX_SESSION)) {
      try {
        const current = execFileSync("tmux", [
          "capture-pane", "-t", TMUX_SESSION, "-p", "-S", "-50",  // 捕获最近 50 行
        ], { encoding: "utf-8" })

        if (current !== lastCapture) {
          const newContent = extractDelta(lastCapture, current)
          lastCapture = current
          lastChangeTime = Date.now()

          if (newContent.trim()) {
            isStreaming = true
            const streamMsg = JSON.stringify({
              type: "cc_stream",
              content: newContent,
              timestamp: new Date().toISOString(),
            })
            for (const ws of mpClients) {
              if (ws.readyState === WebSocket.OPEN) ws.send(streamMsg)
            }
          }
        } else if (isStreaming && Date.now() - lastChangeTime > IDLE_THRESHOLD_MS) {
          // CC 停止输出了
          isStreaming = false
          const endMsg = JSON.stringify({
            type: "cc_stream_end",
            timestamp: new Date().toISOString(),
          })
          for (const ws of mpClients) {
            if (ws.readyState === WebSocket.OPEN) ws.send(endMsg)
          }
        }
      } catch {
        // tmux capture-pane 失败（session 可能不存在），下次轮询再试
      }
    }

    // ── cc_thinking：Stop hook 把 thinking 写入 /tmp/cc-thinking-*.json，
    // 这里检测、广播、删除（文件系统做 IPC，与 tmux session 无关）──
    try {
      const files = readdirSync("/tmp")
        .filter(f => f.startsWith("cc-thinking-") && f.endsWith(".json"))
        .sort()  // 按时间戳排序，多个则依次广播

      for (const file of files) {
        const fullPath = `/tmp/${file}`
        try {
          const raw = readFileSync(fullPath, "utf-8")
          const data = JSON.parse(raw)

          if (data.thinking) {
            const thinkingMsg = JSON.stringify({
              type: "cc_thinking",
              thinking: data.thinking,
              session_id: data.session_id || "",
              timestamp: data.timestamp || new Date().toISOString(),
            })
            for (const ws of mpClients) {
              if (ws.readyState === WebSocket.OPEN) ws.send(thinkingMsg)
            }
          }

          unlinkSync(fullPath)
        } catch {
          // 单个文件解析失败，跳过，下次轮询再试
        }
      }
    } catch {
      // /tmp 读取失败，忽略
    }
  }, POLL_INTERVAL_MS)

  wss.on("close", () => clearInterval(captureTimer))

  wss.on("connection", (ws, req) => {
    // 解析 URL（带 query）
    const reqUrl = new URL(req.url ?? "", "http://localhost")
    const pathname = reqUrl.pathname

    // 鉴权：非 loopback 必须带正确 query token
    const remote = req.socket.remoteAddress
    if (!isLoopback(remote)) {
      const provided = reqUrl.searchParams.get("token")
      if (provided !== HUB_TOKEN) {
        console.warn(`[hub] auth failed from ${remote} (path=${pathname})`)
        ws.close(1008, "auth")
        return
      }
    }

    if (pathname === "/cc") {
      mpClients.add(ws)
      console.log(`[hub] MP connected (total ${mpClients.size}) from ${remote}`)

      // replay 最近 60s 内的 reply 给新 client（兜底网络抖动期间丢的 reply）
      pruneReplyBuffer()
      console.log(`[hub] connect: replay buffer size=${recentReplies.length}`)
      if (recentReplies.length > 0) {
        for (const r of recentReplies) {
          try {
            ws.send(JSON.stringify({
              type: "reply",
              chat_id: r.chat_id,
              content: r.content,
              reply_id: r.reply_id,
            }))
            const ageMs = Date.now() - r.ts
            console.log(`[hub] replay → ${remote}: chat_id=${r.chat_id.slice(0,8)} age=${ageMs}ms reply_id=${r.reply_id.slice(0,8)}`)
          } catch (e: any) {
            console.warn(`[hub] replay failed: ${e?.message}`)
          }
        }
      }

      ws.on("message", (raw) => {
        let msg: any
        try {
          msg = JSON.parse(raw.toString())
        } catch {
          ws.send(JSON.stringify({ type: "error", reason: "invalid_json" }))
          return
        }

        if (msg.type === "send") {
          // L2：per-session 路由。缺省字段 fallback 默认 mp-cc 兼容旧 MP
          const targetSession = typeof msg.session_name === "string" && msg.session_name
            ? msg.session_name
            : TMUX_SESSION
          // 死 session 立即报错，不等 MP 端 60s grace timer
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
            const tag = buildChannelTag(msg as MPMessage, ts)
            tmux.send(tag, targetSession)
            console.log(`[hub] send → tmux:${targetSession} chat_id=${msg.chat_id?.slice(0, 8)} ${msg.content?.slice(0, 50)}`)
            ws.send(JSON.stringify({ type: "ack", message_id: msg.message_id }))
          } catch (err: any) {
            ws.send(JSON.stringify({
              type: "error",
              message_id: msg.message_id,
              reason: `tmux: ${err.message}`,
            }))
          }
        } else if (msg.type === "spawn_cc") {
          const sessionName = typeof msg.session_name === "string" ? msg.session_name : ""
          // 校验：只允许 alphanum + _-. ，长度 1-32
          if (!/^[A-Za-z0-9_.-]{1,32}$/.test(sessionName)) {
            ws.send(JSON.stringify({ type: "spawn_cc_err", session_name: sessionName, reason: "invalid_name" }))
            return
          }
          if (tmux.hasSession(sessionName)) {
            ws.send(JSON.stringify({ type: "spawn_cc_err", session_name: sessionName, reason: "session_exists" }))
            return
          }
          const cwd = process.env.MP_CC_WORKDIR ?? `${process.env.HOME}/Desktop/cc-rp`
          // hub 自身 cwd 应当是 cc-bridge/，.mcp.json 在该目录由 start_cc.sh 渲染
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
        } else if (msg.type === "list_sessions") {
          // 只返回 mp-cc 前缀的 session（避免暴露用户其它 tmux 工作）
          const sessions = tmux.list().filter(s => s.startsWith("mp-cc"))
          ws.send(JSON.stringify({ type: "list_sessions_result", sessions }))
        }
      })

      ws.on("close", (code, reason) => {
        mpClients.delete(ws)
        console.log(`[hub] MP disconnected (total ${mpClients.size}) code=${code} reason=${reason?.toString() || "(empty)"}`)
      })
    } else if (pathname === "/mcp") {
      mcpClients.add(ws)
      console.log(`[hub] MCP connected (total ${mcpClients.size})`)

      ws.on("message", (raw) => {
        let msg: any
        try { msg = JSON.parse(raw.toString()) } catch { return }
        if (msg.type === "reply" && typeof msg.chat_id === "string" && typeof msg.content === "string") {
          // 生成 reply_id 让 client 去重
          const reply_id = crypto.randomUUID()
          const payload = JSON.stringify({
            type: "reply",
            chat_id: msg.chat_id,
            content: msg.content,
            reply_id,
          })
          // 缓存（用于 reconnect replay）
          pruneReplyBuffer()
          recentReplies.push({
            chat_id: msg.chat_id,
            content: msg.content,
            reply_id,
            ts: Date.now(),
          })
          // broadcast
          let broadcastTo = 0
          for (const mp of mpClients) {
            if (mp.readyState === mp.OPEN) {
              try {
                mp.send(payload)
                broadcastTo++
              } catch {
                // 死 socket，等 close 事件清理
              }
            }
          }
          console.log(`[hub] reply ← mcp → broadcast to ${broadcastTo}/${mpClients.size} mp clients (buffered)`)
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

  console.log(`[hub] listening on ws://${HUB_HOST}:${PORT}/cc and /mcp`)
  return wss
}

// Auto-start only when this file is the entry point (bun run hub.ts)
if (import.meta.main) {
  startHub()
}

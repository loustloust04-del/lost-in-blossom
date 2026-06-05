import { Database } from "bun:sqlite"
import { Hono } from "hono"
import { cors } from "hono/cors"

// ── Config ──────────────────────────────────────────────────
const PORT = 3300
const DB_PATH = "/root/projects/BunnyPalace/cc-bridge/chatroom/chatroom.db"

// OpenRouter API（统一入口，Claude/DeepSeek/Gemini 都从这走）
const OPENROUTER_API = "https://openrouter.ai/api/v1/chat/completions"
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY || ""

// DeepSeek 直连（便宜的任务用这个）
const DEEPSEEK_API = "https://api.deepseek.com/chat/completions"
const DEEPSEEK_KEY = process.env.DEEPSEEK_API_KEY || ""

// ── Database ────────────────────────────────────────────────
const db = new Database(DB_PATH)
db.exec("PRAGMA journal_mode = WAL")
db.exec("PRAGMA foreign_keys = ON")

db.exec(`
  CREATE TABLE IF NOT EXISTS chatroom_sessions (
    id TEXT PRIMARY KEY,
    topic TEXT,
    ai_a_model TEXT,
    ai_a_name TEXT,
    ai_a_system TEXT DEFAULT '',
    ai_b_model TEXT,
    ai_b_name TEXT,
    ai_b_system TEXT DEFAULT '',
    status TEXT DEFAULT 'active',
    rounds INTEGER DEFAULT 0,
    max_rounds INTEGER DEFAULT 20,
    created_at TEXT DEFAULT (datetime('now')),
    ended_at TEXT
  )
`)

db.exec(`
  CREATE TABLE IF NOT EXISTS chatroom_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    model TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (session_id) REFERENCES chatroom_sessions(id)
  )
`)

db.exec(`
  CREATE TABLE IF NOT EXISTS chatroom_summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    summary TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (session_id) REFERENCES chatroom_sessions(id)
  )
`)

console.log("[chatroom] database ready:", DB_PATH)

// ── SSE Clients ─────────────────────────────────────────────
type SSEClient = { sessionId: string; controller: ReadableStreamDefaultController }
const sseClients: SSEClient[] = []

function broadcastSSE(sessionId: string, event: string, data: object) {
  const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`
  for (const client of sseClients) {
    if (client.sessionId === sessionId) {
      try { client.controller.enqueue(new TextEncoder().encode(payload)) } catch {}
    }
  }
}

// ── AI API Call ──────────────────────────────────────────────
interface AICallOptions {
  model: string
  systemPrompt: string
  messages: { role: string; content: string }[]
  sessionId: string
  speakerRole: string  // "ai_a" or "ai_b"
}

async function callAI(opts: AICallOptions): Promise<string> {
  const { model, systemPrompt, messages, sessionId, speakerRole } = opts

  // 判断走 OpenRouter 还是 DeepSeek 直连
  const isDeepSeek = model.startsWith("deepseek") && !model.includes("/")
  const apiURL = isDeepSeek ? DEEPSEEK_API : OPENROUTER_API
  const apiKey = isDeepSeek ? DEEPSEEK_KEY : OPENROUTER_KEY

  // 自动追加：不要模仿输入的 [角色名]: 前缀格式
  const antiPrefix = "Direct reply only. Never prefix your response with any name tag like [Name]: or brackets."
  const fullSystem = systemPrompt ? systemPrompt + " " + antiPrefix : antiPrefix

  const body: any = {
    model,
    messages: [
      { role: "system", content: fullSystem },
      ...messages,
    ],
    stream: true,
  }

  const res = await fetch(apiURL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
      ...(isDeepSeek ? {} : { "HTTP-Referer": "https://lib.amberrib.com" }),
    },
    body: JSON.stringify(body),
  })

  if (!res.ok) {
    const err = await res.text()
    throw new Error(`AI API error ${res.status}: ${err}`)
  }

  // 流式读取 + SSE 转推
  let fullContent = ""
  const reader = res.body!.getReader()
  const decoder = new TextDecoder()
  let buffer = ""

  while (true) {
    const { done, value } = await reader.read()
    if (done) break

    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split("\n")
    buffer = lines.pop() || ""

    for (const line of lines) {
      if (!line.startsWith("data: ")) continue
      const data = line.slice(6).trim()
      if (data === "[DONE]") continue

      try {
        const parsed = JSON.parse(data)
        const delta = parsed.choices?.[0]?.delta?.content || ""
        if (delta) {
          fullContent += delta
          broadcastSSE(sessionId, "ai_speaking", {
            role: speakerRole,
            delta,
            model,
          })
        }
      } catch {}
    }
  }

  // 发送完成事件
  broadcastSSE(sessionId, "ai_done", { role: speakerRole, model })

  return fullContent
}

// ── Message Assembly ────────────────────────────────────────
// 关键 trick：给每个 AI 组装消息时，自己的话是 assistant，对方的话和用户的话是 user（带前缀）
function assembleMessages(
  allMessages: { role: string; content: string }[],
  forRole: "ai_a" | "ai_b",
  aiAName: string,
  aiBName: string
): { role: string; content: string }[] {
  const otherRole = forRole === "ai_a" ? "ai_b" : "ai_a"
  const otherName = forRole === "ai_a" ? aiBName : aiAName

  return allMessages.map((msg) => {
    if (msg.role === forRole) {
      return { role: "assistant", content: msg.content }
    } else if (msg.role === otherRole) {
      return { role: "user", content: `[${otherName}]: ${msg.content}` }
    } else {
      // user
      return { role: "user", content: `[用户]: ${msg.content}` }
    }
  })
}

// ── Run One Round ───────────────────────────────────────────
async function runRound(sessionId: string) {
  const session = db.query("SELECT * FROM chatroom_sessions WHERE id = ?").get(sessionId) as any
  if (!session || session.status === "ended") throw new Error("Session not found or ended")

  const allMessages = db.query(
    "SELECT role, content FROM chatroom_messages WHERE session_id = ? ORDER BY id"
  ).all(sessionId) as { role: string; content: string }[]

  // AI A 发言
  broadcastSSE(sessionId, "turn_start", { role: "ai_a", name: session.ai_a_name })
  const messagesForA = assembleMessages(allMessages, "ai_a", session.ai_a_name, session.ai_b_name)
  const contentA = await callAI({
    model: session.ai_a_model,
    systemPrompt: session.ai_a_system || "",
    messages: messagesForA,
    sessionId,
    speakerRole: "ai_a",
  })

  // 存 A 的消息
  db.query("INSERT INTO chatroom_messages (session_id, role, content, model) VALUES (?, ?, ?, ?)")
    .run(sessionId, "ai_a", contentA, session.ai_a_model)

  // 更新 allMessages
  allMessages.push({ role: "ai_a", content: contentA })

  // AI B 发言
  broadcastSSE(sessionId, "turn_start", { role: "ai_b", name: session.ai_b_name })
  const messagesForB = assembleMessages(allMessages, "ai_b", session.ai_a_name, session.ai_b_name)
  const contentB = await callAI({
    model: session.ai_b_model,
    systemPrompt: session.ai_b_system || "",
    messages: messagesForB,
    sessionId,
    speakerRole: "ai_b",
  })

  // 存 B 的消息
  db.query("INSERT INTO chatroom_messages (session_id, role, content, model) VALUES (?, ?, ?, ?)")
    .run(sessionId, "ai_b", contentB, session.ai_b_model)

  // 更新轮次
  const newRounds = session.rounds + 1
  db.query("UPDATE chatroom_sessions SET rounds = ?, status = 'waiting' WHERE id = ?")
    .run(newRounds, sessionId)

  // 通知前端一轮结束
  broadcastSSE(sessionId, "round_complete", {
    round: newRounds,
    status: "waiting_user",
    ai_a_content: contentA,
    ai_b_content: contentB,
  })
}

// ── Hono App ────────────────────────────────────────────────
const app = new Hono()
app.use("/*", cors())

// 创建聊天室 + 第一轮
app.post("/chatroom/start", async (c) => {
  const body = await c.req.json()
  const id = crypto.randomUUID()

  db.query(`INSERT INTO chatroom_sessions 
    (id, topic, ai_a_model, ai_a_name, ai_a_system, ai_b_model, ai_b_name, ai_b_system)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    id,
    body.topic || "自由对话",
    body.ai_a_model || "anthropic/claude-sonnet-4",
    body.ai_a_name || "AI A",
    body.ai_a_system || "",
    body.ai_b_model || "deepseek/deepseek-chat",
    body.ai_b_name || "AI B",
    body.ai_b_system || "",
  )

  // 用话题作为第一条用户消息，启动对话
  if (body.topic) {
    db.query("INSERT INTO chatroom_messages (session_id, role, content) VALUES (?, 'user', ?)")
      .run(id, body.topic)
  }

  // 异步跑第一轮（不阻塞响应）
  runRound(id).catch(err => {
    console.error("[chatroom] round error:", err)
    broadcastSSE(id, "error", { message: err.message })
  })

  return c.json({ id, status: "started" })
})

// 继续下一轮
app.post("/chatroom/continue", async (c) => {
  const { session_id } = await c.req.json()

  db.query("UPDATE chatroom_sessions SET status = 'active' WHERE id = ?").run(session_id)

  runRound(session_id).catch(err => {
    console.error("[chatroom] round error:", err)
    broadcastSSE(session_id, "error", { message: err.message })
  })

  return c.json({ status: "continuing" })
})

// 用户发消息
app.post("/chatroom/send", async (c) => {
  const { session_id, content } = await c.req.json()

  db.query("INSERT INTO chatroom_messages (session_id, role, content) VALUES (?, 'user', ?)")
    .run(session_id, content)

  // 用户消息后继续一轮
  db.query("UPDATE chatroom_sessions SET status = 'active' WHERE id = ?").run(session_id)

  runRound(session_id).catch(err => {
    console.error("[chatroom] round error:", err)
    broadcastSSE(session_id, "error", { message: err.message })
  })

  return c.json({ status: "sent" })
})

// 结束聊天室
app.post("/chatroom/end", async (c) => {
  const { session_id } = await c.req.json()

  db.query("UPDATE chatroom_sessions SET status = 'ended', ended_at = datetime('now') WHERE id = ?")
    .run(session_id)

  broadcastSSE(session_id, "session_ended", { session_id })

  return c.json({ status: "ended" })
})

// 获取消息历史
app.get("/chatroom/history/:id", (c) => {
  const id = c.req.param("id")
  const messages = db.query(
    "SELECT id, role, content, model, created_at FROM chatroom_messages WHERE session_id = ? ORDER BY id"
  ).all(id)
  return c.json({ messages })
})

// 列出所有聊天室
app.get("/chatroom/sessions", (c) => {
  const sessions = db.query(
    "SELECT * FROM chatroom_sessions ORDER BY created_at DESC"
  ).all()
  return c.json({ sessions })
})

// SSE 流式订阅
app.get("/chatroom/stream/:id", (c) => {
  const sessionId = c.req.param("id")

  const stream = new ReadableStream({
    start(controller) {
      const client: SSEClient = { sessionId, controller }
      sseClients.push(client)

      // 心跳
      const heartbeat = setInterval(() => {
        try {
          controller.enqueue(new TextEncoder().encode(": heartbeat\n\n"))
        } catch {
          clearInterval(heartbeat)
        }
      }, 15000)

      // 清理
      c.req.raw.signal.addEventListener("abort", () => {
        clearInterval(heartbeat)
        const idx = sseClients.indexOf(client)
        if (idx !== -1) sseClients.splice(idx, 1)
      })
    },
  })

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
    },
  })
})

// ── Start ───────────────────────────────────────────────────
console.log(`[chatroom] orchestrator listening on port ${PORT}`)
export default { port: PORT, fetch: app.fetch }

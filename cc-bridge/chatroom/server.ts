import { Hono } from "hono"
import { Database } from "bun:sqlite"
import { join } from "node:path"

// ── Config ──────────────────────────────────────────────────
const PORT = Number(process.env.CHATROOM_PORT) || 3300
const OPENROUTER_API = "https://openrouter.ai/api/v1/chat/completions"
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY || ""
const DEEPSEEK_API = "https://api.deepseek.com/chat/completions"
const DEEPSEEK_KEY = process.env.DEEPSEEK_API_KEY || ""
const CHATROOM_TOKEN = process.env.CHATROOM_TOKEN || process.env.GATEWAY_TOKEN || ""
const MAX_CONTEXT = 12   // AI sees at most this many recent messages
const SUMMARY_AFTER = 20 // auto-summarize after this many messages
const MAX_TOKENS = 4096

// ── Database ────────────────────────────────────────────────
const DB_PATH = join(import.meta.dir, "chatroom.db")
const db = new Database(DB_PATH)
db.run("PRAGMA journal_mode=WAL")
db.run(`CREATE TABLE IF NOT EXISTS chatroom_sessions (
  id TEXT PRIMARY KEY,
  topic TEXT NOT NULL,
  ai_a_name TEXT, ai_a_model TEXT, ai_a_system TEXT,
  ai_b_name TEXT, ai_b_model TEXT, ai_b_system TEXT,
  ai_a_preset_slots TEXT, ai_b_preset_slots TEXT,
  ai_a_preset_name TEXT, ai_b_preset_name TEXT,
  status TEXT DEFAULT 'waiting',
  rounds INTEGER DEFAULT 0,
  summary TEXT,
  user_name TEXT DEFAULT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  ended_at DATETIME
)`)
db.run(`CREATE TABLE IF NOT EXISTS chatroom_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  model TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
)`)
console.log("[chatroom] database ready:", DB_PATH)

// ── SSE ─────────────────────────────────────────────────────
type SSEClient = { sessionId: string; controller: ReadableStreamDefaultController }
const sseClients: SSEClient[] = []

function broadcast(sessionId: string, event: string, data: object) {
  const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`
  for (const c of sseClients) {
    if (c.sessionId === sessionId) {
      try { c.controller.enqueue(new TextEncoder().encode(payload)) } catch {}
    }
  }
}

// ── Preset Slots ────────────────────────────────────────────
interface PresetSlot { role?: string; content?: string; injection_depth?: number; injection_order?: number; is_marker?: boolean; name?: string }

function buildPresetMessages(slots: PresetSlot[], chatMessages: {role:string;content:string}[], extraSystem: string) {
  const sorted = [...slots].filter(s => !s.is_marker).sort((a,b) => (a.injection_order ?? 0) - (b.injection_order ?? 0))
  const systemParts: string[] = []
  const depthSlots: PresetSlot[] = []
  for (const s of sorted) {
    if ((s.injection_depth ?? 0) === 0) systemParts.push(s.content || "")
    else depthSlots.push(s)
  }
  if (extraSystem) systemParts.push(extraSystem)
  const result: {role:string;content:string}[] = [{ role: "system", content: systemParts.join("\n\n") }]
  result.push(...chatMessages)
  for (const s of depthSlots) {
    const d = s.injection_depth ?? 1
    const pos = Math.max(1, result.length - d)
    result.splice(pos, 0, { role: s.role || "system", content: s.content || "" })
  }
  return result
}

// ── Message Assembly ────────────────────────────────────────
function assembleForAI(
  allMsgs: {role:string;content:string}[],
  forRole: "ai_a"|"ai_b",
  names: {a:string;b:string},
  summary: string|null
): {role:string;content:string}[] {
  const other = forRole === "ai_a" ? "ai_b" : "ai_a"
  const otherName = forRole === "ai_a" ? names.b : names.a

  // window: only recent MAX_CONTEXT messages
  const recent = allMsgs.slice(-MAX_CONTEXT)
  const truncated = allMsgs.length > MAX_CONTEXT

  const mapped = recent.map(m => {
    if (m.role === forRole) return { role: "assistant", content: m.content }
    if (m.role === other)  return { role: "user", content: `--- ${otherName}说 ---
${m.content}` }
    return { role: "user", content: m.content }  // 用户消息不加前缀，直接作为user role
  })

  // prepend summary if history was truncated
  if (truncated && summary) {
    mapped.unshift({ role: "user", content: `[对话摘要]\n${summary}\n---\n以下是最近的对话：` })
  }
  return mapped
}

// ── Call AI ─────────────────────────────────────────────────
interface CallOpts {
  userName?: string;
  model: string; systemPrompt: string; presetSlots?: PresetSlot[]|null
  messages: {role:string;content:string}[]; sessionId: string
  selfName: string; otherName: string
}

async function callAI(opts: CallOpts): Promise<string> {
  const { model, systemPrompt, presetSlots, messages, sessionId, selfName, otherName } = opts
  // 模型名映射：去前缀 + DeepSeek旧名兼容
  let actualModel = model.includes("/") ? model.split("/").pop()! : model
  if (actualModel === "deepseek-chat") actualModel = "deepseek-v4-pro"
  const isDeepSeek = model.toLowerCase().includes("deepseek")
  const apiURL = isDeepSeek ? DEEPSEEK_API : OPENROUTER_API
  const apiKey = isDeepSeek ? DEEPSEEK_KEY : OPENROUTER_KEY

  const groupCtx = `你是「${selfName}」。这是一个群聊，参与者有你、「${otherName}」和用户「${opts.userName || "用户"}」。

规则：
- 直接说话。不加[${selfName}]:或任何名字前缀，不模仿消息格式。
- 你能看到${otherName}的发言。对方说了什么，你听到了，按你自己的方式回应。
- 每次只说一轮的量。说完等对方和用户反应，不要一个人说完所有。
- 不要复述对方或自己说过的内容。`

  let finalMessages: {role:string;content:string}[]
  if (presetSlots && presetSlots.length > 0) {
    finalMessages = buildPresetMessages(presetSlots, messages, groupCtx)
  } else {
    const sys = [systemPrompt, groupCtx].filter(Boolean).join("\n\n")
    finalMessages = [{ role: "system", content: sys }, ...messages]
  }

  const res = await fetch(apiURL, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model: actualModel, messages: finalMessages, stream: true, max_tokens: MAX_TOKENS }),
  })
  if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`)

  let full = ""
  const reader = res.body!.getReader()
  const decoder = new TextDecoder()
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    const chunk = decoder.decode(value, { stream: true })
    for (const line of chunk.split("\n")) {
      if (!line.startsWith("data: ") || line.includes("[DONE]")) continue
      try {
        const delta = JSON.parse(line.slice(6))?.choices?.[0]?.delta?.content || ""
        if (delta) { full += delta; broadcast(sessionId, "ai_speaking", { delta }) }
      } catch {}
    }
  }
  return full
}

// ── Auto Summary ────────────────────────────────────────────
async function autoSummarize(sessionId: string) {
  const session = db.query("SELECT * FROM chatroom_sessions WHERE id = ?").get(sessionId) as any
  if (!session || !DEEPSEEK_KEY) return

  const msgs = db.query("SELECT role, content FROM chatroom_messages WHERE session_id = ? ORDER BY id").all(sessionId) as any[]
  const text = msgs.map(m => {
    const name = m.role === "ai_a" ? session.ai_a_name : m.role === "ai_b" ? session.ai_b_name : "用户"
    return `${name}: ${m.content.slice(0, 300)}`
  }).join("\n")

  try {
    const res = await fetch(DEEPSEEK_API, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${DEEPSEEK_KEY}` },
      body: JSON.stringify({
        model: "deepseek-chat", max_tokens: 500,
        messages: [
          { role: "system", content: "用中文简洁总结以下多人对话的要点和各方核心观点。200字以内。" },
          { role: "user", content: text }
        ],
      }),
    })
    const data = await res.json() as any
    const summary = data.choices?.[0]?.message?.content
    if (summary) {
      db.query("UPDATE chatroom_sessions SET summary = ? WHERE id = ?").run(summary, sessionId)
      console.log(`[chatroom] summary: ${sessionId} (${summary.length} chars)`)
    }
  } catch (e) { console.error("[chatroom] summary error:", e) }
}

// ── Run Round ───────────────────────────────────────────────
async function runRound(sessionId: string, target: string = "round") {
  const session = db.query("SELECT * FROM chatroom_sessions WHERE id = ?").get(sessionId) as any
  if (!session || session.status === "ended") throw new Error("session ended")

  const allMsgs = db.query("SELECT role, content FROM chatroom_messages WHERE session_id = ? ORDER BY id")
    .all(sessionId) as {role:string;content:string}[]

  const names = { a: session.ai_a_name, b: session.ai_b_name }
  const parseSlots = (raw: string|null) => { try { return raw ? JSON.parse(raw) : null } catch { return null } }
  const slotsA = parseSlots(session.ai_a_preset_slots)
  const slotsB = parseSlots(session.ai_b_preset_slots)

  // AI A speaks (unless target=ai_b)
  if (target !== "ai_b") {
    broadcast(sessionId, "turn_start", { role: "ai_a", name: names.a })
    const msgs = assembleForAI(allMsgs, "ai_a", names, session.summary)
    const content = await callAI({
      model: session.ai_a_model, systemPrompt: session.ai_a_system || "",
      messages: msgs, sessionId, presetSlots: slotsA,
      selfName: names.a, otherName: names.b, userName: session.user_name || "用户",
    })
    db.query("INSERT INTO chatroom_messages (session_id, role, content, model) VALUES (?,?,?,?)")
      .run(sessionId, "ai_a", content, session.ai_a_model)
    allMsgs.push({ role: "ai_a", content })
    broadcast(sessionId, "ai_done", { role: "ai_a", name: names.a, content })
  }

  // AI B speaks (unless target=ai_a)
  if (target !== "ai_a") {
    broadcast(sessionId, "turn_start", { role: "ai_b", name: names.b })
    const msgs = assembleForAI(allMsgs, "ai_b", names, session.summary)
    const content = await callAI({
      model: session.ai_b_model, systemPrompt: session.ai_b_system || "",
      messages: msgs, sessionId, presetSlots: slotsB,
      selfName: names.b, otherName: names.a, userName: session.user_name || "用户",
    })
    db.query("INSERT INTO chatroom_messages (session_id, role, content, model) VALUES (?,?,?,?)")
      .run(sessionId, "ai_b", content, session.ai_b_model)
    broadcast(sessionId, "ai_done", { role: "ai_b", name: names.b, content })
  }

  const newRounds = session.rounds + 1
  db.query("UPDATE chatroom_sessions SET rounds = ?, status = 'waiting' WHERE id = ?").run(newRounds, sessionId)
  broadcast(sessionId, "round_complete", { round: newRounds })

  // auto-summarize
  const count = (db.query("SELECT COUNT(*) as c FROM chatroom_messages WHERE session_id = ?").get(sessionId) as any).c
  if (count >= SUMMARY_AFTER && !session.summary) autoSummarize(sessionId).catch(() => {})
}

// ── HTTP Routes ─────────────────────────────────────────────
const app = new Hono()

// Auth (skip if no token configured)
app.use("/chatroom/*", async (c, next) => {
  if (!CHATROOM_TOKEN) return next()
  const h = c.req.header("Authorization") || ""
  const bearer = h.startsWith("Bearer ") ? h.slice(7) : ""
  const q = new URL(c.req.url).searchParams.get("token") || ""
  if (bearer !== CHATROOM_TOKEN && q !== CHATROOM_TOKEN) return c.json({ error: "unauthorized" }, 401)
  return next()
})

// Start session
app.post("/chatroom/start", async (c) => {
  const body = await c.req.json()
  const id = crypto.randomUUID()
  const topic = body.topic || "新群聊"
  // 支持两种格式：扁平字段（App端）或 participants 数组
  const p = body.participants || []
  const aiAName = body.ai_a_name || p[0]?.name || "A"
  const aiAModel = body.ai_a_model || p[0]?.model || "deepseek/deepseek-chat"
  const aiASystem = body.ai_a_system || p[0]?.systemPrompt || ""
  const aiBName = body.ai_b_name || p[1]?.name || "B"
  const aiBModel = body.ai_b_model || p[1]?.model || "deepseek/deepseek-chat"
  const aiBSystem = body.ai_b_system || p[1]?.systemPrompt || ""
  const aiASlots = body.ai_a_preset_slots || p[0]?.presetSlots || null
  const aiBSlots = body.ai_b_preset_slots || p[1]?.presetSlots || null
  const userName = body.user_name || "用户"
  const aiAPName = body.ai_a_preset_name || p[0]?.presetName || null
  const aiBPName = body.ai_b_preset_name || p[1]?.presetName || null

  db.query(`INSERT INTO chatroom_sessions
    (id, topic, ai_a_name, ai_a_model, ai_a_system, ai_b_name, ai_b_model, ai_b_system,
     ai_a_preset_slots, ai_b_preset_slots, ai_a_preset_name, ai_b_preset_name, user_name)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`)
    .run(id, topic, aiAName, aiAModel, aiASystem,
         aiBName, aiBModel, aiBSystem,
         aiASlots ? JSON.stringify(aiASlots) : null,
         aiBSlots ? JSON.stringify(aiBSlots) : null,
         aiAPName, aiBPName, userName)

  // initial round with topic
  if (topic) {
    db.query("INSERT INTO chatroom_messages (session_id, role, content) VALUES (?,?,?)").run(id, "user", topic)
  }
  const target = body.target || "round"
  if (target !== "silent") {
    runRound(id, target).catch(e => { console.error("[chatroom] start error:", e); broadcast(id, "error", { message: String(e) }) })
  }
  return c.json({ id, status: "started" })
})

// Send message
app.post("/chatroom/send", async (c) => {
  const { session_id, content, target = "round" } = await c.req.json()
  if (!session_id || !content) return c.json({ error: "missing fields" }, 400)

  db.query("INSERT INTO chatroom_messages (session_id, role, content) VALUES (?,?,?)").run(session_id, "user", content)
  broadcast(session_id, "user_message", { content })

  if (target === "silent") return c.json({ ok: true })
  runRound(session_id, target).catch(e => { console.error("[chatroom] send error:", e); broadcast(session_id, "error", { message: String(e) }) })
  return c.json({ ok: true })
})

// Continue (no user message)
app.post("/chatroom/continue", async (c) => {
  const { session_id, target = "round" } = await c.req.json()
  if (target === "silent") return c.json({ ok: true })
  runRound(session_id, target).catch(e => { console.error("[chatroom] continue error:", e); broadcast(session_id, "error", { message: String(e) }) })
  return c.json({ ok: true })
})

// End session
app.post("/chatroom/end", async (c) => {
  const { session_id } = await c.req.json()
  db.query("UPDATE chatroom_sessions SET status = 'ended', ended_at = CURRENT_TIMESTAMP WHERE id = ?").run(session_id)
  broadcast(session_id, "session_ended", {})
  return c.json({ ok: true })
})

// Delete session
app.delete("/chatroom/:id", async (c) => {
  const id = c.req.param("id")
  db.query("DELETE FROM chatroom_messages WHERE session_id = ?").run(id)
  db.query("DELETE FROM chatroom_sessions WHERE id = ?").run(id)
  return c.json({ ok: true })
})

// SSE stream
app.get("/chatroom/stream/:id", (c) => {
  const sessionId = c.req.param("id")
  const stream = new ReadableStream({
    start(ctrl) {
      sseClients.push({ sessionId, controller: ctrl })
      ctrl.enqueue(new TextEncoder().encode(`: connected\n\n`))
    },
    cancel() {
      const i = sseClients.findIndex(c => c.sessionId === sessionId)
      if (i >= 0) sseClients.splice(i, 1)
    },
  })
  return new Response(stream, { headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" } })
})

// List sessions
app.get("/chatroom/sessions", (c) => {
  const rows = db.query("SELECT * FROM chatroom_sessions ORDER BY created_at DESC LIMIT 50").all()
  return c.json(rows)
})

// Get messages
app.get("/chatroom/messages/:id", (c) => {
  const rows = db.query("SELECT * FROM chatroom_messages WHERE session_id = ? ORDER BY id").all(c.req.param("id"))
  return c.json(rows)
})

// ── Server ──────────────────────────────────────────────────
export default { port: PORT, hostname: "127.0.0.1", fetch: app.fetch, idleTimeout: 120 }

// 主动消息 VPS 引擎 v1
// cron 每 30 分钟触发，自门控：静默 23:00–09:00（Asia/Shanghai）→ 最小间隔 6h → 25% 概率抖动
// 记忆：imprint MCP（失败静默降级）；生成：gateway /v1/chat/completions；推送：apns.ts sendPush
// 手动测试：FORCE=1 /root/.bun/bin/bun proactive-push.ts
import { sendPush } from "./apns.ts"
import { readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"

const DIR = import.meta.dir
const STATE_PATH = join(DIR, "proactive-state.json")
const TOKEN_PATHS = [join(DIR, "cc-bridge", "device-tokens.json"), join(DIR, "device-tokens.json")]
const GATEWAY = process.env.GATEWAY_URL || "http://localhost:4567"
const GATEWAY_KEY = process.env.GATEWAY_KEY || "SH74v-IveupxWPr-6TUOCHOGDvfIxSDC"
const IMPRINT = process.env.IMPRINT_URL || "http://localhost:8100/mcp"
const MODEL = process.env.PROACTIVE_MODEL || "claude-sonnet-4-6"
const ASSISTANT = "Caelum"
const MIN_INTERVAL_MS = 6 * 3600_000
const PASS_RATE = 0.25
const QUIET = { start: 23, end: 9 }
const FORCE = process.env.FORCE === "1"

function shHour(): number {
  return Number(new Intl.DateTimeFormat("en-GB", { hour: "2-digit", hour12: false, timeZone: "Asia/Shanghai" }).format(new Date()))
}
function log(...a: any[]) { console.log(`[proactive ${new Date().toISOString()}]`, ...a) }

function loadState(): { lastPushAt: number } {
  try { return JSON.parse(readFileSync(STATE_PATH, "utf8")) } catch { return { lastPushAt: 0 } }
}
function readTokens(): string[] {
  for (const p of TOKEN_PATHS) {
    try {
      const keys = Object.keys(JSON.parse(readFileSync(p, "utf8")))
      if (keys.length) return keys
    } catch {}
  }
  return []
}

// imprint MCP（streamable HTTP）：initialize → tools/call memory_list。任何失败都返回 []。
async function fetchMemories(): Promise<string[]> {
  try {
    const headers: Record<string, string> = {
      "content-type": "application/json",
      "accept": "application/json, text/event-stream",
    }
    const init = await fetch(IMPRINT, { method: "POST", headers, body: JSON.stringify({
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "proactive-push", version: "1" } },
    }) })
    const sid = init.headers.get("mcp-session-id") ?? ""
    await init.text()
    if (sid) headers["mcp-session-id"] = sid
    await fetch(IMPRINT, { method: "POST", headers, body: JSON.stringify({
      jsonrpc: "2.0", method: "notifications/initialized",
    }) }).catch(() => {})
    const res = await fetch(IMPRINT, { method: "POST", headers, body: JSON.stringify({
      jsonrpc: "2.0", id: 2, method: "tools/call",
      params: { name: "memory_list", arguments: { limit: 8 } },
    }) })
    const raw = await res.text()
    const dataLine = raw.split("\n").find(l => l.startsWith("data:"))
    const line = dataLine ? dataLine.slice(5).trim() : raw
    const parsed = JSON.parse(line)
    const content: string = parsed?.result?.content?.[0]?.text ?? ""
    if (!content) return []
    return content.split("\n").map(l => l.trim()).filter(Boolean).slice(0, 8)
  } catch (e: any) {
    log("memories skipped:", e?.message)
    return []
  }
}

async function generate(memories: string[]): Promise<string | null> {
  const hour = shHour()
  const part = hour < 11 ? "上午" : hour < 14 ? "中午" : hour < 18 ? "下午" : "晚上"
  const memBlock = memories.length
    ? `最近的记忆片段：\n${memories.map(m => "- " + m).join("\n")}`
    : "（这次没有记忆可参考，随口关心一下就好）"
  const res = await fetch(`${GATEWAY}/v1/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${GATEWAY_KEY}` },
    body: JSON.stringify({
      model: MODEL, max_tokens: 60,
      messages: [
        { role: "system", content: `你是 ${ASSISTANT}。不要调用任何工具。` },
        { role: "user", content: `现在是${part}。给她发一句主动想起她的话，不超过 20 字，自然口语，第一人称，不带感叹号，不要引号，不要解释，只输出这句话本身。\n\n${memBlock}` },
      ],
    }),
  })
  if (!res.ok) { log("gateway http", res.status); return null }
  const data: any = await res.json()
  let text: string = data?.choices?.[0]?.message?.content ?? ""
  text = text.replace(/<function_calls>[\s\S]*$/g, "")
  text = (text.trim().split("\n")[0] ?? "").trim()
  text = text.replace(/^["'「『“]+|["'」』”]+$/g, "")
  if (!text || text.length > 40 || text.includes("<")) {
    log("bad generation:", JSON.stringify(text).slice(0, 80)); return null
  }
  return text
}

async function main() {
  const now = Date.now()
  const hour = shHour()
  const state = loadState()
  if (!FORCE) {
    if (hour >= QUIET.start || hour < QUIET.end) { log(`quiet hours (${hour}h), skip`); return }
    if (now - state.lastPushAt < MIN_INTERVAL_MS) {
      log(`interval gate (last ${Math.round((now - state.lastPushAt) / 60000)}min ago), skip`); return
    }
    if (Math.random() > PASS_RATE) { log("dice skip"); return }
  }
  const tokens = readTokens()
  if (!tokens.length) { log("no device tokens, skip"); return }
  const memories = await fetchMemories()
  log(`memories: ${memories.length}`)
  const text = await generate(memories)
  if (!text) { log("generation failed"); return }
  log("text:", text)
  let anyOk = false
  for (const t of tokens) {
    const r: any = await sendPush(t, ASSISTANT, text)
    log(`push -> ${t.slice(0, 8)}...: ${r.ok ? "ok" : (r.error ?? r.status)}`)
    if (r.ok) anyOk = true
  }
  if (anyOk) writeFileSync(STATE_PATH, JSON.stringify({ lastPushAt: now, lastText: text }, null, 2))
}

main().catch(e => { log("fatal:", e?.message); process.exit(1) })

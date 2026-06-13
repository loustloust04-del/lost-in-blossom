// CC Session 续命：监控 CC 会话 token 用量，超阈值自动 forge（DeepSeek 摘要旧消息 +
// 保留近期 verbatim + 伪造新 session + tmux 重启）。移植自 session-forge（forge.py），
// 改动：丢弃的旧消息先用 DeepSeek 压成摘要，作为新 session 首条消息注入。
//
// 注意：forge 会改写运行中 CC 会话的 transcript 并 respawn tmux pane，是破坏性操作；
// 自动 forge 默认关闭（MP_CC_AUTO_FORGE=1 才开），未在本机 ~/.claude 实测，接入前请验证。
import { execFileSync } from "node:child_process"
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, renameSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { randomUUID } from "node:crypto"

export const DEFAULT_THRESHOLD = 250_000
export const DEFAULT_RETAIN = 100_000
const DEEPSEEK_KEY = process.env.DEEPSEEK_API_KEY || ""

type Event = Record<string, any>

// ---------- 定位 live transcript ----------
function sh(cmd: string, args: string[]): string {
  try { return execFileSync(cmd, args, { encoding: "utf-8", timeout: 5000 }).trim() } catch { return "" }
}
function paneCwd(session: string): string {
  const out = sh("tmux", ["display-message", "-p", "-t", session, "#{pane_current_path}"])
  return out || homedir()
}
function paneDescendants(session: string): Set<number> {
  const pidOut = sh("tmux", ["list-panes", "-t", session, "-F", "#{pane_pid}"])
  const panePid = parseInt((pidOut.split("\n")[0] || "0").trim(), 10) || 0
  const result = new Set<number>()
  if (!panePid) return result
  const ps = sh("ps", ["-axo", "pid=,ppid="])
  const children = new Map<number, number[]>()
  for (const line of ps.split("\n")) {
    const parts = line.trim().split(/\s+/)
    if (parts.length < 2) continue
    const pid = parseInt(parts[0], 10), ppid = parseInt(parts[1], 10)
    if (isNaN(pid) || isNaN(ppid)) continue
    ;(children.get(ppid) ?? children.set(ppid, []).get(ppid)!).push(pid)
  }
  const stack = [panePid]; result.add(panePid)
  while (stack.length) {
    const pid = stack.pop()!
    for (const c of children.get(pid) ?? []) if (!result.has(c)) { result.add(c); stack.push(c) }
  }
  return result
}
function liveSessionId(session: string): string | null {
  const desc = paneDescendants(session)
  const dir = join(homedir(), ".claude", "sessions")
  if (!existsSync(dir)) return null
  let best: { mtime: number; sid: string } | null = null
  for (const f of readdirSync(dir)) {
    if (!f.endsWith(".json")) continue
    const pid = parseInt(f.slice(0, -5), 10)
    if (isNaN(pid) || !desc.has(pid)) continue
    try {
      const info = JSON.parse(readFileSync(join(dir, f), "utf-8"))
      if (info.sessionId) best = { mtime: Date.now(), sid: info.sessionId }
    } catch {}
  }
  return best?.sid ?? null
}
function transcriptPath(session: string): { path: string; sid: string; cwd: string } | null {
  const cwd = paneCwd(session)
  const sid = liveSessionId(session)
  if (!sid) return null
  const slug = cwd.replace(/\//g, "-")
  const path = join(homedir(), ".claude", "projects", slug, `${sid}.jsonl`)
  return existsSync(path) ? { path, sid, cwd } : null
}

// ---------- transcript 解析 ----------
function loadJsonl(path: string): Event[] {
  return readFileSync(path, "utf-8").split("\n").filter(Boolean)
    .map(l => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean) as Event[]
}
function eventText(ev: Event): string {
  const c = ev?.message?.content
  if (typeof c === "string") return c
  if (Array.isArray(c)) return c.map((b: any) => b?.text || b?.content || "").join(" ")
  return ""
}
function estimateTokens(ev: Event): number { return Math.ceil(eventText(ev).length / 4) }
function isRealUserEvent(ev: Event): boolean {
  if (ev?.type !== "user" || ev?.isMeta) return false
  const c = ev?.message?.content
  if (Array.isArray(c) && c.some((b: any) => b?.type === "tool_result")) return false
  return true
}

// ---------- 状态 ----------
export interface SessionStatus {
  session: string; sessionId: string | null; tokens: number
  threshold: number; percent: number; events: number; available: boolean
}
export function getStatus(session: string, threshold = DEFAULT_THRESHOLD): SessionStatus {
  const t = transcriptPath(session)
  if (!t) return { session, sessionId: null, tokens: 0, threshold, percent: 0, events: 0, available: false }
  const events = loadJsonl(t.path).filter(e => e.type === "user" || e.type === "assistant")
  const tokens = events.reduce((s, e) => s + estimateTokens(e), 0)
  return { session, sessionId: t.sid, tokens, threshold,
           percent: Math.min(100, Math.round((tokens / threshold) * 100)), events: events.length, available: true }
}

// ---------- DeepSeek 摘要 ----------
async function summarizeOld(events: Event[]): Promise<string> {
  if (!events.length || !DEEPSEEK_KEY) return ""
  const transcript = events.map(e => `${e.type === "user" ? "用户" : "AI"}: ${eventText(e).slice(0, 1200)}`).join("\n").slice(0, 40_000)
  try {
    const r = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${DEEPSEEK_KEY}` },
      body: JSON.stringify({
        model: "deepseek-chat",
        messages: [
          { role: "system", content: "你是对话记忆压缩器。把下面这段即将被丢弃的旧对话压成一份累计记忆：保留人物状态、关键事件、决策共识、未解决事项；不写文风分析、不抒情。800字以内，直接输出。" },
          { role: "user", content: transcript },
        ],
        max_tokens: 1500, stream: false,
      }),
      signal: AbortSignal.timeout(60_000),
    })
    const d: any = await r.json()
    return d?.choices?.[0]?.message?.content || ""
  } catch (e: any) { console.warn("[session-manager] summarize failed:", e?.message); return "" }
}

// ---------- forge ----------
function pickKept(conversation: Event[], retainTokens: number): { kept: Event[]; dropped: Event[] } {
  let acc = 0, cut = 0
  for (let i = conversation.length - 1; i >= 0; i--) {
    acc += estimateTokens(conversation[i])
    if (acc > retainTokens) { cut = i + 1; break }
  }
  let keepStart: number | null = null
  for (let i = cut; i < conversation.length; i++) if (isRealUserEvent(conversation[i])) { keepStart = i; break }
  if (keepStart === null) for (let i = 0; i < conversation.length; i++) if (isRealUserEvent(conversation[i])) { keepStart = i; break }
  if (keepStart === null) return { kept: [], dropped: conversation }
  return { kept: conversation.slice(keepStart), dropped: conversation.slice(0, keepStart) }
}

function rewrite(kept: Event[], newSid: string, summaryMsg: Event | null): Event[] {
  const out: Event[] = []
  let prev: string | null = null
  const all = summaryMsg ? [summaryMsg, ...kept] : kept
  for (const original of all) {
    const ev = JSON.parse(JSON.stringify(original))
    const u = randomUUID()
    ev.uuid = u; ev.parentUuid = prev; ev.sessionId = newSid
    if (ev.type === "user" && "promptId" in ev) ev.promptId = randomUUID()
    prev = u; out.push(ev)
  }
  return out
}

export interface ForgeResult {
  ok: boolean; oldSid?: string; newSid?: string; kept?: number; dropped?: number
  summaryChars?: number; restarted?: boolean; error?: string
}

/// forge 一个 CC 会话。restart=false 只改写不重启（安全演练）。
export async function forge(
  session: string, opts: { retainTokens?: number; restart?: boolean } = {}
): Promise<ForgeResult> {
  const retainTokens = opts.retainTokens ?? DEFAULT_RETAIN
  const restart = opts.restart ?? true
  const t = transcriptPath(session)
  if (!t) return { ok: false, error: "live transcript not found (CC session running?)" }
  const events = loadJsonl(t.path)
  const conversation = events.filter(e => e.type === "user" || e.type === "assistant")
  if (!conversation.length) return { ok: false, error: "empty conversation" }

  const { kept, dropped } = pickKept(conversation, retainTokens)
  if (!kept.length) return { ok: false, error: "nothing to keep" }

  const summary = await summarizeOld(dropped)
  const newSid = randomUUID()
  const summaryMsg: Event | null = summary
    ? { type: "user", isMeta: false, sessionId: newSid, message: { role: "user", content: `〔此前对话的累计记忆〕\n${summary}` } }
    : null
  const rewritten = rewrite(kept, newSid, summaryMsg)

  const slug = t.cwd.replace(/\//g, "-")
  const projDir = join(homedir(), ".claude", "projects", slug)
  if (!existsSync(projDir)) mkdirSync(projDir, { recursive: true })
  const newPath = join(projDir, `${newSid}.jsonl`)
  const tmp = newPath + ".tmp"
  writeFileSync(tmp, rewritten.map(e => JSON.stringify(e)).join("\n") + "\n", { mode: 0o600 })
  renameSync(tmp, newPath)

  let restarted = false
  if (restart) {
    try {
      execFileSync("tmux", ["respawn-pane", "-k", "-t", session, "-c", t.cwd,
        `claude --resume ${newSid} --dangerously-skip-permissions`], { timeout: 8000 })
      restarted = true
    } catch (e: any) { return { ok: true, oldSid: t.sid, newSid, kept: kept.length, dropped: dropped.length, summaryChars: summary.length, restarted: false, error: "rewrite ok but respawn failed: " + e?.message } }
  }
  return { ok: true, oldSid: t.sid, newSid, kept: kept.length, dropped: dropped.length, summaryChars: summary.length, restarted }
}

// ---------- 自动监控（opt-in：MP_CC_AUTO_FORGE=1）----------
export function startAutoForge(session: string, intervalMs = 120_000): void {
  if (process.env.MP_CC_AUTO_FORGE !== "1") return
  setInterval(async () => {
    const s = getStatus(session)
    if (s.available && s.tokens >= s.threshold) {
      console.log(`[session-manager] auto-forge ${session} at ${s.tokens} tokens`)
      const r = await forge(session)
      console.log(`[session-manager] forge result:`, JSON.stringify(r))
    }
  }, intervalMs)
  console.log(`[session-manager] auto-forge watching ${session} (threshold ${DEFAULT_THRESHOLD})`)
}

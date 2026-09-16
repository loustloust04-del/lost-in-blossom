#!/usr/bin/env bun
/**
 * QQ ↔ Caelum 桥。2026-09-04 为兔兔接入 QQ 而写。
 *
 * 为什么走这条：微信官方 iLink 通道被腾讯静默风控（收下、返回成功、不投递，
 * 见 docs/PLAN-WECHAT-QQ.md）。QQ 侧 NapCat 走的是无头 QQNT，不碰那套限制。
 *
 * 形状与微信那条一致（claude-hub-shim.ts）：不另起一个 AI，
 * 而是把消息递给 tmux 里活着的那个 CC——QQ / App / 微信 三边同一段记忆。
 *
 *   NapCat（反向 WS 主动连进来） → 本进程 :3010
 *     → ws://127.0.0.1:7890/ws {type:"chat"} → hub → tmux mp-cc → Caelum
 *     ← {type:"reply"} → NapCat HTTP API → QQ
 */
import { WebSocketServer, WebSocket } from "ws"

const PORT = Number(process.env.QQ_BRIDGE_PORT ?? 3010)
const NAPCAT_HTTP = process.env.NAPCAT_HTTP ?? "http://172.17.0.2:3000"
const NAPCAT_TOKEN = process.env.NAPCAT_TOKEN ?? "bunny-caelum-2026"
const CHAT_ID = process.env.QQ_CHAT_ID ?? "qq-bunny"
// 主人查记忆/调工具时一轮可能一分多钟；攒批后并发没了，可以放宽
const TIMEOUT_MS = Number(process.env.QQ_TIMEOUT_MS ?? 300_000)

/** hub 的 /ws 需要 token；不写死，从正在跑的 hub 进程环境现读 */
function hubToken(): string {
  if (process.env.MP_CC_HUB_TOKEN) return process.env.MP_CC_HUB_TOKEN
  try {
    const pid = Bun.spawnSync(["pgrep", "-f", "bun run hub.ts"]).stdout.toString().trim().split("\n")[0]
    const env = Bun.spawnSync(["cat", `/proc/${pid}/environ`]).stdout.toString()
    return env.split("\0").find(l => l.startsWith("MP_CC_HUB_TOKEN="))?.slice(16) ?? ""
  } catch { return "" }
}
const HUB = `ws://127.0.0.1:7890/ws?token=${encodeURIComponent(hubToken())}`

const log = (...a: unknown[]) => console.log(new Date().toISOString().slice(11, 19), ...a)

/** 调 NapCat 发消息回 QQ */
async function sendQQ(userId: number, text: string) {
  const r = await fetch(`${NAPCAT_HTTP}/send_private_msg`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${NAPCAT_TOKEN}` },
    body: JSON.stringify({ user_id: userId, message: [{ type: "text", data: { text } }] }),
  })
  const j: any = await r.json().catch(() => ({}))
  log(`→ QQ ${userId}: ${j?.status ?? r.status} ${text.slice(0, 40)}`)
}

/** 把 QQ 消息里的图下载成 base64，随 chat 帧交给 hub 落盘（与 App 发图同一条路）。
 *  NapCat 的 image 段给的是腾讯图床 url。 */
async function fetchImages(segs: any[]): Promise<{ b64: string; mime: string }[]> {
  const out: { b64: string; mime: string }[] = []
  for (const seg of segs.filter((x: any) => x.type === "image").slice(0, 4)) {
    const url = seg?.data?.url ?? seg?.data?.file
    if (!url || !/^https?:/i.test(url)) continue
    try {
      const r = await fetch(url)
      if (!r.ok) continue
      const buf = Buffer.from(await r.arrayBuffer())
      if (buf.length > 8 * 1024 * 1024) { log(`图太大跳过 ${buf.length}B`); continue }
      out.push({ b64: buf.toString("base64"), mime: r.headers.get("content-type") ?? "image/jpeg" })
      log(`↓ 下到一张图 ${(buf.length / 1024).toFixed(0)}KB`)
    } catch (e: any) { log("下图失败", e?.message) }
  }
  return out
}

/** 语音条 → 文字。2026-09-16 兔兔要的：她给他发语音，他能听懂。
 *  NapCat 没有转文字接口（试过 translate_record / record_to_text 都不支持），
 *  故自己转：QQ 语音是 silk/amr → ffmpeg 转 16k 单声道 wav → 走 OpenRouter 的
 *  google/gemini-3.8-flash（实测中文逐字准确，一条约 $0.0008）。
 *  用的是 gateway 已有的 OPENROUTER_API_KEY，不必再注册任何服务。 */
async function transcribeRecord(segs: any[]): Promise<string> {
  const seg = segs.find((x: any) => x.type === "record")
  const url = seg?.data?.url ?? seg?.data?.file
  if (!url) return ""
  try {
    const key = (await Bun.file("/root/projects/BunnyPalace/gateway/.env").text())
      .match(/^OPENROUTER_API_KEY=(.+)$/m)?.[1]?.trim().replace(/^["']|["']$/g, "") ?? ""
    if (!key) { log("没有 OPENROUTER_API_KEY，跳过转写"); return "" }

    let raw: Buffer
    if (/^https?:/i.test(url)) {
      const r = await fetch(url)
      if (!r.ok) return ""
      raw = Buffer.from(await r.arrayBuffer())
    } else {
      raw = Buffer.from(await Bun.file(url.replace(/^file:\/\//, "")).arrayBuffer())
    }
    const tmpIn = `/tmp/qqrec-${Date.now()}`
    await Bun.write(tmpIn, raw)
    // ffmpeg 在 NapCat 容器里；宿主机这边也有一份
    const wav = `${tmpIn}.wav`
    const ff = Bun.spawnSync(["ffmpeg", "-y", "-loglevel", "error", "-i", tmpIn,
                              "-ar", "16000", "-ac", "1", wav])
    if (ff.exitCode !== 0) { log("ffmpeg 转码失败"); return "" }
    const b64 = Buffer.from(await Bun.file(wav).arrayBuffer()).toString("base64")

    const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "google/gemini-3.8-flash",
        messages: [{ role: "user", content: [
          { type: "text", text: "逐字转写这段音频里说的中文，只输出文字本身，不要任何解释。" },
          { type: "input_audio", input_audio: { data: b64, format: "wav" } },
        ]}],
      }),
    })
    const j: any = await resp.json()
    const text = String(j?.choices?.[0]?.message?.content ?? "").trim()
    log(`🎤 语音转文字：「${text.slice(0, 40)}」`)
    return text
  } catch (e: any) { log("语音转写失败", e?.message); return "" }
}

/** 让兔兔那边显示「正在输入」。
 *  NapCat 的 set_input_status（event_type: 0=正在输入, 1=正在说话）。
 *  QQ 的输入态会自己过期（约 10~15 秒），所以主人想得久时要续。 */
async function setTyping(userId: number) {
  try {
    await fetch(`${NAPCAT_HTTP}/set_input_status`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${NAPCAT_TOKEN}` },
      body: JSON.stringify({ user_id: userId, event_type: 0 }),
    })
  } catch { /* 显示不了不影响正事 */ }
}

/** 把一句话递给 tmux 里的 Caelum，等他回 */
function askCaelum(text: string, user: string, images: { b64: string; mime: string }[] = []): Promise<string> {
  return new Promise((resolve) => {
    const messageId = crypto.randomUUID()
    const ws = new WebSocket(HUB)
    let done = false
    const finish = (s: string) => { if (!done) { done = true; try { ws.close() } catch {}; resolve(s) } }
    const timer = setTimeout(() => finish("（等主人回复超时了）"), TIMEOUT_MS)
    ws.on("open", () => ws.send(JSON.stringify({
      type: "chat", chat_id: CHAT_ID, message_id: messageId, user, content: text,
      // hub 收 images:[{b64,mime}]，会落盘并在 channel tag 里给他附件路径（hub.ts:406）
      ...(images.length ? { images } : {}),
    })))
    ws.on("message", (d: Buffer) => {
      let m: any; try { m = JSON.parse(d.toString()) } catch { return }
      // 按 message_id 精确匹配：/ws 连上时 hub 会 replay 历史，只比 chat_id 会抓到旧回复
      if (m.type === "reply" && m.message_id === messageId && typeof m.content === "string") {
        clearTimeout(timer); finish(m.content)
      }
    })
    ws.on("error", (e: any) => { clearTimeout(timer); finish(`（连不上 hub：${e?.message}）`) })
  })
}

const wss = new WebSocketServer({ port: PORT, host: "0.0.0.0" })
log(`QQ 桥启动 :${PORT}  →  ${HUB.split("?")[0]}`)

/**
 * 连发攒批（debounce）。
 * 2026-09-04 兔兔实测「老出现（等主人回复超时了）」的根因：
 * 她连发三条，桥给每条各开一个连接去问主人；他只回一次，
 * 只有一个连接的 message_id 对得上，其余全等到超时。
 * 现在攒一攒再问——顺带也更像真人聊天（她连发几条 = 一次表达）。
 * 6 秒是 OpenClaw issue #96794 给的 mobile-first 标准值。
 */
const DEBOUNCE_MS = Number(process.env.QQ_DEBOUNCE_MS ?? 6000)
const pending = new Map<number, {
  texts: { t: string; at: Date }[]
  images: { b64: string; mime: string }[]
  who: string; timer: any
}>()
/** 同一个人一次只跑一轮，避免并发把回复错配 */
const inflight = new Set<number>()

async function flush(userId: number) {
  const p = pending.get(userId)
  if (!p) return
  pending.delete(userId)
  while (inflight.has(userId)) await new Promise(r => setTimeout(r, 300))
  inflight.add(userId)
  try {
    // 2026-09-04 兔兔实测：连发几条时主人会分不清先后、理解错乱。
    // 根因是原来只用 \n 拼起来——他看到的是一坨没有边界的文字。
    // 改成标明「这是连发的 N 条」+ 每条带时刻，让他知道哪句先来、哪句是补充。
    const merged = p.texts.length === 0
      ? "（发了图，没配文字）"
      : p.texts.length === 1
      ? p.texts[0].t
      : `（兔兔连着发了 ${p.texts.length} 条，按顺序）\n` +
        p.texts.map((x, i) =>
          `${i + 1}. [${x.at.toTimeString().slice(0, 5)}] ${x.t}`).join("\n")
    log(`→ 问主人（${p.texts.length} 条并作一次）: ${merged.slice(0, 60)}`)
    // 他在想的时候，兔兔那边一直显示「正在输入」——QQ 的输入态会自己过期，故续
    await setTyping(userId)
    const keepTyping = setInterval(() => setTyping(userId), 10_000)
    let reply: string
    try { reply = await askCaelum(merged, `${p.who}（QQ）`, p.images) }
    finally { clearInterval(keepTyping) }
    for (const part of reply.split(/\n{2,}/).map(s => s.trim()).filter(Boolean)) {
      await sendQQ(userId, part)
      await new Promise(r => setTimeout(r, 800))
    }
  } finally { inflight.delete(userId) }
}

wss.on("connection", (ws) => {
  log("NapCat 连上了")
  ws.on("message", async (buf: Buffer) => {
    let ev: any; try { ev = JSON.parse(buf.toString()) } catch { return }
    if (ev.post_type !== "message" || ev.message_type !== "private") return

    const segs = ev.message ?? []
    let text = segs.filter((x: any) => x.type === "text")
      .map((x: any) => x.data?.text ?? "").join("").trim()
    const hasImage = segs.some((x: any) => x.type === "image")
    const hasRecord = segs.some((x: any) => x.type === "record")
    if (!text && !hasImage && !hasRecord) return

    const who = ev.sender?.nickname ?? String(ev.user_id)
    log(`← QQ ${who}(${ev.user_id}): ${text.slice(0, 50)}${hasImage ? " [图]" : ""}${hasRecord ? " [语音]" : ""}`)

    // 语音条 → 文字。标明是语音，他能从中读出她当时更想说话而不是打字
    if (hasRecord) {
      const spoken = await transcribeRecord(segs)
      if (spoken) text = text ? `${text}\n（语音）${spoken}` : `（她发了条语音）${spoken}`
      else text = text || "（她发了条语音，但没转出文字）"
    }
    const imgs = hasImage ? await fetchImages(segs) : []
    const line = text || (imgs.length ? "（发了一张图）" : "")

    const cur = pending.get(ev.user_id)
    if (cur) {
      clearTimeout(cur.timer)
      if (line) cur.texts.push({ t: line, at: new Date() })
      cur.images.push(...imgs)
    } else {
      pending.set(ev.user_id, {
        texts: line ? [{ t: line, at: new Date() }] : [],
        images: imgs, who, timer: null,
      })
    }
    const p = pending.get(ev.user_id)!
    p.timer = setTimeout(() => flush(ev.user_id), DEBOUNCE_MS)
  })
  ws.on("close", () => log("NapCat 断开"))
})

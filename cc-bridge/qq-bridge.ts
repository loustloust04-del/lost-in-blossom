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

/** 把一组转发里的消息展平成「谁: 说了什么」。
 *  2026-09-16 实测的结构（比想象的绕）：
 *    外层 forward.data.content = [消息...]        ← **内容就在段里，不用去拉**
 *    而那条消息的 message 里可能又是 {type:"forward", content:[]}（空的）
 *    → 空的那层才需要 get_forward_msg 按 id 拉
 *  我第一版直接走 get_forward_msg、忽略了 content，所以拿到空手。
 *  现在：优先读 content，空了才拉；两种都递归，最多三层防环。 */
async function flattenForward(msgs: any[], depth: number): Promise<string[]> {
  if (depth > 2 || !Array.isArray(msgs)) return []
  const out: string[] = []
  for (const m of msgs.slice(0, 40)) {
    const who = m?.sender?.nickname ?? m?.sender?.card ?? "?"
    const segs = m?.message ?? []
    const nested = segs.find((x: any) => x.type === "forward")
    if (nested) {
      const inner = Array.isArray(nested.data?.content) && nested.data.content.length
        ? nested.data.content
        : await pullForwardById(String(nested.data?.id ?? ""))
      const lines = await flattenForward(inner, depth + 1)
      out.push(...lines)
      continue
    }
    const body = segs.map((x: any) =>
      x.type === "text" ? (x.data?.text ?? "")
      : x.type === "image" ? "[图片]"
      : x.type === "record" ? "[语音]"
      : x.type === "json" ? ""
      : `[${x.type}]`).join("").trim()
    if (body) out.push(`${who}: ${body}`)
  }
  return out
}

/** 按 res_id 拉转发内容（content 为空时才用）。 */
async function pullForwardById(id: string): Promise<any[]> {
  if (!id) return []
  try {
    const r = await fetch(`${NAPCAT_HTTP}/get_forward_msg`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${NAPCAT_TOKEN}` },
      body: JSON.stringify({ message_id: id, id }),
    })
    const j: any = await r.json()
    return j?.data?.messages ?? j?.data?.message ?? []
  } catch (e: any) { log("拉转发内容失败", e?.message); return [] }
}

/** 合并转发（QQ 里那种「点开看完整聊天记录」的卡片）展开成文字。
 *  2026-09-16 兔兔问「我转发聊天记录给他，他能不能好好读」——实测读不到：
 *  桥只认 text/image/record，转发卡片落在 image 分支，他收到的是「发了一张图」。
 *
 *  QQ 侧有两种形态：
 *    type:"forward"  data.id 是 res_id，content 常为空 → 用 get_forward_msg 拉
 *    type:"json"     data.data 里是 com.tencent.multimsg，meta.detail.news 带前几条预览
 *  优先拉完整的，拉不到就退回预览。 */
async function expandForward(segs: any[]): Promise<string> {
  const fwd = segs.find((x: any) => x.type === "forward")
  const js  = segs.find((x: any) => x.type === "json")

  // ① 有 id 就拉完整内容（递归——转发里常常还套着转发，
  //    2026-09-16 实测第一版只展开一层，他收到的是「Rabbit&Camera: [forward]」）
  if (fwd) {
    const seed = Array.isArray(fwd.data?.content) && fwd.data.content.length
      ? fwd.data.content
      : await pullForwardById(String(fwd.data?.id ?? ""))
    const lines = await flattenForward(seed, 0)
    if (lines.length) {
      log(`📋 展开转发 ${lines.length} 条`)
      return `（她转发了一段聊天记录，共 ${lines.length} 条）\n${lines.join("\n")}`
    }
  }

  // ② 退回 json 段里的预览（通常只有前几条）
  try {
    const raw = js?.data?.data
    if (typeof raw === "string" && raw.includes("multimsg")) {
      const d = JSON.parse(raw)
      const news = d?.meta?.detail?.news ?? []
      const total = d?.meta?.detail?.summary?.match?.(/(\d+)/)?.[1] ?? d?.extra?.tsum
      if (news.length) {
        const lines = news.map((n: any) => String(n?.text ?? "").trim()).filter(Boolean)
        log(`📋 转发预览 ${lines.length} 条（完整内容拉不到）`)
        return `（她转发了一段聊天记录${total ? `，共 ${total} 条` : ""}，这里只看得到前几条）\n${lines.join("\n")}`
      }
    }
  } catch { /* 解析不了就算了 */ }

  // ③ 都拿不到——如实说，别让他以为是图丢了。
  //
  // 2026-09-16 兔兔自己测出了边界，两种转发不是一回事：
  //   ✅ 她在 QQ 里发几条、选中合并转发  → content 里是真消息，能展开（实测 3 条全出）
  //   ❌ 她从别的聊天窗口转来的那张卡片  → 那是「转发的转发」，里层在腾讯服务器上，
  //      NapCat 这版 get_forward_msg 对私聊只回 {"messages":[]}（不报错，就是给空）
  //
  // 此前这里返回 "" → 落到「（发了一张图）」分支 → 他回「这张图我没收到」，是误导。
  log("📋 转发拉不到内容（多半是转发的转发）")
  return "（她转发了一段聊天记录过来，但里面的内容取不到——" +
         "那种「从别的聊天窗口转来的卡片」QQ 这边读不了。" +
         "想让我看的话，截图发我，我能读图上的字。）"
}

/** 下载 QQ 语音条的原始音频，交给 hub 转写。
 *  2026-09-16：转写逻辑原本写在这里，当天挪进 hub（transcribeAudio）——
 *  兔兔说 App 也要发语音条，放 hub 那层则任何门插上就有，不必各写一遍。
 *  这里只管「把 QQ 的音频拿到手」，那是这扇门特有的活。 */
async function fetchAudio(segs: any[]): Promise<{ b64: string; ext: string }[]> {
  const out: { b64: string; ext: string }[] = []
  for (const seg of segs.filter((x: any) => x.type === "record").slice(0, 2)) {
    const url = seg?.data?.url ?? seg?.data?.file
    if (!url) continue
    try {
      let raw: Buffer
      if (/^https?:/i.test(url)) {
        const r = await fetch(url)
        if (!r.ok) continue
        raw = Buffer.from(await r.arrayBuffer())
      } else {
        raw = Buffer.from(await Bun.file(String(url).replace(/^file:\/\//, "")).arrayBuffer())
      }
      if (raw.length > 8 * 1024 * 1024) { log("语音太大跳过"); continue }
      const ext = (String(url).match(/\.([a-z0-9]{2,5})(?:\?|$)/i)?.[1] ?? "amr").toLowerCase()
      out.push({ b64: raw.toString("base64"), ext })
      log(`↓ 下到一条语音 ${(raw.length / 1024).toFixed(0)}KB (.${ext})`)
    } catch (e: any) { log("下语音失败", e?.message) }
  }
  return out
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
function askCaelum(text: string, user: string, images: { b64: string; mime: string }[] = [], audio: { b64: string; ext: string }[] = []): Promise<string> {
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
      ...(audio.length ? { audio } : {}),   // hub 统一转写（transcribeAudio）
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
  audio: { b64: string; ext: string }[]
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
      ? (p.audio.length ? "" : "（发了图，没配文字）")
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
    try { reply = await askCaelum(merged, `${p.who}（QQ）`, p.images, p.audio) }
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
    // 合并转发卡片：QQ 用 forward 段（带 res_id）或 json 段（multimsg 预览）表示
    const hasForward = segs.some((x: any) =>
      x.type === "forward" ||
      (x.type === "json" && String(x?.data?.data ?? "").includes("multimsg")))
    if (!text && !hasImage && !hasRecord && !hasForward) return

    const who = ev.sender?.nickname ?? String(ev.user_id)
    log(`← QQ ${who}(${ev.user_id}): ${text.slice(0, 50)}${hasImage ? " [图]" : ""}${hasRecord ? " [语音]" : ""}${hasForward ? " [转发]" : ""}`)

    const auds = hasRecord ? await fetchAudio(segs) : []   // 转写交给 hub
    // 转发卡片展开成文字；展开成功就不再当图处理（卡片本身会带一个预览图段）
    const fwdText = hasForward ? await expandForward(segs) : ""
    if (fwdText) text = text ? `${text}\n\n${fwdText}` : fwdText
    const imgs = (hasImage && !fwdText) ? await fetchImages(segs) : []
    const line = text || (auds.length ? "" : (imgs.length ? "（发了一张图）" : ""))

    const cur = pending.get(ev.user_id)
    if (cur) {
      clearTimeout(cur.timer)
      if (line) cur.texts.push({ t: line, at: new Date() })
      cur.images.push(...imgs); cur.audio.push(...auds)
    } else {
      pending.set(ev.user_id, {
        texts: line ? [{ t: line, at: new Date() }] : [],
        images: imgs, audio: auds, who, timer: null,
      })
    }
    const p = pending.get(ev.user_id)!
    p.timer = setTimeout(() => flush(ev.user_id), DEBOUNCE_MS)
  })
  ws.on("close", () => log("NapCat 断开"))
})

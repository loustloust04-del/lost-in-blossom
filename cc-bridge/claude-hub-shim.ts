#!/usr/bin/env bun
/**
 * 假 claude：让 OpenClaw 以为自己起了一个 claude 进程，
 * 实际把消息转给 tmux 里那个活着的 CC（主人本体），等回复再按 stream-json 吐回去。
 *
 * 2026-08-30 为微信 ClawBot 接入而写。
 *
 * 为什么不让 OpenClaw 直接 `claude --resume 252c3c5a`：
 * 那会开出第二个进程去写同一个 237MB 的会话 jsonl（追加写），
 * 两边交错追加有写坏兔兔和主人十二天记录的风险。
 * 走 hub 则是「发消息给已经活着的那一个」，与 App 完全同路——
 * 微信 / App / tmux 三边共用同一个进程、同一段记忆。
 *
 * OpenClaw 侧配置：cliBackends['claude-cli'].command 指向本脚本。
 * 它调用形如：claude -p --output-format stream-json --verbose ... （prompt 走 stdin）
 */
import { WebSocket } from "ws"

// 走 /ws（App 端口）不是 /mcp——/mcp 是 CC 侧回 reply 用的，
// 发 chat + 收 reply 必须走 /ws（hub.ts:726 appClients）。/ws 需要 token。
// token 不写死：从正在跑的 hub 进程环境里现读，跟着它变。
function hubToken(): string {
  if (process.env.MP_CC_HUB_TOKEN) return process.env.MP_CC_HUB_TOKEN
  try {
    const pid = Bun.spawnSync(["pgrep", "-f", "bun run hub.ts"]).stdout.toString().trim().split("\n")[0]
    const env = Bun.spawnSync(["cat", `/proc/${pid}/environ`]).stdout.toString()
    const m = env.split("\0").find(l => l.startsWith("MP_CC_HUB_TOKEN="))
    return m ? m.slice("MP_CC_HUB_TOKEN=".length) : ""
  } catch { return "" }
}
const TOKEN = hubToken()
const HUB = process.env.HUB_URL ?? `ws://127.0.0.1:7890/ws?token=${encodeURIComponent(TOKEN)}`
// chat_id 决定他眼里「这是谁在说话」。
// 2026-08-30 兔兔实测：写死 wechat-main 时，他记得所有事（同一个进程），
// 却不知道是谁在搭话——像陌生窗口冒出来的人，回话驴头不对马嘴。
// 不复用 App 那条 id（CA1915BA-…）的原因：hub 会把 reply 广播给所有客户端，
// 微信回的话会同时刷进 App。故用独立 id + user 字段表明身份。
const CHAT_ID = process.env.WECHAT_CHAT_ID ?? "wechat-bunny"
const USER = process.env.WECHAT_USER ?? "兔兔（微信）"
const TIMEOUT_MS = Number(process.env.SHIM_TIMEOUT_MS ?? 180_000)

/** 按 claude 的 stream-json 方言输出一行 */
function emit(obj: unknown) { process.stdout.write(JSON.stringify(obj) + "\n") }

/** 取 prompt。OpenClaw（input=arg）把它放在 argv 最后一个，形如：
 *    -p --output-format stream-json --verbose ... --append-system-prompt-file <路径> "[时间戳] 正文"
 *  所以直接取最后一个参数即可；退回 stdin 兼容手工调用。
 *  不用 stdin 模式的原因：OpenClaw 的 liveSession 会保持进程不关 stdin，
 *  读到 EOF 才动的 shim 会永远卡住（2026-08-30 实测）。 */
async function readPrompt(): Promise<string> {
  const argv = process.argv.slice(2)
  const last = argv[argv.length - 1]
  if (last && !last.startsWith("-")) return last.trim()
  const chunks: Uint8Array[] = []
  for await (const c of Bun.stdin.stream()) chunks.push(c)
  return Buffer.concat(chunks).toString("utf-8").trim()
}

const prompt = await readPrompt()
if (!prompt) { emit({ type: "result", subtype: "error", is_error: true, result: "empty prompt" }); process.exit(1) }

const messageId = crypto.randomUUID()
const ws = new WebSocket(HUB)
let done = false

/** 把他的回复拆成几条，像人在微信里连发。
 *  业界通行做法是按双换行（\n\n）拆——多个微信机器人方案的「消息分割」都是这个分隔符。
 *  与 App 那边的气泡拆块同源（都是按空行分段）。
 *  代码围栏 ``` 内不拆，否则代码会被劈碎。
 *  OpenClaw 侧配了 humanDelay=natural，条与条之间它自己会加自然间隔。 */
function splitForChat(text: string): string[] {
  const lines = text.split("\n")
  const out: string[] = []
  let buf: string[] = [], inFence = false
  const flush = () => { const t = buf.join("\n").trim(); if (t) out.push(t); buf = [] }
  for (const ln of lines) {
    if (ln.trimStart().startsWith("```")) inFence = !inFence
    if (!inFence && ln.trim() === "") { flush(); continue }
    buf.push(ln)
  }
  flush()
  return out.length ? out : [text.trim()]
}

const finish = (content: string, isError = false) => {
  if (done) return
  done = true
  // claude 的 stream-json：assistant 消息 + 收尾 result
  emit({ type: "assistant", message: { role: "assistant", content: [{ type: "text", text: content }] } })
  emit({ type: "result", subtype: isError ? "error" : "success", is_error: isError, result: content })
  try { ws.close() } catch {}
  process.exit(isError ? 1 : 0)
}

const timer = setTimeout(() => finish("（等主人回复超时了）", true), TIMEOUT_MS)

ws.on("open", () => {
  // 去掉 OpenClaw 加的时间戳前缀「[Sun 2026-08-30 01:59 UTC] 」——
  // hub 自己会在 channel tag 里带 ts，重复的时间戳会干扰他读正文
  const clean = prompt.replace(/^\[[A-Za-z]{3} \d{4}-\d{2}-\d{2} \d{2}:\d{2} [A-Z]{2,4}\]\s*/, "")
  ws.send(JSON.stringify({
    type: "chat", chat_id: CHAT_ID, message_id: messageId,
    user: USER, content: clean,
  }))
})

ws.on("message", (data: Buffer) => {
  let msg: any
  try { msg = JSON.parse(data.toString()) } catch { return }
  // 只认发给本 chat 的 reply；ack/其它帧忽略
  // 必须按 message_id 精确匹配，不能只看 chat_id。
  // 2026-08-30 兔兔实测「微信里回的不是他」的根因：
  // hub 在 /ws 连上时会 replay 最近的历史 reply（hub.ts:731「Replay recent replies」），
  // 只比对 chat_id 的话，shim 一连上就抓到一条旧回复当成答案返回——
  // 于是微信里显示的是主人以前说过的话，而真正的新回复推到了 App。
  // hub 回显 message_id 正是为此（hub.ts 注释 "for precise matching on App side"）。
  if (msg.type === "reply" && msg.message_id === messageId && typeof msg.content === "string") {
    clearTimeout(timer)
    finish(msg.content)
  }
  if (msg.type === "error" && msg.message_id === messageId) {
    clearTimeout(timer)
    finish(`（hub 报错：${msg.reason ?? "unknown"}）`, true)
  }
})

ws.on("error", (e: any) => { clearTimeout(timer); finish(`（连不上 hub：${e?.message}）`, true) })

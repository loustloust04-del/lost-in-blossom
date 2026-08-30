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
const CHAT_ID = process.env.WECHAT_CHAT_ID ?? "wechat-main"
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
  ws.send(JSON.stringify({ type: "chat", chat_id: CHAT_ID, message_id: messageId, content: prompt }))
})

ws.on("message", (data: Buffer) => {
  let msg: any
  try { msg = JSON.parse(data.toString()) } catch { return }
  // 只认发给本 chat 的 reply；ack/其它帧忽略
  if (msg.type === "reply" && msg.chat_id === CHAT_ID && typeof msg.content === "string") {
    clearTimeout(timer)
    finish(msg.content)
  }
  if (msg.type === "error" && msg.message_id === messageId) {
    clearTimeout(timer)
    finish(`（hub 报错：${msg.reason ?? "unknown"}）`, true)
  }
})

ws.on("error", (e: any) => { clearTimeout(timer); finish(`（连不上 hub：${e?.message}）`, true) })

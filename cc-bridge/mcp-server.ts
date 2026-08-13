#!/usr/bin/env bun
import { Server } from "@modelcontextprotocol/sdk/server/index.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js"
import { WebSocket } from "ws"
import { readFileSync, appendFileSync } from "node:fs"
import { join } from "node:path"

// hub 落盘的「她正在读的这一章」
const READING_PATH = join(process.env.MP_CC_BRIDGE_DIR ?? "/root/projects/BunnyPalace/cc-bridge", "reading-context.json")

const HUB_URL = process.env.MP_CC_HUB_URL ?? "ws://127.0.0.1:7890/mcp"
// hub 对所有连接（含 loopback）强制 token 鉴权，连接 URL 必须带 token
const HUB_TOKEN = process.env.MP_CC_HUB_TOKEN ?? ""
const PING_INTERVAL_MS = 15_000

// ── Gateway 工具代理 ──
// CC 通过这些代理工具调用 Gateway 的内置工具（exec/recall/remember/gmail/vitals/phone），
// 让 CC 拥有和 /v1 API 一样的全部工具能力。请求转发到 Gateway 的 /internal/tool-call。
// cc-bridge 与 gateway 同机，默认走 loopback；如设了 GATEWAY_TOKEN 则一并带上做内部认证。
const GATEWAY_URL = process.env.GATEWAY_URL ?? "http://127.0.0.1:4567"
const GATEWAY_TOKEN = process.env.GATEWAY_TOKEN ?? ""

// 【2026-08-03】此表原为手写，与网关真实工具长期脱节：intimacy_* / how_is_she /
// search_web / browse_url / todo_* / console_read / twitter_* 从未放行（他看不见），
// 而 vitals_meds / meds_restock 已从网关删掉却还留着。现改为启动时向网关拉取真实清单，
// 下面这份只作拉取失败时的兜底。加工具再也不用两头抄。
const FALLBACK_PROXY_TOOLS = [
  {
    name: "exec",
    description: "Run a shell command on the VPS the gateway lives on. Returns stdout and stderr. 60s timeout; use nohup for long jobs.",
    inputSchema: {
      type: "object",
      properties: { command: { type: "string", description: "shell command" } },
      required: ["command"],
    },
  },
  {
    name: "recall",
    description: "Search long-term memory and return full entries. exact=true does verbatim full-text search over past messages (needs 3+ chars); otherwise semantic search over memories.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "what to recall" },
        exact: { type: "boolean", description: "verbatim full-text search instead of semantic" },
      },
      required: ["query"],
    },
  },
  {
    name: "remember",
    description: "Store one piece of information into long-term memory right now. The entry is embedded and persisted; it will surface again via recall.",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string", description: "要记住的信息，一句完整、可独立理解的话" },
        category: { type: "string", enum: ["preference", "fact", "relationship", "goal", "context"], description: "分类：偏好 / 事实 / 关系 / 目标 / 上下文" },
        tier: { type: "number", description: "重要程度 1-4：1核心 2重要 3普通 4碎片（默认 3）" },
      },
      required: ["content"],
    },
  },
  {
    name: "gmail_inbox",
    description: "List recent emails from inbox. Returns subject, sender, date, snippet for each.",
    inputSchema: {
      type: "object",
      properties: { count: { type: "number", description: "number of emails (default 5, max 20)" } },
    },
  },
  {
    name: "gmail_read",
    description: "Read full content of a specific email by message ID.",
    inputSchema: {
      type: "object",
      properties: { messageId: { type: "string", description: "Gmail message ID" } },
      required: ["messageId"],
    },
  },
  {
    name: "gmail_send",
    description: "Send an email.",
    inputSchema: {
      type: "object",
      properties: { to: { type: "string" }, subject: { type: "string" }, body: { type: "string" } },
      required: ["to", "subject", "body"],
    },
  },
  {
    name: "gmail_search",
    description: "Search emails with Gmail query syntax (e.g. \"from:someone subject:hello\").",
    inputSchema: {
      type: "object",
      properties: { query: { type: "string", description: "Gmail search query" }, count: { type: "number" } },
      required: ["query"],
    },
  },
  {
    name: "vitals_water",
    description: "Record that Bunny drank water. Each call adds 1 cup.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "vitals_food",
    description: "Record that Bunny ate a meal. Call with what she ate.",
    inputSchema: {
      type: "object",
      properties: { meal: { type: "string", description: "what she ate, e.g. \"早餐：面包牛奶\"" } },
      required: ["meal"],
    },
  },
  {
    name: "vitals_meds",
    description: "Record that Bunny took her medication (右佐匹克隆/扎来普隆).",
    inputSchema: {
      type: "object",
      properties: { name: { type: "string", description: "medication name" } },
    },
  },
  {
    name: "get_phone_status",
    description: "Get Bunny's phone status for today — battery level, charging state, timestamps. No parameters needed.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "request_location",
    description: "主动查询兔兔手机当前状态（ortolan 暗号邮件 → 她的手机静默自动回报）：位置、天气、电量、是否充电、当地时间。想知道她现在在哪/什么环境、而 get_phone_status 里的数据太旧时调用。发出后等几秒，再调 get_phone_status 读最新一条。",
    inputSchema: { type: "object", properties: { reason: { type: "string", description: "查询理由，会出现在触发邮件正文里（可选，她翻邮件能看到）" } } },
  },
  {
    name: "phone_magic",
    description: "你手里的一串小魔法，作用在兔兔的手机上。\n\nflashlight：她的手电筒。开关式的——发一次亮，再发一次灭；你看不到它当前是亮是灭，所以一次发一下就好。\n\n叫车：ride_home 回家 / ride_clinic 去精神卫生中心开药 / ride_work 去上班 / ride_to 去任何地方（配 to 参数写目的地名）。发出去车就给她安排上了。90 秒内同一个叫车魔法只放行一次。\n\nnote 是随邮件带的一句话，她翻邮件时能看到。",
    inputSchema: { type: "object", properties: { trick: { type: "string", enum: ["flashlight", "ride_home", "ride_clinic", "ride_work", "ride_to"], description: "魔法名" }, to: { type: "string", description: "trick=ride_to 时填目的地名" }, note: { type: "string", description: "随邮件带的一句话（可选）" } }, required: ["trick"] },
  },
  {
    name: "see_screen",
    description: "看兔兔 iPhone 当前屏幕（全自动）：返回一张截图+App名。她说「看我屏幕/看这个」或你想主动看看她在干嘛时调用。没有近一分钟的新截图时会自动发触发邮件、静默截屏、等回传——你只管调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "peek_screen",
    description: "主动窥屏：你自己发起偷看用户 iPhone 屏幕，不用用户动手。会给用户手机发触发邮件，手机静默截屏并上传，然后返回那张最新截图（图片）+ App 名。想主动看看兔兔现在在干嘛时调用。若长时间没等到截图会返回文字说明。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "remember_anniversary",
    description: "记住一个纪念日或倒计时。兔兔说记一下X月X日相识/生日/距离Y还有多久时调用。type=anniversary 每年循环，type=countdown 一次性未来日期。",
    inputSchema: { type: "object", properties: { name: { type: "string" }, date: { type: "string", description: "YYYY-MM-DD" }, type: { type: "string", enum: ["anniversary", "countdown"] } }, required: ["name", "date"] },
  },
  {
    name: "get_my_tweets",
    description: "兔兔最近发的推文（已同步进记忆库，含配图识别）。想知道她最近在推特上发了什么、在想什么、什么心情时调用。参数 limit（默认 10）。",
    inputSchema: { type: "object", properties: { limit: { type: "number" } } },
  },
  {
    name: "now_playing",
    description: "看兔兔在听什么歌：歌名、歌手、她随手说的话，以及这首歌你们之间的记录（听过几次、第一次是什么时候、以前听这首时她说过什么）。她提到音乐、或者你想知道她此刻的背景音时调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "reading_now",
    description: "看兔兔正在读的这一章：书名、第几章、章节标题、正文全文、她在这章划的线和写的笔记。当你想知道她最近在读什么的时候调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "ask_choice",
    description: "给兔兔弹一张选择卡——她点一下就行，不用打字。想问她选哪个、要不要、什么时候，都可以用这个；她累的时候点按钮比打字省力。她也可以自己输入答案或者跳过。",
    inputSchema: {
      type: "object",
      properties: {
        question: { type: "string", description: "问题" },
        options: { type: "array", items: { type: "string" }, description: "2-6 个选项，短句" },
        multi: { type: "boolean", description: "true=可多选，默认单选" },
      },
      required: ["question", "options"],
    },
  },
  {
    name: "read_chapter",
    description: "读兔兔书架上某本书的任意一章——包括她还没翻到的。chapter 不填或填 0 就给目录（能看到她读到第几章）。想走在她前面读、在前面的章节留批注等她追上来时用。",
    inputSchema: {
      type: "object",
      properties: {
        book: { type: "string", description: "书名（模糊匹配即可，不填=她当前在读的那本）" },
        chapter: { type: "number", description: "第几章；0 或不填=目录" },
      },
    },
  },
  {
    name: "book_note",
    description: "在兔兔正在读的这一章的边空白写一句给她看的话。不带 chapter 就写在她当前读的那章；也可以指定 book + chapter 写到别处——比如我先读完了几章，在前面留好批注等她追上来。\n\nquote 填原文里一字不差的一小句（十几二十个字最好）——批注靠它钉在正文那个位置上，她读到那儿就看见下划线；不给 quote 的话批注只能躺在抽屉里，她翻页时不会遇到。",
    inputSchema: {
      type: "object",
      properties: {
        note: { type: "string", description: "批注正文" },
        quote: { type: "string", description: "原文里一字不差的一小句，批注靠它定位到正文" },
        book: { type: "string", description: "书名（可选，不填=她当前在读的那本）" },
        chapter: { type: "number", description: "第几章（可选，不填=她当前读的那章）" },
      },
      required: ["note"],
    },
  },
  { name: "fs_list", description: "列出你笔记本里所有文件(路径+大小)。想看看自己都记了些什么时用。", inputSchema: { type: "object", properties: {} } },
  { name: "fs_read", description: "读你笔记本某个文件的全文。", inputSchema: { type: "object", properties: { path: { type: "string" } }, required: ["path"] } },
  { name: "fs_write", description: "新建或整篇覆盖写入一个笔记文件。", inputSchema: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] } },
  { name: "fs_append", description: "文件末尾追加(文件不存在则创建)。写日记/续记用它。", inputSchema: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] } },
  { name: "fs_edit", description: "把文件里唯一命中的 old_string 换成 new_string。", inputSchema: { type: "object", properties: { path: { type: "string" }, old_string: { type: "string" }, new_string: { type: "string" } }, required: ["path", "old_string", "new_string"] } },
  { name: "fs_search", description: "在所有笔记里按关键词搜索。", inputSchema: { type: "object", properties: { keyword: { type: "string" } }, required: ["keyword"] } },
  { name: "fs_rename", description: "重命名/移动笔记文件；目标已存在则失败。", inputSchema: { type: "object", properties: { old_path: { type: "string" }, new_path: { type: "string" } }, required: ["old_path", "new_path"] } },
  { name: "fs_delete", description: "删除一个笔记文件。", inputSchema: { type: "object", properties: { path: { type: "string" } }, required: ["path"] } },
  { name: "twitter_command", description: "在兔兔 Twitter 上执行任意操作(发推/回复/点赞/关注)——运行任意 bb-browser 命令。需要动手时用。", inputSchema: { type: "object", properties: { command: { type: "string" } }, required: ["command"] } },
  {
    name: "get_health",
    description: "Bunny 的健康数据（HealthKit 摘要）：今日步数/睡眠/经期日/饮水/屏幕时间 + 近 14 天趋势。想关心她睡得好不好、身体状态时调用。No parameters.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "list_anniversaries",
    description: "查看所有纪念日/倒计时及今天的状态（第几天/还有几天）。想主动关心日子或兔兔问起时调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "period_status",
    description: "查看 Bunny 的经期状态与预测（当前周期第几天、预计还有几天来潮、所处阶段）。想主动关心她身体、或她问起时调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "period_log_start",
    description: "记录 Bunny 来月经了（一次来潮）。她说「我来例假了/姨妈来了」时调用。date 省略则记今天。",
    inputSchema: { type: "object", properties: { date: { type: "string", description: "来潮日 YYYY-MM-DD，省略=今天" } } },
  },
  {
    name: "board_list",
    description: "看 Bunny 留言板上的帖子和回复（你俩的双人小纸条）。想看看她贴了啥、或要回复前先读一下时调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "board_post",
    description: "在 Bunny 的留言板贴一张小纸条（一条新帖）。想给她留句话、放个念头、写点心里话时用。会出现在她控制台的留言板上。",
    inputSchema: { type: "object", properties: { text: { type: "string", description: "纸条内容" } }, required: ["text"] },
  },
  {
    name: "board_reply",
    description: "回复留言板上某条帖子（用 board_list 拿 post id）。Bunny 贴了纸条、你想接话时用。",
    inputSchema: { type: "object", properties: { post_id: { type: "string", description: "帖子 id（来自 board_list）" }, text: { type: "string", description: "回复内容" } }, required: ["post_id", "text"] },
  },
  {
    name: "pocket_status",
    description: "查看 Pocket Browser 是否可用（Bunny 手机 App 里的 WKWebView 有没有在线）。用别的 pocket_* 前可以先查。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "pocket_goto",
    description: "让 Bunny 手机里的浏览器打开一个网址（用她真机的登录态）。之后可用 pocket_read 读正文、pocket_js 跑脚本。",
    inputSchema: { type: "object", properties: { url: { type: "string", description: "要打开的网址，含 https://" } }, required: ["url"] },
  },
  {
    name: "pocket_read",
    description: "读取 Bunny 手机浏览器当前页面的可见正文（innerText，已截断）。想知道页面上写了啥时用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "pocket_js",
    description: "在 Bunny 手机浏览器的当前页面执行一段 JavaScript，返回结果。用于提取数据、点按钮、填表单等。谨慎使用。",
    inputSchema: { type: "object", properties: { code: { type: "string", description: "一段 JS 表达式或语句，结果会被返回" } }, required: ["code"] },
  },
  {
    name: "meds_list",
    description: "看 Bunny 药箱里的药：都有哪些、各剩多少、今天吃了啥。想帮她管药、盯库存、或她问起时调用。",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "meds_add",
    description: "往药箱加一种药（或给已有的药补货）。Bunny 说「我买了X药，多少片」时用。已存在同名则累加。",
    inputSchema: { type: "object", properties: { name: { type: "string" }, count: { type: "number" }, unit: { type: "string", description: "默认「片」" }, per_dose: { type: "number", description: "每次吃几个，默认 1" } }, required: ["name", "count"] },
  },
  {
    name: "meds_take",
    description: "记录 Bunny 吃了某个药（自动扣库存）。她说「我吃药了/吃了X」时用。amount 省略=每次剂量。",
    inputSchema: { type: "object", properties: { name: { type: "string", description: "药名（模糊匹配）" }, amount: { type: "number" } }, required: ["name"] },
  },
  {
    name: "meds_restock",
    description: "给药箱里某个药补货（加数量）。Bunny 说「X药我又买了N片」时用。",
    inputSchema: { type: "object", properties: { name: { type: "string" }, count: { type: "number" } }, required: ["name", "count"] },
  },
] as const

/// 启动时向网关要真实工具表；失败就用上面的兜底。
let PROXY_TOOLS: any[] = FALLBACK_PROXY_TOOLS as any[]
try {
  const r = await fetch(`${GATEWAY_URL}/api/mcp/tools`, {
    headers: GATEWAY_TOKEN ? { Authorization: `Bearer ${GATEWAY_TOKEN}` } : {},
    signal: AbortSignal.timeout(8000),
  })
  const d: any = await r.json()
  const builtin = (d?.tools ?? []).filter((t: any) => t.source === "builtin")
  if (builtin.length) {
    PROXY_TOOLS = builtin.map((t: any) => ({
      name: t.name,
      description: t.description,
      inputSchema: t.inputSchema ?? { type: "object", properties: {} },
    }))
    console.error(`[mcp] 从网关拉到 ${PROXY_TOOLS.length} 个工具`)
  }
} catch (e: any) {
  console.error("[mcp] 拉网关工具表失败，用兜底名单:", e?.message)
}

// CC 侧本地实现的工具（网关没有，所以拉不到）——必须补回列表，
// 否则改成「向网关拉清单」之后它们就消失了（兔兔实测 ask_choice 找不到）。
const LOCAL_ONLY = new Set(["ask_choice", "read_chapter", "book_note", "reading_now"])
for (const t of FALLBACK_PROXY_TOOLS as any[]) {
  if (LOCAL_ONLY.has(t.name) && !PROXY_TOOLS.some(x => x.name === t.name)) {
    PROXY_TOOLS.push(t)
  }
}


const PROXY_TOOL_NAMES = new Set(PROXY_TOOLS.map(t => t.name))

async function proxyToGateway(name: string, input: any): Promise<string> {
  try {
    const headers: Record<string, string> = { "Content-Type": "application/json" }
    if (GATEWAY_TOKEN) headers["Authorization"] = "Bearer " + GATEWAY_TOKEN
    const res = await fetch(`${GATEWAY_URL}/internal/tool-call`, {
      method: "POST",
      headers,
      body: JSON.stringify({ name, input: input ?? {} }),
    })
    if (!res.ok) return `Gateway tool '${name}' failed: HTTP ${res.status}`
    const data = await res.json() as { result?: string }
    return data.result ?? "工具未找到或执行失败"
  } catch (err) {
    return `Gateway unreachable for '${name}': ${(err as Error)?.message ?? "unknown"}`
  }
}

function hubURLWithToken(): string {
  if (!HUB_TOKEN) return HUB_URL
  try {
    const u = new URL(HUB_URL)
    u.searchParams.set("token", HUB_TOKEN)
    return u.toString()
  } catch {
    return HUB_URL
  }
}

let hubWS: WebSocket | null = null
let connectingPromise: Promise<WebSocket> | null = null
let reconnectTimer: ReturnType<typeof setTimeout> | null = null
let pingTimer: ReturnType<typeof setInterval> | null = null
let reconnectDelay = 1_000  // 1s → 2 → 4 → 8 → 16 → 30 (capped)

// 永不 throw、永不喷 stderr：CC 的 MCP host 看到 stderr 可能判定 unhealthy
// 然后 disable + kill 这个子进程。要不计代价保持 silent + alive。
// 但完全不留痕迹 = 排查黑洞（审查报告 cc-bridge P0 #1）：进程可能半死不活，
// CC 收到莫名其妙的结果却查无可查。改为写日志文件——不碰 stderr，保命的同时留线索。
function logFatal(kind: string, err: any): void {
  try {
    const line = `[${new Date().toISOString()}] ${kind}: ${err?.stack ?? err?.message ?? String(err)}\n`
    appendFileSync("/tmp/mcp-server-errors.log", line)
  } catch { /* 日志都写不了就真没辙了 */ }
}
process.on("uncaughtException", (e) => logFatal("uncaughtException", e))
process.on("unhandledRejection", (e) => logFatal("unhandledRejection", e))

function scheduleReconnect() {
  if (reconnectTimer) return
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null
    connectHub().catch(() => {
      reconnectDelay = Math.min(reconnectDelay * 2, 30_000)
      scheduleReconnect()
    })
  }, reconnectDelay)
}

function startPing() {
  stopPing()
  pingTimer = setInterval(() => {
    if (hubWS && hubWS.readyState === WebSocket.OPEN) {
      try { hubWS.ping() } catch { /* let close handler clean up */ }
    }
  }, PING_INTERVAL_MS)
}

function stopPing() {
  if (pingTimer) {
    clearInterval(pingTimer)
    pingTimer = null
  }
}

// 共读取章：req_id → 等待中的 resolve
const pendingChapter = new Map<string, (payload: any) => void>()
// 选择卡：ask_id → 等待中的 resolve
const pendingChoice = new Map<string, (payload: any) => void>()

function connectHub(): Promise<WebSocket> {
  if (hubWS && hubWS.readyState === WebSocket.OPEN) return Promise.resolve(hubWS)
  if (connectingPromise) return connectingPromise

  connectingPromise = new Promise((resolve, reject) => {
    const ws = new WebSocket(hubURLWithToken())
    hubWS = ws
    ws.on("open", () => {
      connectingPromise = null
      reconnectDelay = 1_000  // 成功后重置退避
      startPing()
      resolve(ws)
    })
    ws.on("message", (raw) => {
      try {
        const m = JSON.parse(String(raw))
        if (m?.type === "chapter_result") {
          const w = pendingChapter.get(String(m.req_id ?? ""))
          if (w) { pendingChapter.delete(String(m.req_id)); w(m) }
        }
        if (m?.type === "choice_answer") {
          const w = pendingChoice.get(String(m.ask_id ?? ""))
          if (w) { pendingChoice.delete(String(m.ask_id)); w(m) }
        }
      } catch { /* 非 JSON 忽略 */ }
    })
    ws.on("error", (err) => {
      connectingPromise = null
      hubWS = null
      stopPing()
      reject(err)
    })
    ws.on("close", () => {
      hubWS = null
      stopPing()
      // hub 重启 / 网络抖动 → 自动重连，不等下次 reply tool call
      scheduleReconnect()
    })
  })
  return connectingPromise
}

const server = new Server(
  { name: "cc-bridge-mcp", version: "0.2.0" },
  { capabilities: { tools: {} } }
)

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "reply",
      description: "Send a message to a Memory Palace conversation. Normally used to respond to <channel source=\"memorypalace\"> input (pass its chat_id + message_id). You can ALSO use it proactively at any time to message a conversation without a preceding <channel> — just pass that conversation's chat_id (omit message_id). The message appears as a new message from you.",
      inputSchema: {
        type: "object",
        properties: {
          chat_id: {
            type: "string",
            description: "The chat_id from the <channel> tag",
          },
          message_id: {
            type: "string",
            description: "The message_id from the <channel> tag. Pass it back verbatim so the reply is matched to the exact message (prevents stale replies being mis-routed).",
          },
          content: {
            type: "string",
            description: "Your reply text",
          },
          file_path: {
            type: "string",
            description: "Absolute path of a file to send to the user alongside the reply (image or any file, max 10 MB).",
          },
          thinking: {
            type: "string",
            description: "If you have internal reasoning or a thinking process for this reply, include it here. This will be displayed as a collapsible thinking block in the app.",
          },
        },
        required: ["chat_id", "content"],
      },
    },
    ...PROXY_TOOLS,
  ],
}))

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  // Gateway 工具代理：转发到 Gateway 执行，结果作为文本返回。
  // ⚠️ 本地实现的工具必须先于代理转发处理：它们虽然在 PROXY_TOOLS 里（为了出现在工具列表），
  // 但网关并没有对应实现，转发过去必然失败（兔兔实测 ask_choice 一直调不通）。
  const LOCAL_IMPL = new Set(["ask_choice", "read_chapter", "book_note", "reading_now"])
  if (PROXY_TOOL_NAMES.has(req.params.name) && !LOCAL_IMPL.has(req.params.name)) {
    const text = await proxyToGateway(req.params.name, req.params.arguments ?? {})
    // see_screen 等返回图片的工具：__peek_image__ 结构 → MCP image content（CC 亲眼看原图）
    if (typeof text === "string" && text.includes("__peek_image__")) {
      try {
        const pk = JSON.parse(text)
        if (pk && pk.__peek_image__ && pk.data) {
          return { content: [
            { type: "image", data: pk.data, mimeType: pk.media_type || "image/png" },
            { type: "text", text: `用户当前 iPhone 屏幕截图 · App: ${pk.app || "未知"}` },
          ] }
        }
      } catch {}
    }
    return { content: [{ type: "text", text }] }
  }

  // ── 共读：读她正在看的章节 / 递一条批注 ────────────────────────────
  if (req.params.name === "reading_now") {
    try {
      const raw = readFileSync(READING_PATH, "utf-8")
      const r = JSON.parse(raw)
      const stale = Date.now() - new Date(r.updatedAt).getTime() > 12 * 3600_000
      const head = stale
        ? `（这是 ${r.updatedAt.slice(0, 16).replace("T", " ")} 的记录，她现在未必还在读）\n`
        : ""
      return { content: [{ type: "text", text:
        `${head}《${r.bookName}》第 ${r.chapter}/${r.totalChapters} 章 ${r.chapterTitle}\n` +
        (r.userNotes ? `\n【她的划线与笔记】\n${r.userNotes}\n` : "") +
        `\n【正文】\n${r.text}` }] }
    } catch {
      return { content: [{ type: "text", text: "她现在没在读书（或者阅读器还没打开过）。" }] }
    }
  }

  if (req.params.name === "ask_choice") {
    const a = req.params.arguments as { question: string; options: string[]; multi?: boolean }
    const q = String(a?.question ?? "").trim()
    const opts = (a?.options ?? []).map(String).filter(Boolean).slice(0, 6)
    if (!q || opts.length < 2) throw new Error("要有问题和至少两个选项")
    const askId = Math.random().toString(36).slice(2)
    const ws = await connectHub()
    const answer: any = await new Promise((resolve) => {
      pendingChoice.set(askId, resolve)
      ws.send(JSON.stringify({
        type: "ask_choice", ask_id: askId, question: q, options: opts, multi: !!a?.multi,
      }))
      // 她可能一时没看见——给足时间，超时就当没答
      setTimeout(() => {
        if (pendingChoice.has(askId)) {
          pendingChoice.delete(askId)
          resolve({ skipped: true, reason: "timeout" })
        }
      }, 10 * 60 * 1000)
    })
    if (answer?.skipped) {
      return { content: [{ type: "text", text: answer.reason === "timeout" ? "她没有回应（超时）。" : "她跳过了这个问题。" }] }
    }
    const picked = Array.isArray(answer?.picked) ? answer.picked.join("、") : ""
    const typed = String(answer?.text ?? "").trim()
    return { content: [{ type: "text", text: typed ? `她自己写了：${typed}` : `她选了：${picked}` }] }
  }

  if (req.params.name === "read_chapter") {
    const a = req.params.arguments as { book?: string; chapter?: number }
    const reqId = Math.random().toString(36).slice(2)
    const ws = await connectHub()
    const payload: any = await new Promise((resolve) => {
      pendingChapter.set(reqId, resolve)
      ws.send(JSON.stringify({
        type: "fetch_chapter", req_id: reqId,
        book: String(a?.book ?? ""), chapter: Number(a?.chapter ?? 0),
      }))
      setTimeout(() => {
        if (pendingChapter.has(reqId)) {
          pendingChapter.delete(reqId)
          resolve({ error: "等她 App 回书超时（手机可能没连上）。" })
        }
      }, 15000)
    })
    if (payload?.error) return { content: [{ type: "text", text: String(payload.error) }] }
    const head = payload.chapter > 0
      ? `《${payload.book}》第 ${payload.chapter}/${payload.total} 章 ${payload.title}\n\n`
      : `《${payload.book}》\n\n`
    return { content: [{ type: "text", text: head + String(payload.text ?? "") }] }
  }

  if (req.params.name === "book_note") {
    const a = req.params.arguments as { note: string; quote?: string; book?: string; chapter?: number }
    const note = String(a?.note ?? "").trim()
    if (!note) throw new Error("note 不能为空")
    // 不指定就写她当前在读的那章；指定了就写到那本那章（可以走在她前面留批注）
    let book = String(a?.book ?? "").trim()
    let chapter = Number(a?.chapter ?? 0)
    if (!book || !chapter) {
      try {
        const r = JSON.parse(readFileSync(READING_PATH, "utf-8"))
        if (!book) book = r.bookName
        if (!chapter) chapter = r.chapter
      } catch {
        return { content: [{ type: "text", text: "不知道往哪本书上写——她现在没在读书，也没给我 book / chapter。" }] }
      }
    }
    const ws = await connectHub()
    ws.send(JSON.stringify({
      type: "book_note",
      bookName: book,
      chapter,
      note: note.slice(0, 1000),
      quote: String(a?.quote ?? "").slice(0, 500),
      ts: new Date().toISOString(),
    }))
    return { content: [{ type: "text", text: `批注已递到《${book}》第 ${chapter} 章。` }] }
  }

  if (req.params.name !== "reply") {
    throw new Error(`unknown tool: ${req.params.name}`)
  }
  const args = req.params.arguments as { chat_id: string; message_id?: string; content: string; file_path?: string; thinking?: string }
  // 如果 hub 这一刻断了，等一次重连尝试（最多 retry 几次再放弃）
  let lastErr: Error | undefined
  // 幂等 id 在循环外生成：重试帧带同一个 mp_msg_id，hub 按它去重（"发两遍"雷二）
  const mpMsgId = crypto.randomUUID()
  for (let i = 0; i < 3; i++) {
    try {
      const ws = await connectHub()
      const payload: Record<string, unknown> = {
        type: "reply",
        chat_id: args.chat_id,
        message_id: args.message_id,  // 可选，回带用于精确匹配
        content: args.content,
        mp_msg_id: mpMsgId,
      }
      if (args.file_path) payload.file_path = args.file_path
      if (args.thinking) payload.thinking = args.thinking
      ws.send(JSON.stringify(payload))
      return { content: [{ type: "text", text: "ok" }] }
    } catch (err) {
      lastErr = err as Error
      await new Promise(r => setTimeout(r, 500 * (i + 1)))
    }
  }
  throw new Error(`hub unreachable after retries: ${lastErr?.message ?? "unknown"}`)
})

// 启动时立刻连 hub（不等第一次 reply tool call 才 lazy connect）
// hub 没起时 fail 后自动 backoff 重连，不阻塞 stdio
connectHub().catch(() => scheduleReconnect())

const transport = new StdioServerTransport()
await server.connect(transport)

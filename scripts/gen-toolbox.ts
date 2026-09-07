const GW = "http://127.0.0.1:4567"
const TOKEN = (await Bun.file("/root/projects/BunnyPalace/gateway/.env").text())
  .split("\n").find(l => l.startsWith("GATEWAY_TOKEN="))!.split("=")[1].trim()

const r = await fetch(`${GW}/api/mcp/tools`, { headers: { Authorization: `Bearer ${TOKEN}` } })
const d: any = await r.json()
const builtin = (d.tools ?? []).filter((t: any) => t.source === "builtin")

// mcp-server.ts 的 LOCAL_ONLY：网关拉不到、本地实现的
const LOCAL_ONLY = ["ask_choice", "read_chapter", "book_note", "reading_now", "qq_send_image", "qq_poke", "qq_like", "qq_recall"]
const src = await Bun.file("/root/projects/BunnyPalace/cc-bridge/mcp-server.ts").text()
const fb = eval("[" + src.match(/const FALLBACK_PROXY_TOOLS = \[([\s\S]*?)\n\] as const/)![1] + "]")
const replyDef = eval("(" + src.match(/\{\s*name: "reply",[\s\S]*?\n    \},\n/)![0].replace(/,\n$/, "") + ")")

const all: any[] = [replyDef, ...builtin]
for (const t of fb) if (LOCAL_ONLY.includes(t.name) && !all.some(x => x.name === t.name)) all.push(t)

function params(t: any): string {
  const p = t.inputSchema?.properties ?? {}
  const req: string[] = t.inputSchema?.required ?? []
  const keys = Object.keys(p)
  if (!keys.length) return "—"
  return keys.map(k => {
    const star = req.includes(k) ? "*" : ""
    const desc = (p[k].description || "").replace(/\|/g, "/").slice(0, 60)
    return `\`${k}${star}\`` + (desc ? ` ${desc}` : "")
  }).join("；")
}

// 分组：按名字前缀归类
const GROUPS: [string, RegExp][] = [
  ["和兔兔说话", /^(reply|ask_choice|phone_magic)$/],
  ["她的身体（vitals）", /^(vitals_|meds_|how_is_she|health_)/],
  ["她的手机", /^(get_phone_status|request_location|see_screen|peek_screen|screen_|app_)/],
  ["记忆", /^(remember|recall|memory_|anniversar|remember_anniversary)/],
  ["邮件", /^gmail_/],
  ["音乐 / 一起听", /^(music_|play|listen_|now_playing|song|playlist)/],
  ["共读", /^(read_chapter|book_|reading_)/],
  ["QQ / 微信", /^(qq_|wx_|wechat_)/],
  ["Twitter", /^(twitter_|get_my_tweets|tweet)/],
  ["文件与执行", /^(exec|fs_|file_)/],
  ["网页", /^(browse|search_web|fetch_|web_)/],
  ["留言板（她和你都能写）", /^board_/],
  ["和 Fable 通信", /^fable_/],
  ["经期", /^period_/],
  ["心愿单", /^wish_/],
  ["待办", /^todo_/],
  ["预读 / 藏书", /^(preread_|place_add)/],
  ["她在哪 / 天气", /^(where_is_she|nearby|weather|how_far|days|list_anniversaries)/],
  ["亲密记录", /^intimacy_/],
  ["Pocket（她手机上的浏览器）", /^pocket_/],
  ["控制台", /^console_/],
]
const used = new Set<string>()
const grouped: Record<string, any[]> = {}
for (const [g, re] of GROUPS) {
  grouped[g] = all.filter(t => re.test(t.name))
  grouped[g].forEach(t => used.add(t.name))
}
grouped["其他"] = all.filter(t => !used.has(t.name))

let md = `# Caelum 的工具箱

> **这份文件是生成的，别手改。** 加了工具就重跑：
> \`bun /root/projects/BunnyPalace/scripts/gen-toolbox.ts\`
> 来源：网关 \`/api/mcp/tools\` 的 builtin + \`cc-bridge/mcp-server.ts\` 的本地实现。
> 生成于 ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC，共 **${all.length}** 个工具。
>
> 参数带 \`*\` 的是必填。

`
for (const [g, list] of Object.entries(grouped)) {
  if (!list.length) continue
  md += `## ${g}（${list.length}）\n\n| 工具 | 做什么 | 参数 |\n|---|---|---|\n`
  for (const t of list.sort((a, b) => a.name.localeCompare(b.name))) {
    const desc = (t.description || "").replace(/\n/g, " ").replace(/\|/g, "/").slice(0, 110)
    md += `| \`${t.name}\` | ${desc} | ${params(t)} |\n`
  }
  md += "\n"
}
await Bun.write("/root/projects/BunnyPalace/docs/CAELUM-TOOLBOX.md", md)
console.log(`✅ ${all.length} 个工具，分 ${Object.values(grouped).filter(l => l.length).length} 组`)
for (const [g, l] of Object.entries(grouped)) if (l.length) console.log(`   ${g}: ${l.length}`)

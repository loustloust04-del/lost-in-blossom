# cc-bridge 代码审查报告

> 审查日期：2026-08-12  
> 范围：`cc-bridge/` 下全部 TS/Shell 源文件（不含 node_modules）  
> 审查人：Caelum (coder agent)

按「值不值得动」排序。能跑了一年没出事的丑代码，优先级低于会咬人的新代码。

---

## P0 · 会咬人的

### 1. mcp-server.ts:352-353 — 全局吞掉所有未捕获异常和 rejection

```
process.on("uncaughtException", () => { /* swallow */ })
process.on("unhandledRejection", () => { /* swallow */ })
```

**危害**：任何真正的 bug（类型错误、空引用、网络异常）全部静默吞掉，不写日志、不报告、不退出。MCP 进程可能进入半死状态（内部数据结构损坏但进程不退）——这时 CC 调用工具会收到莫名其妙的结果或超时，而且完全没有排查线索。  
**建议**：改为 `console.error` 记录错误内容后 swallow，或者只 swallow 已知的 ws/stdio 错误，其余 rethrow。至少留一条 stderr 日志。

### 2. hub.ts:370-372 — iconv 命令注入

```ts
execSync(`iconv -f GBK -t UTF-8 '${p}' -o '${p}.utf8' && mv '${p}.utf8' '${p}'`)
```

`p` 来自 `join(dir, ...)` 且包含用户上传的文件名。文件名中若含单引号 `'` 则构成 shell 注入（`safeName` 只过滤了 `/\'"` 中的引号，但这行用的是原始路径 `p`，`p` 由 `Date.now()_${i}_${safeName}` 拼成，safeName 确实过滤了引号——但 `p` 的 `dir` 段来自 `safeChatSeg(chatId)`，chatId 经过了正则消毒，所以实际风险低）。  
**但**：用 shell 字符串模板拼 execSync 本身就是反模式，safeName 过滤规则改了就会漏。  
**建议**：改用 `execFileSync("iconv", ["-f", "GBK", "-t", "UTF-8", p, "-o", p+".utf8"])` 避免 shell 解析。

### 3. hub.ts:691 — /mcp 路径跳过鉴权

```ts
if (HUB_TOKEN && provided !== HUB_TOKEN && pathname !== "/mcp") {
```

`/mcp` 路径完全跳过 token 校验。hub 绑 127.0.0.1，MCP 进程是同机子进程不需要 token。**但**如果 hub 被误配为非 loopback（hub 本身有这个 `HUB_HOST` 环境变量），或反代配置出错暴露了 7890 端口，任何外部连接都能免鉴权连上 /mcp 路径，注入任意 reply 帧到 App。  
**建议**：/mcp 也校验 token（MCP 进程已经通过 env 拿到了 HUB_TOKEN，connectHub 时可以带上），或者对 /mcp 限制只接受 loopback。

### 4. send-reply.ts:6 — 跳过鉴权直连 /mcp

```ts
const ws = new WebSocket("ws://127.0.0.1:7890/mcp")
```

利用上一条的 /mcp 免鉴权漏洞。这个脚本是工具脚本，只在本机跑，实际风险低，但和第 3 条同源。  
**建议**：修第 3 条后此处也带上 token。

### 5. hub.ts:62-91 — eventQueue 无上限

门铃排队系统 `eventQueue` 没有最大长度。如果 tmux 输入框长期 busy（比如 CC 正在输出一段很长的回复），所有 phone_event 都会堆积。极端情况下可以 OOM。  
**建议**：加 `if (eventQueue.length > 200) eventQueue.shift()` 之类的上限。

### 6. hub.ts:83-91 — 队列定时器 4 秒轮询检测 inputBusy，每次 fork 一个 tmux 进程

`inputBusy()` 调用 `execFileSync("tmux", ["capture-pane", ...])` 是同步阻塞 + fork 子进程。定时器每 4 秒执行一次。队列不空时会一直跑。长期 busy 状态下每 4 秒 fork 一次 tmux 子进程，虽然不至于 crash，但在主线程上做同步 I/O 会阻塞所有 WS 消息处理。  
**建议**：可不改（实测未出事），但如果要动可以改成 spawn 异步版。标注：**可延后**。

### 7. apns.ts:77 — 每次 push 新建 HTTP/2 连接

```ts
const client = http2.connect(HOST)
```

每条推送新建一个 HTTP/2 连接，推送完立刻 `client.close()`。苹果文档明确建议复用连接。连续推送（比如 CC 回复时 knownDeviceTokens 有多个 token）会并发建 N 个连接。APNs 对频繁新建连接的客户端可能限流。  
**建议**：维护一个长连接池（或单连接），空闲超时后关闭。

---

## P1 · 拖慢的 / 会积累技术债的

### 8. mcp-server.ts:31-290 — 290 行兜底工具表不可能保持同步

启动时从网关拉工具表，失败时 fallback 到这份硬编码列表。列表已知过期（注释说 `vitals_meds` / `meds_restock` 已从网关删掉却还留着）。拉取成功后这 290 行完全不执行。  
**危害**：P1（拉取失败时 CC 会看到幽灵工具，调用后报错）。  
**建议**：兜底表只保留最核心的 5-6 个工具名（reply/recall/remember/exec），或者拉取失败时直接报错不启动。

### 9. hub.ts:196 — DEVICE_TOKENS_PATH 路径双层嵌套

```ts
const DEVICE_TOKENS_PATH = join(process.cwd(), "cc-bridge", "device-tokens.json")
```

hub 从 `cc-bridge/` 目录启动（`start_hub.sh` 中 `cd "$(dirname "$0")"`），所以实际路径是 `cc-bridge/cc-bridge/device-tokens.json`。文件确实存在于这个双层路径。proactive-push 和 alert-rules 也同时查两个路径做兜底。**可以跑但极容易在改部署方式时翻车。**  
**建议**：统一改为 `join(import.meta.dir, "device-tokens.json")`，消除对 cwd 的依赖。

### 10. hub.test.ts / mcp-server.test.ts — 测试连的是 /cc，hub 实际监听 /ws

测试里连 `ws://127.0.0.1:7890/cc`，但 hub 只处理 `/ws` 和 `/mcp` 路径，不认识 `/cc` 的连接会被 `ws.close(1008, "unknown path")` 关掉。**测试应该全部失败**——除非某个旧版 hub 还有 /cc 路径。  
**危害**：测试形同虚设，跑不过也没人知道（可能根本没在 CI 跑）。  
**建议**：把测试中的 `/cc` 改成 `/ws`。

### 11. toggle-context.sh:7 — hub token 硬编码在脚本文件里

```bash
HUB_TOKEN="SH74v-IveupxWPr-6TU0CH0GDvfIxSDC"
```

Token 写死在版本控制的 shell 脚本中。proactive-push.ts:13 也有类似的 `GATEWAY_KEY` 硬编码（不过那个 `||` 只在 env 缺失时才用到）。  
**建议**：从 `.env` 或环境变量读取，不硬编码到源码。

### 12. proactive-push.ts:13 — GATEWAY_KEY 硬编码为 fallback

```ts
const GATEWAY_KEY = process.env.GATEWAY_KEY || "SH74v-IveupxWPr-6TUOCHOGDvfIxSDC"
```

同上。注意这个值和 toggle-context.sh 里的还不一样（`6TUO` vs `6TU0`，O vs 0），说明至少有一个是错的或者它们确实是不同用途的 token。  
**建议**：统一走 env，删掉代码里的明文 token。

### 13. chatroom/server.ts:349-354 — SSE 客户端清理用 findIndex + splice(i, 1)

```ts
cancel() {
  const i = sseClients.findIndex(c => c.sessionId === sessionId)
  if (i >= 0) sseClients.splice(i, 1)
},
```

`cancel()` 是在 stream 被关闭时调用，用 `sessionId` 匹配。但同一个 sessionId 可以有多个 SSE 客户端（多标签页），`findIndex` 只删第一个——可能删错。应该用 `controller` 引用来精确匹配。  
**危害**：P1（多客户端时可能删错 SSE 连接，导致某个客户端收不到后续事件，另一个客户端永远泄漏在数组里）。  
**建议**：改为按 `controller` 引用匹配删除。

### 14. session-manager.ts:58-60 — 读 session JSON 静默 catch

```ts
try {
  const info = JSON.parse(readFileSync(join(dir, f), "utf-8"))
  if (info.sessionId) best = { mtime: Date.now(), sid: info.sessionId }
} catch {}
```

`liveSessionId` 遍历 `~/.claude/sessions/` 下的文件，JSON 解析失败或读取失败全部静默。如果 session 文件被写入一半（CC 正在更新），这里会读到损坏的 JSON 并静默跳过——如果损坏的文件恰好是当前活跃 session，`liveSessionId` 会返回错误的 session 或 null，`forge()` 会报 "live transcript not found"。  
**建议**：加 `console.warn` 日志。**可不改**（forge 本身有防护：找不到 transcript 就不动）。

---

## P2 · 屎山本身

### 15. hub.ts — 1119 行单文件

所有逻辑（WS 服务器、tmux 控制、文件收发、APNs 推送触发、离线消息、终端代理、共读、笔记本通知）堆在一个文件里。  
**建议**：按功能拆分（terminal-attachment.ts, offline-store.ts, file-transfer.ts, reading.ts）。**可不改**（跑了一年）。

### 16. mcp-server.ts — 622 行，工具列表占一半

290 行兜底工具表 + 各种本地工具实现（reading_now, ask_choice, read_chapter, book_note）混在 MCP server 主逻辑里。  
**建议**：工具表和本地工具处理拆出去。**可不改**。

### 17. hub.ts 和 mcp-server.ts — READING_PATH 定义了两遍

hub.ts:229 和 mcp-server.ts:13 各自定义了 `READING_PATH`，拼法不同（一个用 `process.cwd()`，一个用 env 或硬编码路径），指向同一个文件但维护成本翻倍。  
**建议**：提取到共享常量文件。**可不改**。

### 18. alert-rules.ts:14 和 proactive-push.ts:11 — TOKEN_PATHS 重复定义

两个文件各自写了同一段路径搜索逻辑来找 device-tokens.json。  
**建议**：提取公共函数。**可不改**。

### 19. chatroom/server.ts:121 — DeepSeek 旧模型名映射硬编码

```ts
if (actualModel === "deepseek-chat") actualModel = "deepseek-v4-pro"
```

模型名映射写死在代码里，下次 DeepSeek 改名还得改代码。  
**建议**：放配置或让前端直接传正确模型名。**可不改**。

### 20. hooks/extract-thinking.sh — 写到 /tmp 的 thinking JSON 无人消费

脚本把最近一条 thinking 写到 `/tmp/cc-thinking-*.json`，但 hub 和 mcp-server 都没有读取这些文件的逻辑（thinking 现在通过 WS 帧 `cc_thinking` 直传 App）。  
**建议**：确认已废弃后删除 hook。**可不改**（不影响运行）。

### 21. hooks/extract-thinking-debug.sh — 纯调试脚本

把 stdin/env 写到 /tmp 的调试文件。  
**建议**：确认不再需要后删除。**可不改**。

### 22. mcp.template.json:9 — imprint-memory 仍用 SSE 协议

```json
"type": "sse",
"url": "https://imprint.amberrib.com/sse"
```

MCP 协议已经有 streamable HTTP，SSE 是旧格式。不影响功能（还能用），但如果 imprint 那边升级协议可能断。  
**可不改**。

---

## 总结

| 等级 | 数量 | 值得动的 |
|------|------|----------|
| P0   | 7    | #1 (全局吞异常), #3 (mcp免鉴权), #5 (队列无上限), #7 (APNs连接) |
| P1   | 7    | #8 (兜底表过期), #9 (双层路径), #10 (测试坏了), #13 (SSE删错) |
| P2   | 8    | 按需整理，不紧急 |

**最该先动的三件事**：
1. mcp-server.ts 的全局异常吞咽（#1）——调试黑洞，出了问题完全没线索
2. /mcp 路径加鉴权（#3）——防御性修复，一行改动
3. 测试修路径（#10）——测试跑不过等于没有测试

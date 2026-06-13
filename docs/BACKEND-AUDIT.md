# 后端审查报告 · BACKEND-AUDIT

> 审查人：Claude（后端审查任务）
> 日期：2026-06-13
> 范围：`/root/projects/BunnyPalace/gateway/`（Hono + Bun 网关，~2000 行）、
> `/root/projects/BunnyPalace/cc-bridge/`（CC Bridge hub + MCP + chatroom）
> 参考：`docs/BACKEND-BIBLE-SUPPLEMENT.md`、`docs/GATEWAY-HANDOFF-COMPLETE.md`

审查方式：通读 VPS 上的全部源码 + systemd 服务 + nginx 反代 + ufw 防火墙配置。

---

## 0. 优先级速览

| # | 问题 | 类别 | 优先级 |
|---|------|------|--------|
| S1 | CC Bridge 鉴权可被 nginx 反代绕过 → 远程命令执行面 | 安全 | 🔴 P0 |
| S2 | Chatroom 服务零鉴权 + IDOR，任何人可烧 API 额度 | 安全 | 🔴 P0 |
| S3 | Gateway Token 弱口令且明文写进交接文档 | 安全 | 🔴 P0 |
| S4 | 入站文件落盘存在路径穿越（chatId 未消毒） | 安全 | 🟠 P1 |
| S5 | Supabase 用 service/anon key 直连，无行级隔离与多用户边界 | 安全/架构 | 🟠 P1 |
| A1 | 记忆系统全局单租户，无 `profile_id`/`user_id` 隔离 | 架构 | 🟠 P1 |
| A2 | 定时器（decay/dream/desire）依赖单进程内存状态，无幂等/补偿 | 架构 | 🟠 P1 |
| A3 | 转发层错误处理缺失，上游异常会变成 App 端裸 500/挂死 | 架构 | 🟠 P1 |
| A4 | 备份/降级缺失：Supabase 挂掉时记忆静默丢失 | 架构 | 🟡 P2 |
| P1 | retriever 每轮 N+1 串行查询 Supabase（侧翼检索循环） | 性能 | 🟠 P1 |
| P2 | decay 全表逐行 UPDATE，无批处理 | 性能 | 🟡 P2 |
| P3 | `compressForStorage` 用灾难性回溯正则扫全文 | 性能 | 🟡 P2 |
| P4 | 每条消息同步算 embedding，阻塞提取链路 | 性能 | 🟡 P2 |

---

## 1. 架构问题

### A1. 记忆系统是全局单租户的（无隔离）🟠 P1

**现象**：App 端 `Memory` 模型有 `profileId`（楼层隔离），但 Gateway 端 Supabase 的
`memories`/`messages` 表完全没有 `user_id` 或 `profile_id` 字段。`retrieveMemories`、
`extractMemoriesIfNeeded`、`runDream`、`runDesireCheck` 都是对整张表无差别操作。

```ts
// retriever.ts —— 没有任何 user/profile 过滤
const { data: vectorHits } = await supabase.rpc('match_memories', {
  query_embedding, match_threshold: 0.55, match_count: 6,
});
```

**影响**：当前只服务一个人（兔兔），所以"能跑"。但：
- App 的多楼层（profile）记忆全部塌缩成后端的一锅粥，楼层 A 的记忆会注入到楼层 B 的对话。
- 任何未来的多用户/多角色扩展都要推翻重做。
- `session_id` 来自 `X-Session-Id` header，但记忆检索根本不按 session 隔离。

**修复**：给 `memories`/`messages`/`dream_log`/`persona_state` 加 `owner_id`（或
`profile_id`）列，所有查询带 `.eq('owner_id', ...)`，并配 Supabase RLS。即使短期单用户，
也先把列加上、查询带上，避免日后数据污染无法回滚。**优先级 P1**。

### A2. 三个定时器依赖单进程，无幂等与补偿 🟠 P1

`index.ts` 用 `setInterval` 起了 decay（6h）、dream（每小时查是不是 4 点）、desire（2h）。

问题：
- **进程重启即丢状态**：`setTimeout` 的"30 秒后首跑"和"凌晨 4 点"判断全在内存里。
  服务半夜重启一次，当天的 dream/日摘要就漏跑，没有补偿机制。
- **dream 判断脆弱**：`if (new Date().getHours() === 4)` —— 如果那一小时 tick 恰好错过
  （GC 卡顿、重启），整天不触发。`getHours()` 还依赖服务器时区，没显式 UTC。
- **多实例不安全**：将来横向扩两个 gateway 实例，三个定时器会并发重复跑 dream，
  产生重复摘要、重复 persona 行。

**修复**：把定时任务挪到带去重锁的调度（Supabase 里建 `job_runs(job, run_date)` 唯一约束，
跑前 `INSERT ... ON CONFLICT DO NOTHING`，抢到才执行），或用外部 cron + 一次性脚本。
dream 改成"查 `dream_log` 看今天跑过没"而不是"看现在几点"。**优先级 P1**。

### A3. 转发层错误处理缺失 🟠 P1

`providers/*.ts` 的四个 `forward*` 函数都是裸 `fetch` + 直接把 `upstream.body` 透传：

```ts
const upstream = await fetch(BASE, {...});       // 网络异常 → 抛出，无 catch
return new Response(upstream.body, { status: upstream.status, ... });
```

- 上游 `fetch` 抛异常（DNS/超时/连接重置）时，`app.ts` 里没有 try/catch 包住转发段，
  Hono 会回一个未格式化的 500，App 端拿到的不是 OpenAI 兼容错误体。
- `enhanceMessages` 有 try/catch 兜底（好），但转发本身没有。
- 非流式分支 `const data = await upstream.json()`：上游返回非 JSON（HTML 错误页、网关 502）
  时直接抛，同样裸奔。
- 没有超时控制：上游卡住，App 的连接也一起卡死，没有 `AbortSignal.timeout`。

**修复**：转发统一包一层，捕获后返回 OpenAI 风格错误
`{ error: { message, type, code } }` + 合适状态码；给所有上游 `fetch` 加
`signal: AbortSignal.timeout(60_000)`；非流式 `json()` 前先判 `content-type`。**P1**。

### A4. Supabase 是单点，挂掉时记忆静默丢失 🟡 P2

`saveMessage`/`saveMemory`/提取写入全是 `.catch(() => {})` 或只 `console.error`。
Supabase 故障时：用户消息存不进、记忆提取静默失败、检索返回空 → AI 突然"失忆"，
而 App 端毫无感知。`db/supabase.ts` 还在模块加载时无条件 `createClient`，URL 为空也不报。

**修复**：写失败进本地落盘队列（类似 cc-bridge 的 `offline/` 机制）后台重试；
`/health` 端点实际探测一次 Supabase 连通性而不是只看 `config.supabaseUrl` 是否非空。**P2**。

### A5. 双重记忆系统并存且互不相通（架构耦合）🟠 P1

这是最值得点名的架构问题，详见 `MEMORY-SYNC-PLAN.md`：

- **App 端**：`MemoryService.swift` 一套本地 SwiftData 记忆（`decayWeight`/`category`/
  `isUserExplicit`/`profileId`），由 `ConversationViewModel` 调用聊天模型自行提取。
- **Gateway 端**：Supabase 一套完全不同 schema 的记忆（`heat`/`tier`/`valence`/`arousal`/
  `is_anchor`/`embedding`），由 `extractor.ts` 调 deepseek 提取。

两套系统字段不兼容、提取逻辑重复、永不同步。同一句话可能被提取两次（App 一次、Gateway 一次），
也可能哪边都没存。**修复方向见专门文档**。**P1**。

---

## 2. 安全问题

### S1. CC Bridge 鉴权被 nginx 反代绕过 → RCE 面 🔴 P0

`hub.ts` 的鉴权逻辑：

```ts
// 非 loopback 连接才校验 token
if (!isLoopback(remote)) {
  const provided = reqUrl.searchParams.get("token")
  if (provided !== HUB_TOKEN) { ws.close(1008, "auth"); return }
}
```

`remote = req.socket.remoteAddress`。而 nginx（`/etc/nginx/sites-enabled/ip-mcp`）把
`8890/cc/`、`443/cc`、`443/mcp` 全部 `proxy_pass http://127.0.0.1:7890`。**经过 nginx 的
所有公网连接，到达 hub 时 remoteAddress 都是 `127.0.0.1`** → `isLoopback` 返回 true →
**token 校验被完全跳过**。nginx 虽然传了 `X-Real-IP`，但 hub 根本没读。

后果：任何能访问 `172.245.88.103:8890` 的人（ufw 对 8890 是 `ALLOW IN Anywhere`）都能：
- 发 `spawn_cc` 启动 `claude --continue --dangerously-skip-permissions`（hub 的 `spawn` 实现）——
  即在 VPS 上拉起一个跳过所有权限确认的 Claude Code 会话 = **任意命令执行通道**。
- 发 `chat` 把任意文本 `tmux send-keys` 注入正在运行的 CC 会话。
- 发 `register_device` 投毒 APNs 推送目标。

**修复（P0，立即）**：
1. hub 改为信任 `X-Real-IP`/`X-Forwarded-For`（仅当来源是本机 nginx 时），用真实客户端 IP
   判 loopback；或更简单——**对所有连接一律强制校验 token，删掉 loopback 豁免**，
   本机 MCP/App 也带上 token。
2. ufw 关掉公网 8890，CC Bridge 只走 443 + 强 token。
3. `spawn_cc` 这种能起 `--dangerously-skip-permissions` 的能力，额外加独立授权，不与普通 chat 同权限。

### S2. Chatroom 服务零鉴权 + IDOR 🔴 P0

`cc-bridge/chatroom/server.ts` 监听 `*:3300`（**所有网卡**，非 loopback），
nginx `443/chatroom/ → 127.0.0.1:3300`。所有路由 **没有任何鉴权**：

```ts
app.use("/*", cors())                         // 全开 CORS
app.post("/chatroom/start", ...)              // 无 auth：触发 AI 对话，烧 OpenRouter/DeepSeek 额度
app.post("/chatroom/send", ...)               // 无 auth
app.delete("/chatroom/:id", ...)              // 无 auth + IDOR：任意 id 可删
app.get("/chatroom/history/:id", ...)         // 无 auth + IDOR：任意 id 可读全部对话
```

后果：任何人可无限调用 `/chatroom/start` 直接消耗你的 API key 余额（DoS 钱包）；
可用任意 UUID 读/删别人的聊天记录。session_id 是 UUID 不可枚举，但一旦泄露即全开。

**修复（P0）**：chatroom 套同一套 Bearer token 中间件；监听改 `127.0.0.1:3300`；
write/delete 操作校验归属；考虑给 `/chatroom/start` 加速率限制。

### S3. Gateway Token 弱口令且明文外泄 🔴 P0

- `GATEWAY_TOKEN=<redacted — rotate & store in .env only>` —— 可猜测的弱口令，且**明文写在
  `docs/GATEWAY-HANDOFF-COMPLETE.md` 第三节**（"Gateway Token | <redacted — rotate & store in .env only>"）。
  该文档若进过任何 git 仓库或被分享，token 即泄露。
- `MP_APNS_*`、APNs `.p8` 路径、Team/Key ID 全部硬编码在 `apns.ts` 默认值里。
- `auth.ts` 用 `!==` 明文比较 token —— 理论上有时序侧信道（影响小，但可顺手用
  `crypto.timingSafeEqual`）。

**修复（P0）**：换成 32+ 字节随机 token，从环境注入，从所有文档里删掉明文值并轮换；
APNs 配置全部走 env。`.env`/`.env.save` 已在 `.gitignore` 里且未被 git 跟踪（已确认 ✅），
保持如此。

### S4. 入站文件落盘路径穿越 🟠 P1

`hub.ts` 的 `saveInboundImages`/`saveInboundFiles`：

```ts
const dir = join(INBOUND_DIR, chatId.slice(0, 16))   // chatId 未消毒
```

`chatId` 来自 App 消息，未过滤 `../`。`chatId = "../../../../tmp"` → `slice(0,16)` 仍含
`../../../../tm` → `join` 后逃出 `inbound/` 目录。文件名虽然过滤了 `/\'"`，但目录这层没防。
配合 S1 的鉴权绕过，攻击者可控制写入路径。

**修复（P1）**：`chatId` 白名单化（`replace(/[^A-Za-z0-9_-]/g, '_')`）后再用；
落盘前 `resolve` 校验最终路径仍在 `INBOUND_DIR` 内。`stageOutboundFile` 读 CC 给的
`file_path` 同理应限制在白名单目录内（防 CC 被诱导读 `/etc/shadow` 回传 App）。

### S5. Supabase 直连无 RLS 边界 🟠 P1

`supabase.ts` 用 `SUPABASE_KEY` 建客户端。若该 key 是 service_role，则 gateway 进程一旦
被攻陷（见 S1/S2），攻击者即拿到整库读写。结合 A1（无 user 隔离），数据面没有纵深防御。

**修复（P1）**：确认用的是受 RLS 约束的 key；给所有表开 RLS；service_role key 只用于
确需绕过 RLS 的后台任务，且这部分代码与对外转发进程隔离。

### S6. SSRF / 参数透传面（信息记录）🟡 P2

`/v1/chat/completions` 把 App 传来的 `body` 几乎原样转发给上游（只删 `top_p`、改 `model`）。
上游地址是固定白名单（deepseek/openrouter/treegpt），**不存在经典 SSRF**（用户不能控制目标 URL）。
但需注意：`reasoning`、`session_id` 等被无条件注入；App 可传任意 `max_tokens`/工具定义，
配合无速率限制 = 成本放大。属于"成本型滥用"而非 SSRF，归到限流一并处理。**P2**。

---

## 3. 性能瓶颈

### P1. retriever 的 N+1 串行查询 🟠 P1

`retrieveMemories` 每轮对话要打 Supabase 很多次，且**串行**：
1. 向量搜索 1 次 + 关键词 1 次 + 锚点 1 次（主记忆）
2. 时间侧翼：`for (primary of primaryResults.slice(0,3))` → **最多 3 次串行查询**
3. 情感侧翼：又一个 `slice(0,3)` 循环 → **再 3 次串行查询**
4. `getTodayMarkers` 1 次

单轮对话光检索就 ~11 次往返 Supabase，全部 `await` 串行。每次往返按 30–80ms 算，
检索就吃掉 0.5–1s，直接加到首 token 延迟上。

**修复（P1）**：侧翼的两个循环用 `Promise.all` 并发；或更好——把时间/情感侧翼合并成
一个 SQL/RPC（`OR` 条件 + 一次返回），用数据库做扩散激活而不是应用层循环。

### P2. decay 全表逐行 UPDATE 🟡 P2

`runDecay` 取出所有 `heat > 0.02` 的记忆后，`for` 循环里逐条 `await supabase.update()`。
记忆上千条时就是上千次串行写。6 小时一次还能忍，但随数据增长会变成长尾卡顿。

**修复**：改成一条 SQL 批量更新（`UPDATE memories SET heat = heat * exp(...) WHERE ...`，
衰减公式纯数学，完全可以下推到 Postgres），或分批 `upsert`。**P2**。

### P3. `compressForStorage` 灾难性回溯正则 🟡 P2

```ts
const jsonBlockPattern = /\{[\s\S]{500,}\}/g;   // 贪婪 + 任意字符，长文本上回溯爆炸
```

`{[\s\S]{500,}}` 对每条消息全文跑，遇到大段含很多 `{` 的文本会触发指数级回溯，
单条消息可能卡住事件循环。`base64Pattern.test()` 之后又 `replace` 一遍，重复扫描。

**修复**：JSON 检测改为先按长度门槛切块或用非回溯解析（找平衡括号），别用贪婪正则扫全文；
`test` + `replace` 合并成一次 `replace`。**P2**。

### P4. embedding 同步阻塞提取 🟡 P2

`extractor.ts` 的 `executeActions` 里，每个 `add` 都 `await embed(action.content)` 后才插库，
串行。一轮提取出 5 条记忆 = 5 次串行 embedding API 调用。虽然整个提取是异步触发
（不阻塞对话），但链路本身慢，且 embedding 失败无重试（回退为无向量，之后只能关键词命中）。

**修复**：批量 `embedBatch`（代码已有该函数，没用上）一次算完所有新记忆的向量；
embedding 失败的记忆标记 `embedding IS NULL`，后台 `backfill-embeddings.ts` 补（脚本已存在）。**P2**。

### P5. 流式 thinking 转换每行 JSON.parse + 重新 stringify 🟡 P3

`app.ts` 的 thinking 流处理对每个 SSE 行 `JSON.parse` → 改对象 → `JSON.stringify` 再写出。
高频小包下 CPU 开销不小，但属于功能正确性必需，影响有限。**P3，低优先级**，
可在 profiling 确认是瓶颈后再优化（如只在含 `reasoning` 字段时才解析）。

---

## 4. 代码质量与可维护性（次要）

- **重复的提取 prompt**：`extractor.ts` 和 App 的 `MemoryExtractor.swift` 维护两份几乎一样的
  中文提取 prompt，改一处忘另一处。建议后端做唯一真相源，App 不再本地提取（见 sync plan）。
- **`hub.ts` 749 行单文件**：tmux、文件落盘、APNs、WS 路由全挤在一个文件，
  建议拆 `transport/`、`files/`、`push/`。
- **散落的 `.bak`/`.bak.<ts>` 文件**：`cc-bridge/hub.ts.bak`、`hub.ts.bak.1780530843` 等
  残留在工作目录，含旧鉴权逻辑，应删除（避免误部署旧版、避免泄露历史 token）。
- **`generateImageDescription` 是 TODO 空实现**：`compressForStorage` 标了
  `needsVisionSummary` 但没人消费，图片占位符永远不会被回填成描述。要么实现要么删标记。
- **`/v1/desires` 端点无人调用**：见 `FRONTEND-BACKEND-MAP.md`，desire 写了没人读。

---

## 5. 立即行动清单（按顺序）

1. **S1**：删掉 hub 的 loopback 鉴权豁免（或改信任 X-Real-IP），ufw 关公网 8890。
2. **S2**：chatroom 加 Bearer 鉴权 + 改监听 127.0.0.1。
3. **S3**：轮换 `GATEWAY_TOKEN` 为随机强口令，从文档删除明文。
4. **S4**：消毒 `chatId` 防路径穿越。
5. **A3**：转发层包 try/catch + 超时，返回 OpenAI 风格错误。
6. **A1 / A5**：规划记忆系统的用户隔离与前后端同步（见后续文档）。

P0 三项是"现在就有人能打"的洞，应优先于一切功能开发。

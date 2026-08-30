# Gateway 代码审查报告

> 审查范围：`/root/projects/BunnyPalace/gateway/src/` 全部 TypeScript 文件
> 日期：2026-08-12
> 审查人：Caelum (code-audit agent)
> 原则：按「值不值得动」排序，不按「有多丑」排序

---

## P0 · 会咬人的

### 1. desire.ts:339 — `saveMemory` 调用签名错误，静默产生废数据

`exploreInternet()` 调用 `saveMemory(summary, 'exploration', 2)`，传了三个位置参数。但 `store.ts:38` 的 `saveMemory` 接受单个对象 `{ content, category, tier, ... }`。第一个参数 `summary`（字符串）被当作 `opts`，`opts.content` 为 `undefined`，后续 `embed(undefined)` 大概率抛错或生成垃圾向量。即使不崩，写入的记忆条目内容为空。

**建议**：改为 `saveMemory({ content: summary, category: 'exploration', tier: 2 })`。

### 2. sync.ts:83 vs desire.ts:143 — 欲望查询两套口径，数据互相看不见

- `sync.ts:listDesires` 查 `session_id = 'desire'`
- `desire.ts:saveDesire` 写入的 `session_id` 取自最近活跃会话（`recent?.[0]?.session_id || 'desire'`），且标记 `model: 'desire-engine'`
- `desire.ts:getUnreadDesires` 查 `model = 'desire-engine'`

结果：`listDesires`（给 App 用的同步接口）只能查到 fallback 到 `session_id='desire'` 的旧数据，查不到写入正式 session 的新数据。App 和 gateway 看到的欲望列表不一致。

**建议**：统一查询策略，`listDesires` 也按 `model = 'desire-engine'` 筛选。

### 3. claude-p.ts:101 — stderr 静默吞掉，CLI 报错无从得知

`proc.stderr.on("data", () => {})` 把所有 stderr 数据丢弃。如果 `claude` CLI 进程报错（鉴权失败、配额耗尽、二进制崩溃），调用方完全不知道发生了什么，流式响应会静默结束。

**建议**：至少 `console.warn('[claude-p] stderr:', chunk.toString())` 记一下。

---

## P1 · 拖慢的

### 4. desire.ts:332 — `child_process.exec` 跑 curl，绕过网关已有的搜索能力

`exploreInternet()` 用 `exec('curl -s "https://html.duckduckgo.com/..."')` 做搜索。网关已经有 `tools/websearch.ts`（Playwright + Google/DDG/Bing fallback），功能更强、结果更干净。shell exec 多一层进程开销，且 `topic` 来自 LLM 输出，虽然经过 `encodeURIComponent` 但仍有边际注入风险。

**建议**：改用 `callWebSearch` 或直接 `fetch` DDG。

### 5. dreamer.ts — 每小时轮询检查是否到 4 点

dreamer 启动后每小时检查一次当前时间是否在 4:00-4:59。一天只触发一次的任务用 24 次轮询来等，浪费 23 次。

**建议**：算出距下次 4:00 的毫秒数，用 `setTimeout` 精确调度。

### 6. murmur.ts — 30 分钟轮询检查是否到 4 点 / 14 点

同上模式，一天两次的任务用 48 次轮询来等。

**建议**：同 dreamer，改用 `setTimeout` 精确调度。

### 7. retriever.ts:115-165 — flanking retrieval 顺序执行 6 次 Supabase 查询

侧翼检索循环中，每次迭代都发一条 Supabase 查询，最多 6 次串行。在高延迟网络下，这段占检索总时间的大头。

**建议**：用 `Promise.all` 并行发查询。

### 8. prompt/builder.ts — 每条消息触发 5+ 次串行 Supabase 查询

`enhanceWithContext` 依次查 persona_state、calendar_summaries、recent conversations、memory retrieval、history search。这些查询之间无依赖，可以并行。

**建议**：用 `Promise.all` 包裹无依赖的查询。

### 9. memory/decay.ts — 热度衰减逐条 UPDATE

`runDecay` 遍历所有记忆条目，逐条发 Supabase UPDATE。记忆量大时 N 次网络往返。

**建议**：改用 Supabase RPC 或批量 UPDATE（一条 SQL 搞定）。

---

## P2 · 屎山本身

### 10. vitals.ts:77-83 — `vitals_meds` handler 是死代码

`callVitalsTool` 里有 `vitals_meds` 的处理分支（line 77-83），但 `VITALS_TOOLS` 数组里没有注册 `vitals_meds` 这个工具。吃药记录已迁到独立的 `meds.ts`。这段代码不会被执行到。

**建议**：删除 77-83 行。

### 11. vitals.ts:112-118 — `console_write` 残留代码不可达

`callConsoleTool` 在 line 100 `if (name !== 'console_read') return null`，line 102 再 `if (name === 'console_read')` 必然为真并 return。lines 112-118 是已删除的 `console_write` 逻辑的残骸，永远不会执行。

**建议**：删除 112-118 行。

### 12. treegpt.ts:48-67 — `forwardTreeAws` 已被替代

`forwardTreeAws` 已导出但从未被调用。`app.ts:526-529` 把 `tree-aws/*` 模型路由到了 `forwardAnthropicNative`（因为 TreeGPT AWS 走 Anthropic 原生格式）。`forwardTreeAws` 是 OpenAI 格式转发，不再适用。

**建议**：删除函数和 `app.ts:10` 的 import。

### 13. store.ts:74-87 — `addRing` / `getRings` 无调用方

`memory_rings` 表的读写函数，项目内无任何调用。功能设计可能还没落地。

**建议**：标注 TODO 或删除。可不改。

### 14. store.ts:185+ — `generateImageDescription` 是空壳 TODO

函数体只有 TODO 注释，从未被调用。

**建议**：删除。可不改。

### 15. store.ts:117 vs builder.ts:54 — `getPersonaState` 两份实现

`store.ts` 和 `builder.ts` 各有一个 `getPersonaState`，都查同一张 `persona_state` 表。`builder.ts` 的版本被实际使用（line 97），`store.ts` 的版本导出但无外部调用方。

**建议**：删除 `store.ts` 里的那份，或让 `builder.ts` 导入 `store.ts` 的。

### 16. rhythm.ts:11 — `expireCount` 声明后从未使用

变量声明了，没有任何读取或更新的代码。

**建议**：删除。

### 17. embedder.ts:26 — `embedBatch` 导出后无调用方

只在 `embedder.ts` 内定义和导出，项目内没有 import。单条 `embed` 函数倒是在用。

**建议**：可不改（留着备用无害）。

### 18. rhythm.ts:51 — `getTTL` 导出后无外部调用方

函数定义了，但 grep 全项目只在 `rhythm.ts` 内部使用。没有外部 import。

**建议**：改为非导出，或留着备用。可不改。

### 19. app.ts:923-934 — 底部 startup log + `export default` 是残留

`app.ts` 底部有一段启动日志和 `export default app`，但实际入口是 `index.ts` 导入 `admin.ts`（admin.ts 再导入 app.ts）。这段 console.log 在模块被 import 时执行一次，与 `index.ts` 里的启动日志重复。`export default` 不被任何地方使用。

**建议**：删除 923-934 行的日志，保留 export（或也删掉）。可不改（无功能影响）。

### 20. prompt/builder.ts:2 — `emotionDb` 是 `supabase` 的冗余别名

```ts
import { supabase as emotionDb } from '../db/supabase';
import { supabase } from '../db/supabase';
```

同一个对象 import 了两次，用了两个名字。

**建议**：统一用一个。可不改。

---

## 关于 memory/ 目录「大半没在跑」的结论

**结论：15 个模块全部已接入，没有死模块。** 但它们受 `config.brainEnabled` 开关控制——如果 `.env` 里 `BRAIN_ENABLED` 不是 `true`，以下功能静默跳过：

- 定时器：decay（6h）、dream（4am）、desire（动态）、murmur（4am/2pm）、keepalive（50min）均不启动
- 聊天管线：记忆增强、情绪提取、自动记忆提取均跳过

这不是死代码，是功能开关。只要 Supabase 配好且 `BRAIN_ENABLED=true`，所有模块都在跑。

模块内部的死代码已在上面逐条列出（`addRing`/`getRings`、`generateImageDescription`、`getPersonaState` 重复、`expireCount`、`embedBatch`、`getTTL`）。

---

## 关于「两张表没建」

`calendar_markers` 和 `persona_state` 两张表在代码中被引用（desire.ts:93、store.ts:99/119、dreamer.ts:244、builder.ts:56）。如果这两张表在 Supabase 中不存在，相关查询会静默返回空数据（Supabase 客户端不会抛异常，只返回 error 对象，而代码中大部分地方只 `console.error` 了 error 然后返回空数组/null）。

**建议**：确认这两张表是否已在 Supabase 中创建。如果没有，相关功能（日历标记注入、persona 状态注入、梦境 persona 写入）处于「有代码但查不到数据」的状态。

---

## 整体干净的文件（可不改）

以下文件审查通过，没有发现值得单独列出的问题：

- `anniversary.ts` — 纪念日，纯本地 JSON，逻辑清晰
- `period.ts` — 经期追踪，算法合理
- `board.ts` — 留言板，简洁
- `meds.ts` — 药箱管理，含低库存告警，完整
- `peek.ts` — 窥屏，轮询等截图有 45s 超时保护
- `screentime.ts` — 屏幕时间聚合，轻量
- `fableline.ts` — Fable 通讯线，简洁
- `intimacy.ts` — 亲密卡 + 心愿单，完整
- `liveline.ts` — 生活直播线，有节流
- `mailer.ts` — SMTP 发信，配置检查到位
- `imap-reader.ts` — IMAP 收信，连接自动关闭
- `music.ts` — 音源代理，cookie 服务端保管
- `notebook.ts` — 笔记本，有路径越狱防护
- `nowplaying.ts` — 正在播放，歌曲记忆设计用心
- `phone-status.ts` — 手机状态，充电推送有冷却
- `todos.ts` — 待办，简洁
- `tweets.ts` — 推文桥，只读 SQLite
- `doorbell.ts` — 门铃通知，有冷却
- `config.ts` — 配置集中，干净
- `db/supabase.ts` — 一行客户端创建
- `middleware/auth.ts` — timing-safe 比较，正确
- `tools/builtin.ts` — 84 工具调度链，架构清晰
- `tools/loop.ts` — 流式工具循环，有 SSE keepalive
- `tools/mcp-client.ts` — MCP 客户端，5 分钟缓存
- `tools/websearch.ts` — Playwright 搜索，有并发限制
- `tools/gmail.ts` — OAuth + SMTP/IMAP 降级链
- `tools/twitter.ts` — CLI 桥接
- `providers/anthropic-native.ts` — 三层缓存断点，结构清晰
- `providers/deepseek.ts` — 简单转发
- `providers/openrouter.ts` — 简单转发
- `pocket.ts` — WebSocket 手机中继
- `howisshe.ts` — 健康聚合，Promise.all 并行
- `health.ts` — HealthKit 桥，180 天保留

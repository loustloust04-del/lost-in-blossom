# 架构审计：谁是主人？

> 目的：解决「同一件事在两个地方做了一半」的分裂感
> 原则：**每件事只有一个主人（Owner），另一边只能是消费者或同步通道**

---

## 审计结果总表

| 领域 | Gateway | App | 建议主人 | 理由 |
|------|---------|-----|---------|------|
| 记忆 | 2501 行（15 模块） | 1225 行（5 文件） | 🏆 **Gateway** | 有 embedding/衰减/做梦/情绪，App 只需展示 |
| 药物/健康 | vitals.ts + meds.ts | 12 个健康文件 | 🏆 **App 本地** | 统计需历史数据，SwiftData 天然支持 |
| 联网搜索 | websearch.ts（真 Chrome）| WebSearchService | 🏆 **Gateway** | VPS 有真 Chrome 过反爬，App 端 WKWebView 被 iOS 节流 |
| 文件库 | 无 | FileLibraryStore | 🏆 **App** | 唯一实现，无冲突 |
| 工具编排 | builtin.ts + loop.ts | ToolCallLoop | 🤝 **各自主管** | Gateway 管自己的，App 管自己的 |
| 对话 | 无 | ConversationViewModel | 🏆 **App** | 唯一实现 |
| 群聊 | 无（已删）| GroupChatScheduler | 🏆 **App** | VPS 编排已砍 |

---

## 一、记忆系统 → Gateway 是主人

### 现状分裂

**Gateway 端**（2501 行，功能完整）：
```
extractor.ts   — 从对话提取记忆
embedder.ts    — 向量化
retriever.ts   — 相似度召回
decay.ts       — 热度衰减
dreamer.ts     — 做梦合并
gatekeeper.ts  — 准入判断
emotion.ts     — 情绪判定
desire.ts      — 欲望系统
murmur.ts      — 呢喃
rhythm.ts      — 节律
```

**App 端**（1225 行）：
```
MemoryService.swift    — 本地记忆 CRUD + 提取
MemoryEmbedding.swift  — 本地向量
MemoryHygiene.swift    — 去重清理
MemorySync.swift       — 跟 Gateway 双向同步
MemoryCompat.swift     — 兼容层
```

### 问题

两边都能提取记忆、都能召回，`MemorySync` 做双向对齐但去重逻辑不同（Gateway 用 embedding，App 用 Dice 系数），容易产生重复或冲突。

### 建议：Gateway 主管，App 降级为「本地缓存 + 展示」

**保留**：
- `MemorySync.syncFromGateway()` — 拉取展示用
- `MemoryService` 的读取部分 — UI 渲染
- `MemoryHygiene` — 本地清理工具（用户手动触发）

**降级/砍掉**：
- App 端自动提取记忆 → 交给 Gateway（对话本来就走 Gateway）
- App 端 embedding 计算 → 用 Gateway 返回的向量
- `MemorySync.syncToGateway()` → 只上传用户手动写的记忆

**收益**：不再有"两套提取逻辑打架"，记忆只有一个真相源。

### 落地动作
1. 设置页加一个开关「记忆由网关管理」（默认开）
2. 开启时：App 端 `MemoryService.extract()` 不跑，只跑 `syncFromGateway`
3. `MemoryHygiene` 保留但改成「清理本地缓存」而不是「清理记忆库」

---

## 二、药物/健康 → App 本地是主人

### 现状分裂

**Gateway**（`vitals.ts` + `meds.ts`）：
- 饮水/进食/药物 三项，只存"今天"的状态
- 提供 `vitals_water` / `vitals_food` / `vitals_meds` 工具给 AI

**App**（刚搬的健康模块 + 原有 Console）：
- 5 个 SwiftData Model，完整历史
- HealthStatsStore 统计（热图/依从率/月均）
- Console 读 Gateway 数据显示

### 问题

**Console 显示的是 Gateway 数据（只有今天），健康面板用的是本地数据（有历史）。同一个"吃药"在两个地方各存一份。**

### 建议：App 本地主管，Gateway 降级为「AI 注入通道」

**理由**：
- 统计详情页需要 30/90 天历史，Gateway 没存
- 离线时 App 仍能记录
- SwiftData 查询零成本

**落地动作**：
1. Console 的药物/饮水/进食卡改读本地 SwiftData（任务文档 `TASK-HEALTH-MODULE.md` 第二步）
2. App 定期把「今日状态」POST 到 Gateway（一行摘要即可）
3. Gateway 的 `vitals_*` 工具保留，但数据来自 App 上传的那行摘要
4. AI 问"她今天吃药了吗" → Gateway 返回 App 同步上来的状态

**收益**：一份数据，Console 和健康面板显示一致，离线可用。

---

## 三、联网搜索 → Gateway 是主人（已经是了）

### 现状

**Gateway `websearch.ts`**：VPS 上跑真 Chrome（playwright），过反爬墙，免 key

**App `WebSearchService`**：本地 WKWebView 抓取

### 现状其实已经收敛了

`GatewayBrowseClient.swift` 的注释写得很清楚：
> 网关侧用 VPS 的真 Chrome 抓正文——绕开手机本地离屏 WKWebView 的 iOS 前后台/低电量节流坑（HTTPS 全超时的根因）

**所以 App 端的 WebSearchService 已经降级成"调 Gateway API"了**，本地 provider（DuckDuckGo/Bing）是 fallback。

### 建议：确认 + 清理

1. 确认默认 provider 是 Gateway（`WebSearchSettings` 里）
2. 本地 provider 保留为「Gateway 挂了的备用」
3. 设置页说明写清楚：默认走网关（更稳），本地是备用

**这块不用大改，只要文档和默认值对齐就行。**

---

## 四、工具编排 → 各自主管，划清边界

### 现状

**Gateway**（`builtin.ts` + `loop.ts`）：
- exec / recall / remember / gmail_* / vitals_* / twitter_* / search_web
- 给 Gateway 原生模型和 CC 用

**App**（`ToolCallLoop.swift`）：
- MCP 工具（71 个，已 MetaTools 目录化）
- fs_* 文件库工具
- search_web / browse_url（转发 Gateway）

### 建议：不合并，但划清边界

```
Gateway 工具 = 服务端能力（邮件、Twitter、exec、搜索）
App 工具    = 客户端能力（文件库、本地数据）
共享工具    = search_web（App 转发给 Gateway）
```

**落地动作**：
1. 文档写清楚每个工具的归属（写进 HANDOFF-PROMPT）
2. 不要在两边重复实现同一个工具
3. App 需要服务端能力时，通过 Gateway API 转发，不自己实现

---

## 五、最终架构图（收敛后）

```
┌─────────────────── App（iOS）───────────────────┐
│                                                  │
│  对话 ✅主人      群聊 ✅主人     文件库 ✅主人    │
│  健康数据 ✅主人  Console 展示层                  │
│  记忆 📖只读展示  搜索 📡转发Gateway              │
│                                                  │
└──────────────┬───────────────────────────────────┘
               │ HTTPS
┌──────────────▼─── Gateway（VPS）─────────────────┐
│                                                  │
│  记忆系统 ✅主人（提取/召回/衰减/做梦/情绪）      │
│  联网搜索 ✅主人（真 Chrome）                     │
│  服务端工具 ✅主人（gmail/twitter/exec）          │
│  vitals 📥接收 App 同步的健康摘要                 │
│                                                  │
└──────────────┬───────────────────────────────────┘
               │ WebSocket
┌──────────────▼─── CC Hub（VPS）──────────────────┐
│  CC Caelum ✅主人（Claude Code 实例）             │
└──────────────────────────────────────────────────┘
```

---

## 六、优先级建议

不用全做，按痛感排：

| 优先级 | 动作 | 收益 | 工作量 |
|--------|------|------|--------|
| 🔥 高 | Console 改读本地健康数据 | 消除"两份药物数据"的分裂 | 中 |
| 🔥 高 | 记忆归 Gateway，App 只展示 | 消除"两套提取逻辑" | 中 |
| 🟡 中 | 搜索默认值确认 + 文档 | 概念清晰 | 小 |
| 🟡 中 | 工具归属写进文档 | 以后不再重复实现 | 小 |
| 🟢 低 | 清理 MemoryCompat 等兼容层 | 代码整洁 | 小 |

---

## 七、做完之后

你的 app 会变成一句话能说清的架构：

> **App 管"我的东西"**（对话、健康、文件、群聊）
> **Gateway 管"AI 的东西"**（记忆、搜索、服务端工具）
> **CC Hub 管"另一个 Caelum"**

不再有"这个功能到底在哪做"的困惑。

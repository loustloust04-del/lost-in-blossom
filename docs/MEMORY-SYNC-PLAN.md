# 记忆系统前后端联动方案 · MEMORY-SYNC-PLAN

> 作者：Claude（记忆联动规划任务）
> 日期：2026-06-13
> 目标：让 App 端的记忆面板（`MemoryPanelView`）从"纯本地 SwiftData"接入后端，
> 实现本地 ↔ 云端双向同步、冲突解决、离线可用。

---

## 1. 现状盘点：两套互不相通的记忆系统

### 1.1 App 端（本地，SwiftData）

- 模型：`MemoryPalace/Models/Memory.swift`，`@Model class Memory`
- 存储：`MemoryService.swift` 的 `SwiftDataMemoryStore`
- 展示：`MemoryPanelView.swift`（活跃/休眠/将忘三档分组）
- 提取：`ConversationViewModel.swift:1480` 调用 `MemoryExtractor.buildRequest`，
  用当前聊天模型自行提取，`executeActions` 写入本地库
- 注入：`PromptAssembler.swift:262` 用 `MemoryInjector.buildInjection` 拼进 system prompt
- 衰减：本地 `DecayEngine`，`applyDecay` 惰性计算 `decayWeight × exp(-0.1·days)`

**字段**：`id(UUID)`、`content`、`category`(preference/fact/relationship/goal/context)、
`keywords[]`、`tokenCount`、`accessCount`、`lastAccessedAt`、`decayWeight(0–1)`、
`validUntil?`、`isUserExplicit`、`profileId`（楼层隔离）、`createdAt`、`updatedAt`、
`sourceConversationId`、`extractedBy`。

### 1.2 Gateway 端（云端，Supabase）

- 表：`memories`（+ `memory_rings`、`persona_state`、`calendar_markers`、`dream_log`）
- 提取：`extractor.ts` 对话后异步调 `deepseek-chat`，写 Supabase
- 检索：`retriever.ts` 两层（主记忆向量+关键词+锚点 / 侧翼时间+情感扩散）
- 注入：`prompt/builder.ts` 四层 RAG + `gatekeeper.ts` 概率浮现
- 衰减：`decay.ts`，`heat × exp(-0.1·days)`，每 6h 全表跑

**字段**：`id`、`content`、`tier(1–4)`、`category`、`heat(0–1)`、`valence(-1..1)`、
`arousal(0..1)`、`is_anchor`、`is_pinned`、`resolved`、`source`(auto/dream/...)、
`embedding(vector)`、`created_at`、`updated_at`。**没有 user_id / profile_id。**

### 1.3 核心矛盾

| 维度 | App 本地 | Gateway 云端 |
|------|---------|-------------|
| 主键 | `UUID`（客户端生成） | `uuid`（Supabase 默认生成） |
| 权重 | `decayWeight` 0–1 | `heat` 0–1（语义相近，可映射） |
| 重要度 | 无（只有 isUserExplicit 布尔） | `tier` 1–4 |
| 情感 | 无 | `valence` / `arousal` |
| 隔离 | `profileId`（多楼层） | 无（全局单租户） |
| 用户手动 | `isUserExplicit` | `is_pinned` / `source='manual'`（语义近） |
| 向量 | `embeddingData`（预留未用） | `embedding`（已用） |

两套**永不同步**：用户在 App 面板手动加的记忆，AI 经云端对话时看不到；云端 dream
固化出的记忆、提取的记忆，App 面板也看不到。同一句话可能两边各提取一次（重复），
也可能（若主聊天没走 gateway）只有 App 提取、云端为空。

---

## 2. 设计原则

1. **云端为权威源（source of truth），本地为缓存 + 离线副本**。
   理由：AI 的"记得"发生在 gateway 注入时；只有云端记忆能影响对话。本地若是权威，
   AI 永远读不到。
2. **统一 schema，本地是云端的子集映射**，不强行让两套字段一一对应，
   只同步双方都有意义的字段，云端独有字段（valence/arousal/embedding）本地只读展示。
3. **先解决隔离（A1）再谈同步**：云端必须先有 `owner_id`，否则多楼层同步会串台。
4. **同步必须离线可用**：iOS 网络不稳，所有写操作先落本地、再后台 push。

---

## 3. 后端改造（前置条件）

### 3.1 给云端表加用户/楼层维度

```sql
ALTER TABLE memories ADD COLUMN owner_id text NOT NULL DEFAULT 'bunny';
ALTER TABLE memories ADD COLUMN client_id uuid;          -- App 端 Memory.id，去重用
ALTER TABLE memories ADD COLUMN updated_at timestamptz DEFAULT now();
ALTER TABLE memories ADD COLUMN deleted_at timestamptz;  -- 软删除（墓碑），同步删除用
CREATE UNIQUE INDEX ON memories(owner_id, client_id) WHERE client_id IS NOT NULL;
```

`owner_id` 对应 App 的 `profileId`（楼层）。所有 retriever/extractor/dream 查询带
`.eq('owner_id', ownerId)`。

### 3.2 新增同步 API（gateway，带 Bearer 鉴权）

```
GET  /v1/memories/sync?owner_id=<floor>&since=<ISO8601>
     → { memories: [...], server_time: <ISO>, deleted: [<id>...] }
     返回 since 之后 updated_at 变化的记忆 + 该窗口内被软删的 id 列表

POST /v1/memories/sync
     body: { owner_id, changes: [{ op: "upsert"|"delete", memory: {...}, base_version }] }
     → { results: [{ client_id, server_id, status: "ok"|"conflict", winner: {...} }],
         server_time }
```

- 增量同步用 `updated_at` 高水位线（`since`）。
- `base_version`：客户端上次见到的 `updated_at`，用于冲突检测（乐观并发）。
- 软删除返回墓碑，保证一端删除能传播到另一端。

字段映射（App → 云端）：

| App | 云端 | 说明 |
|-----|------|------|
| `id` | `client_id` | 客户端主键，去重锚 |
| `content` | `content` | 直接 |
| `category` | `category` | 直接 |
| `decayWeight` | `heat` | 直接（同为 0–1 衰减语义） |
| `isUserExplicit` | `is_pinned` + `source='manual'` | 手动记忆置顶不衰减 |
| `profileId` | `owner_id` | 楼层 = 所有者 |
| `keywords` | （云端不存或存 jsonb） | 可选 |
| `updatedAt` | `updated_at` | 冲突基准 |
| — | `tier`/`valence`/`arousal`/`embedding` | 云端独有，App 只读 |

App 同步下来云端独有字段时，存进 `Memory` 的预留列（`embeddingData` 等）或新增只读属性，
仅供面板展示"这条记忆云端判定为核心/情绪强烈"。

---

## 4. 同步流程

### 4.1 本地 → 云端（push）

触发时机：
- 用户在 `MemoryPanelView` 手动增/改/删记忆 → 立即标脏，后台 push。
- App 本地 `MemoryExtractor` 提取出新记忆 → **改为不再本地提取**（见 4.4），
  避免与云端提取重复。过渡期若仍本地提取，提取后 push 并打 `source='app-extract'`。

实现：给 `Memory` 加 `syncState` 字段（`synced`/`dirty`/`pendingDelete`）和
`serverUpdatedAt`。写操作只改本地 + 置 `dirty`。后台 `MemorySyncService`（新增）
周期/触发地把所有 `dirty` 打包 `POST /v1/memories/sync`，成功后置 `synced` 并记录
`server_id`/`serverUpdatedAt`。

### 4.2 云端 → 本地（pull）

触发时机：App 启动、进入记忆面板、收到推送提示"记忆有更新"、或定时（如每 5 分钟前台）。

实现：`MemorySyncService` 存一个 per-floor 的 `lastSyncedAt` 高水位线，
`GET /v1/memories/sync?owner_id=&since=lastSyncedAt`，把返回的记忆 upsert 进 SwiftData
（按 `client_id`/`server_id` 匹配），处理 `deleted` 墓碑删本地，更新 `lastSyncedAt = server_time`。

### 4.3 冲突解决

模型：**乐观并发 + 字段级合并 + LWW 兜底**。

1. **删除优先**：任一端删除（墓碑） vs 另一端编辑 → 删除胜（避免"复活"已删记忆）。
   除非编辑端是 `isUserExplicit` 手动改且时间更晚 → 提示用户二选一（少见，可后做）。
2. **手动 > 自动**：`isUserExplicit/is_pinned` 的一方覆盖自动提取的一方
   （用户明确意图优先于 LLM 猜测）。
3. **内容冲突走 LWW**：两端都改了 `content` 且都不是手动 → 比 `updated_at`，新的胜，
   旧的进 `memory_rings`（云端已有"年轮/水彩叠层"表）留痕，不硬删。
4. **权重字段（heat/decayWeight）不参与冲突**：各自独立演化，pull 时云端 heat 覆盖本地
   decayWeight（因为 AI 注入依据的是云端 heat，本地只是展示）。这样避免衰减值来回打架。

服务端在 `POST /sync` 里用 `base_version != 当前 updated_at` 判冲突，按上述规则裁决，
返回 `winner` 让客户端对齐。

### 4.4 提取去重（消除双重系统）

**目标终态**：记忆提取只在云端发生一处。

- App 本地 `MemoryExtractor` 自动提取**关闭**（`ConversationViewModel` 的提取调用改为可开关，
  默认走云端）。当主聊天经 gateway 时，`extractor.ts` 已在对话后提取，App 只需 pull。
- 用户手动加的记忆仍在 App 创建（push 上去），打 `source='manual'`，云端提取时把它当
  "已有记忆"去重上下文，不重复 add。
- 过渡期（主聊天可能不走 gateway）：保留本地提取但 push，云端用 `client_id` 幂等去重。

---

## 5. 离线处理

1. **写操作永远先落本地 SwiftData**，UI 立即反映（乐观更新），`syncState=dirty`。
2. 网络不可用：push 失败静默重试（指数退避），脏记录留在队列，不丢。
3. App 重启：启动时扫 `dirty`/`pendingDelete` 重新入队。
4. 长期离线后重连：先 pull（拿云端增量）→ 跑冲突解决 → 再 push 本地脏数据，
   顺序保证不会用旧本地覆盖新云端。
5. **去重幂等键**：`(owner_id, client_id)` 唯一索引保证重复 push（网络重试导致）不产生分身。
6. 面板加一个轻量同步状态指示（已同步 / 同步中 / 离线待同步 N 条），失败可手动重试。

---

## 6. 分阶段落地

| 阶段 | 内容 | 依赖 |
|------|------|------|
| P0 | 后端先修 A1（加 `owner_id`/`client_id`/`updated_at`/`deleted_at` 列 + RLS） | 无 |
| P1 | gateway 加 `GET/POST /v1/memories/sync`（带鉴权） | P0 |
| P2 | App 加 `MemorySyncService` + `Memory.syncState`/`serverUpdatedAt`，实现 pull | P1 |
| P3 | 实现 push + 冲突解决（删除优先 / 手动优先 / LWW + 年轮留痕） | P2 |
| P4 | 关闭 App 本地自动提取，统一到云端；面板展示云端独有字段（tier/情感） | P3 |
| P5 | 同步状态 UI + 离线队列重试 + 手动重试入口 | P3 |

P0/P1 是纯后端，可独立先做且不影响现有 App。P2 起 App 才动。

---

## 7. 风险与注意

- **不要让 heat/decayWeight 双向覆盖**：两套衰减引擎都在跑，权重字段必须单向
  （云端→本地只读），否则会出现"刚强化又被旧值打回"的抖动。
- **profileId ↔ owner_id 映射要稳定**：楼层 id 是 App 端字符串（如 `lost-blossom`），
  作为 `owner_id`，不要用会变的显示名。
- **先隔离再同步**：在 `owner_id` 落地前不要开 push，否则把多楼层记忆灌进无隔离的云端，
  数据污染后很难拆。
- **embedding 归属**：App 同步上去的手动记忆，云端要补算 embedding（复用
  `backfill-embeddings.ts`），否则它进不了向量检索，只能关键词命中。

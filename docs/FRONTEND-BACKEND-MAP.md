# 前后端联动总体图 · FRONTEND-BACKEND-MAP

> 作者：Claude（前后端联动规划任务）
> 日期：2026-06-13
> 一张完整数据流图：App ↔ CC Bridge ↔ VPS ↔ Supabase / 外部 API，
> 每条通路标注现在是 **通 ✅ / 断 ⚠️ / 半通 🟡**。

---

## 1. 部署拓扑（VPS 172.245.88.103）

```
                          公网 172.245.88.103
                                  │
                ┌─────────────────┼──────────────────────────┐
                │ nginx (ip-mcp)  │                          │ ufw 放行端口
                │                 │                          │ 80,443,6080,7681,
   :443 ssl ────┤  /v1/  /health  → 127.0.0.1:4567 (gateway) │ 8888,8890,8891,48722
                │  /cc  /mcp      → 127.0.0.1:7890 (hub)      │
                │  /chatroom/     → 127.0.0.1:3300 (chatroom) │
                │  /              → 127.0.0.1:3456 (其他)     │
   :8890 ───────┤  /cc/           → 127.0.0.1:7890/ (hub,明文)│
                └─────────────────┬──────────────────────────┘
                                  │
   systemd 常驻服务：
     lib-gateway     :4567  (bun, /root/projects/BunnyPalace/gateway)
     cc-bridge hub   :7890  (bun, 127.0.0.1)        ← /ws=App  /mcp=MCP
     chatroom        :3300  (bun, *:全网卡 ⚠️)
     imprint-memory  :8100 / SSE  (独立记忆 MCP, imprint.amberrib.com)
     memory-palace   (Bunny & Caelum 服务)
```

域名：`blossom.amberrib.com` → gateway；`imprint.amberrib.com` → imprint-memory SSE。

---

## 2. 完整数据流图

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         iOS App (MemoryPalace)                             │
│                                                                            │
│  ChatService ──────────┐   ChatroomService ──┐   CC Bridge WS client ──┐   │
│  MemoryService(本地)   │   PushAgentService  │   (ContentView 启动连)  │   │
└────────┬───────────────┼─────────────────────┼─────────────────────────┼───┘
         │               │                     │                         │
   (A)   │ 直连供应商    │ (B) gateway          │ (C) chatroom            │ (D) CC Bridge
         ▼               ▼                     ▼                         ▼
   OpenAI/DeepSeek   blossom.amberrib.com   /chatroom/* (无鉴权⚠️)   ws .../cc → hub :7890
   /OpenRouter/...   /v1/* :4567                :3300                  /ws (tmux send-keys)
   (App 自带 key)        │                       │                         │
         ✅              │ Bearer auth ✅         │                         │ /mcp ← MCP server
                        ▼                       ▼                         ▼
              ┌──────────────────┐      OpenRouter/DeepSeek      tmux: claude --continue
              │ Gateway 记忆增强  │      (烧 VPS 的 key)          --dangerously-skip-perms
              │ enhanceMessages  │            │                         │
              │ → 转发上游        │            │                  reply 工具 → hub → APNs
              │ → 存消息/提取记忆 │            │                         │
              └────────┬─────────┘            │                         ▼
                       │ extractor/dreamer    │                   APNs (sandbox)
                       │ retriever/gatekeeper │                   sendPush → iPhone
                       ▼                      ▼
              ┌────────────────────────────────────┐
              │  Supabase (ezeldljtafhvpswgfxjx)    │
              │  messages / memories / dream_log /  │
              │  persona_state / calendar_markers   │
              │  ⚠️ 无 user_id / profile_id 隔离     │
              └────────────────────────────────────┘

         旁路：imprint-memory MCP (imprint.amberrib.com/sse) ← CC 通过 .mcp.json 使用
              （与 gateway 的 Supabase 记忆是另一套独立记忆系统）
```

---

## 3. 逐条通路状态

### (A) App → 外部 AI 供应商（主聊天，直连） ✅ 通
- 路径：`ChatService` → provider `baseURL`（OpenRouter/DeepSeek/Kimi/Ollama...），用 App 自带 key。
- 状态：**通**。这是默认主聊天路径。
- 含义：**走这条时不经过 gateway，云端记忆系统完全不参与**——AI 不会"记得"，
  也不会触发提取/dream/desire。

### (B) App → Gateway `/v1/chat/completions`（记忆增强聊天） 🟡 半通
- 路径：用户把某个 provider 配成 `blossom.amberrib.com/v1` + token `<redacted — rotate & store in .env only>`。
- gateway 端 `enhanceMessages` 注入记忆、转发上游、存消息、异步提取。
- 状态：**代码通，但是否启用取决于 App 配置**。`ChatroomService` 默认用了
  `blossom.amberrib.com` 取模型列表，但**主聊天是否路由到 gateway 需用户手动配 provider**。
  若没配，整个云端记忆系统（extractor/retriever/gatekeeper/dream）空转。
- 建议：把 gateway 设为推荐/默认主聊天通道，否则后端一半的功能不生效。

### (C) App → Chatroom `/chatroom/*`（AI 互聊） 🟡 半通 + ⚠️ 安全
- 路径：`ChatroomService`（`blossom.amberrib.com` fallback）→ nginx → `:3300`。
- 功能：两个 AI 互相对话（SSE 流），SQLite 本地库。
- 状态：**功能通**，但 **零鉴权 + IDOR + 监听全网卡**（见 BACKEND-AUDIT S2）。任何人可烧 API 额度。

### (D) App ↔ CC Bridge（ws .../cc → hub） ✅ 通 + ⚠️ 安全
- 路径：App WS → `ws://172.245.88.103:8890/cc/...`（或内置 `ws://127.0.0.1:7890/cc`）
  → nginx → hub `:7890` `/ws`。
- 上行：`chat` → `tmux send-keys` 注入 CC 会话（`<channel source="memorypalace">` 标签）。
- 下行：CC 用 MCP `reply` 工具 → hub `/mcp` → 广播给 App + 离线落盘 + APNs 推送。
- 文件：双向（入站图片/文件落 `inbound/`，出站 `stageOutboundFile`）。
- 状态：**通**，App ↔ CC 实时双向工作。但 **鉴权可被 nginx 反代绕过**（BACKEND-AUDIT S1，
  `isLoopback` 对所有反代流量返回 true），`spawn_cc` 暴露 = RCE 面。

### (E) Gateway ↔ Supabase ✅ 通（单点 + 无隔离）
- 路径：`db/supabase.ts` 用 `SUPABASE_KEY` 直连。
- 状态：**通**。但单租户、无 RLS 边界、挂掉时记忆静默丢失（A1/A4/S5）。

### (F) Gateway 定时器 → Supabase ✅ 通（脆弱）
- decay(6h) / dream(每小时查 4 点) / desire(2h)，仅 `config.supabaseUrl` 非空时启动。
- 状态：**通但脆弱**——单进程内存状态，重启即漏跑，无幂等（A2）。

### (G) Desire（"想你了"念头） ⚠️ 断（写了没人读）
- `desire.ts` 把念头写进 `messages`（`session_id='desire'`），`/v1/desires` 端点可读。
- 状态：**后端在写，但 App 端从不调用 `/v1/desires`**（grep `desires` 在 App 代码零命中）。
- 含义：欲望系统单向空转——念头生成了，用户永远看不到。需 App 加轮询/展示，
  或接入推送把念头推给用户。

### (H) CC ↔ imprint-memory MCP（独立记忆系统） ✅ 通（又一套并行记忆）
- `.mcp.json` 里 CC 挂了 `imprint-memory` SSE（`imprint.amberrib.com/sse`）。
- 这是**第三套**记忆系统（除 App 本地、gateway/Supabase 之外），CC 自己用。
- 状态：**通**，但与前两套记忆完全独立，三套记忆互不知晓。

### (I) App 本地记忆 ↔ Gateway/Supabase 记忆 ⚠️ 断
- App `MemoryService`（SwiftData）与 gateway 的 Supabase `memories` **schema 不同、永不同步**。
- 状态：**完全断开**。这是 `MEMORY-SYNC-PLAN.md` 要解决的核心。

### (J) APNs 推送 ✅ 通（sandbox）
- hub `apns.ts` → `api.sandbox.push.apple.com`，token-based（.p8）。
- 状态：**通**。注意是 **sandbox** host（`MP_APNS_HOST` 默认 sandbox），
  生产发布需切 `api.push.apple.com`，否则正式版收不到推送。

---

## 4. 断点汇总（需要打通的）

| 通路 | 现状 | 要做什么 |
|------|------|---------|
| (I) App本地 ↔ 云端记忆 | ⚠️ 断 | 实现同步 API + MemorySyncService（见 MEMORY-SYNC-PLAN） |
| (G) Desire 念头 → App | ⚠️ 断 | App 调 `/v1/desires` 或推送念头；否则欲望系统无出口 |
| (B) 主聊天 → Gateway | 🟡 取决于配置 | 把 gateway 设为默认聊天通道，否则云端记忆不触发 |
| (H)(I) 三套记忆并存 | 🟡 各自为政 | 中长期收敛：App本地/Supabase/imprint 至少前两者统一 |

## 5. 安全热点汇总（详见 BACKEND-AUDIT）

| 通路 | 风险 | 等级 |
|------|------|------|
| (D) CC Bridge | 反代绕过鉴权 → spawn_cc RCE | 🔴 P0 |
| (C) Chatroom | 零鉴权 + IDOR + 全网卡监听 | 🔴 P0 |
| (B)(D) Token | `<redacted — rotate & store in .env only>` 弱口令 + 文档明文 | 🔴 P0 |
| (D) 文件落盘 | chatId 路径穿越 | 🟠 P1 |
| (E) Supabase | 无 RLS / 无 user 隔离 | 🟠 P1 |

---

## 6. 一句话总结

后端三大子系统（gateway 记忆 / CC Bridge / chatroom）**各自能跑**，但：
1. **主聊天默认不经 gateway**，导致云端记忆系统可能整段空转（B）。
2. **三套记忆系统并存且互不相通**（App本地 / Supabase / imprint），是最大的架构债（I/H）。
3. **欲望系统有入无出**（G），念头生成了没人读。
4. **两个 P0 鉴权洞**（C/D）让"能跑"的通路同时也"谁都能打"。

打通顺序建议：先堵 P0 安全洞 → 把主聊天默认接 gateway → 做记忆同步（I）→ 接通 desire（G）。

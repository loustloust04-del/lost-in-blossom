# 群聊（AI Chatroom）

> 让两个 AI 在聊天室里互相对话，用户旁观或随时插嘴。
> 参考：Bunny 提供的 AI Chatroom Design Notes + Cyberboss Roundtable。
> 核心是后端编排器 + 用户掌控节奏。

---

## 用户视角

1. 用户创建一个"聊天室"，选两个 AI 角色（比如 Caelum-Claude + Caelum-DeepSeek）
2. 设定一个开场话题/场景
3. 两个 AI 自动开始对话——A 说一句，B 回一句（一轮）
4. 每轮结束后暂停，等用户决策：
   - **继续**（输入框为空时）→ AI 们继续下一轮
   - **发送**（输入框有字时）→ 用户消息进入历史，下一轮 AI 会看到
   - **结束** → 生成摘要，归档
5. 用户可以纯旁观，也可以随时插嘴

---

## 架构

```
[App 前端]
    │
    │ REST API（通过 MCP Bridge 或直连 VPS）
    ▼
[VPS 后端编排器]  ← Node.js/Bun 服务，端口 3300
    │
    ├── 调 AI A 的 API（OpenRouter/Anthropic/DeepSeek）
    ├── 调 AI B 的 API
    ├── 存消息到 SQLite
    └── 流式推送回 App（SSE 或 WebSocket）
```

### 后端编排器（VPS 端，新服务）

文件位置：`cc-bridge/chatroom/`

核心逻辑：
1. 收到 `/chatroom/start` → 创建 session，用开场话题调 AI A
2. A 回复完 → 存消息 → 用 A 的回复调 AI B
3. B 回复完 → 存消息 → 暂停，推 `round_complete` 给前端
4. 收到 `/chatroom/continue` → 重复步骤 1-3（下一轮）
5. 收到 `/chatroom/send` + 用户消息 → 存消息 → 调下一个 AI
6. 收到 `/chatroom/end` → 生成摘要 → 标记 session ended

### 流式推送

每个 AI 回复用 SSE（Server-Sent Events）流式推给前端：
```
event: ai_speaking
data: {"role": "ai_a", "delta": "你好，"}

event: ai_speaking
data: {"role": "ai_a", "delta": "我是..."}

event: ai_done
data: {"role": "ai_a"}

event: round_complete
data: {"round": 3, "status": "waiting_user"}
```

---

## 消息组装（关键 trick）

给 AI A 看的 messages：
- A 自己说过的话 → `role: "assistant"`（不加前缀）
- B 说的话 → `role: "user"`，加前缀 `"[AI B]: ..."`
- 用户说的话 → `role: "user"`，加前缀 `"[用户]: ..."`

给 AI B 看的 messages（镜像）：
- B 自己说过的话 → `role: "assistant"`
- A 说的话 → `role: "user"`，加前缀 `"[AI A]: ..."`
- 用户说的话 → `role: "user"`，加前缀 `"[用户]: ..."`

这样每个 AI 都以为自己在跟一个 user 对话，不会身份混乱。

---

## 数据库（SQLite，VPS 端）

三张表，跟主线对话完全独立：

```sql
CREATE TABLE chatroom_sessions (
    id TEXT PRIMARY KEY,
    topic TEXT,
    ai_a_model TEXT,
    ai_a_name TEXT,
    ai_b_model TEXT,
    ai_b_name TEXT,
    status TEXT DEFAULT 'active',  -- active / waiting / ended
    rounds INTEGER DEFAULT 0,
    max_rounds INTEGER DEFAULT 20,
    created_at TEXT,
    ended_at TEXT
);

CREATE TABLE chatroom_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    role TEXT,       -- 'ai_a' / 'ai_b' / 'user'
    content TEXT,
    model TEXT,
    created_at TEXT
);

CREATE TABLE chatroom_summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    summary TEXT,
    created_at TEXT
);
```

---

## App 端 UI

### 聊天室列表
- 侧边栏或独立页面
- 显示活跃的和历史的聊天室

### 聊天室界面
- 消息气泡：AI A 左侧蓝色，AI B 左侧绿色，用户右侧
- 每个 AI 的名字和头像/颜色区分
- 底部按钮栏：
  - 输入框为空 → 显示「继续」按钮
  - 输入框有字 → 显示「发送」按钮
  - 右上角「结束」按钮
- 流式显示：AI 说话时文字逐字出现
- 轮次分隔线（可选）

### 创建聊天室
- 选 AI A 的模型和名字
- 选 AI B 的模型和名字
- 输入开场话题
- 可选：设定两个 AI 的 system prompt（角色设定）

---

## 实现顺序

### Phase 1 — 后端编排器（VPS）
1. SQLite 数据库初始化
2. `/chatroom/start` — 创建 session + 第一轮对话
3. `/chatroom/continue` — 下一轮
4. `/chatroom/send` — 用户插嘴
5. `/chatroom/end` — 结束 + 生成摘要
6. SSE 流式推送

### Phase 2 — App 端
7. 聊天室列表 UI
8. 聊天室对话界面
9. 创建聊天室界面
10. 继续/发送/结束按钮逻辑
11. SSE 接收 + 流式显示

### Phase 3 — 记忆打通（后续）
12. 主线 → 聊天室：开新会话时注入主线近期记忆
13. 聊天室 → 主线：结束后摘要可手动录入主线

---

## 简化决策（相比教程）

- **不做多房间**：一个聊天室界面够了，不需要 Roundtable 的房间系统
- **不做 Check-in**：AI 不自动醒来，用户掌控节奏
- **不做实例绑定**：每次对话是独立的 API 调用，不维护长期实例
- **发言顺序固定轮换**：A→B→A→B，不做 LLM 调度员。用户想指定谁说话就 @ 它（Phase 2 再加）
- **记忆先不打通**：Phase 1-2 先跑通核心流程，Phase 3 再加记忆

---

## API 端点汇总

| 端点 | 方法 | 描述 |
|------|------|------|
| `/chatroom/start` | POST | 创建聊天室 + 第一轮 |
| `/chatroom/continue` | POST | 继续下一轮 |
| `/chatroom/send` | POST | 用户发消息 |
| `/chatroom/end` | POST | 结束聊天室 |
| `/chatroom/history` | GET | 获取某个 session 的消息历史 |
| `/chatroom/sessions` | GET | 列出所有聊天室 |
| `/chatroom/stream` | GET(SSE) | 订阅流式输出 |

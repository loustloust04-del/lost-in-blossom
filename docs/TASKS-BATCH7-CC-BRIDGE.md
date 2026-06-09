# 第七批任务 — CC Bridge Phase 1 重写（能连能回）

> 日期：2026-06-09
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 参考代码：粟粟原版 VPS `/root/projects/SusuPalace/cc-bridge/`
> 难度：高 — 请完整读完本文档 + 粟粟的参考代码再动手

---

## 背景

我们的 CC Bridge 是半成品（200多行），CC 流式输出走 capture-pane 轮询导致"什么都流出来了"。
粟粟的 CC Bridge（899行 hub + 134行 mcp-server）架构更成熟：

```
CC ←(stdio MCP)→ mcp-server.ts ←(WebSocket)→ hub.ts ←(WebSocket)→ App
```

三个节点两条管道。CC 通过 MCP reply 工具说话，Hub 转发给 App。
Phase 1 目标：**CC 能收到用户消息、能回复**。终端流/推送/文件互发后续 Phase 做。

---

## 重要：先读粟粟的代码

用 exec_vps 读这些文件，完整理解架构再动手：

```bash
# MCP Server（134行，最重要）
cat /root/projects/SusuPalace/cc-bridge/mcp-server.ts

# Hub（899行，Phase 1 只需要前 400 行的基础部分）
cat /root/projects/SusuPalace/cc-bridge/hub.ts

# 启动脚本
cat /root/projects/SusuPalace/cc-bridge/start_cc.sh
cat /root/projects/SusuPalace/cc-bridge/start_hub.sh

# package.json（看依赖）
cat /root/projects/SusuPalace/cc-bridge/package.json

# MCP 配置模板
cat /root/projects/SusuPalace/cc-bridge/mcp.template.json
```

---

## Task 1: 重写 mcp-server.ts

**参考**: 粟粟的 `/root/projects/SusuPalace/cc-bridge/mcp-server.ts`（134行）

**要做的事**:
1. 用 `@modelcontextprotocol/sdk` 创建 MCP Server
2. StdioServerTransport（CC 通过 stdin/stdout 调用）
3. 一个工具 `reply`：
   - `chat_id`（必需）— 回复到哪个会话
   - `message_id`（可选）— 精确匹配消息
   - `content`（必需）— 回复文本
4. WebSocket 连接到 Hub（`ws://127.0.0.1:7890/mcp`，端口跟我们 VPS 配置匹配）
5. 自动重连 + 指数退避（1s→2→4→8→16→30s capped）
6. **关键**：永不 throw、永不 stderr——`process.on("uncaughtException/unhandledRejection", () => {})`

**注意**: 基本照抄粟粟的，但改这些：
- Hub URL 改成我们的 VPS 端口配置（检查 `.env` 里的端口设置）
- 暂时不做 `file_path` 参数（Phase 4 再加）

**文件路径**: `cc-bridge/mcp-server.ts`（覆盖我们现有的）
**commit**: `feat(cc-bridge): rewrite mcp-server with @modelcontextprotocol/sdk`

---

## Task 2: 重写 hub.ts 基础部分

**参考**: 粟粟的 `/root/projects/SusuPalace/cc-bridge/hub.ts`（前 400 行）

**只做 Phase 1 的基础功能**:

1. **WebSocket 服务器**（用 Bun 原生 WebSocket）
   - 监听端口 7890（或 .env 配置的端口）
   - 两种客户端：`/ws`（App 客户端）和 `/mcp`（MCP Server 客户端）
   - 客户端注册/注销

2. **消息路由**
   - App → Hub：`{ type: "chat", chat_id, message_id, content }` → 转发给 CC（tmux send-keys）
   - MCP → Hub：`{ type: "reply", chat_id, content }` → 转发给 App 客户端
   - tmux send-keys 入站：把用户消息注入到 CC 的 tmux session

3. **tmux send-keys 入站格式**
   参考粟粟的实现——用 `<channel source="memorypalace">` XML 标签包裹用户消息：
   ```
   <channel source="memorypalace" chat_id="xxx" message_id="yyy">
   用户消息内容
   </channel>
   ```
   CC 看到这个标签就知道是来自 App 的消息。

4. **关键注意**:
   - 用 `execFileSync("tmux", ["send-keys", ...])` 不要用 `execSync`（shell 转义问题）
   - 注入前 strip 换行符（send-keys 遇到 `\n` 当 Enter 截断）
   - 消息太长时（>4000字符）截断或分段

**不做的（后续 Phase）**:
- 终端流（pipe-pane）— Phase 2
- 焦点推送（focusByClient）— Phase 3
- APNs — Phase 3
- 图片/文件互发 — Phase 4
- 离线补发 — Phase 4

**文件路径**: `cc-bridge/hub.ts`（覆盖现有的）
**commit**: `feat(cc-bridge): rewrite hub with WebSocket routing + tmux send-keys`

---

## Task 3: 启动脚本和配置

1. **start_hub.sh** — 启动 Hub 的脚本
   ```bash
   #!/bin/bash
   cd "$(dirname "$0")"
   exec bun run hub.ts
   ```

2. **start_cc.sh** — 启动 CC 的脚本（在 tmux session 里启动 Claude Code + MCP Server）
   参考粟粟的 start_cc.sh，关键是：
   - 创建 tmux session（名字叫 `mp-cc` 或配置里的名字）
   - 在 session 里启动 `claude --dangerously-skip-permissions`（或其他 CC 命令）
   - CC 的 MCP config 指向我们的 mcp-server.ts

3. **mcp.template.json** — CC 的 MCP 配置模板
   参考粟粟的，指向我们的 mcp-server.ts 路径

4. **package.json** — 确保依赖正确
   需要：`@modelcontextprotocol/sdk`、`ws`（如果 Bun 原生 WebSocket 不够用的话）

**commit**: `feat(cc-bridge): add startup scripts + MCP config template`

---

## Task 4: App 端 CCBridgeWebSocketClient 适配

**文件**: `MemoryPalace/Services/CCBridgeWebSocketClient.swift`

**检查/修改**:
1. 确认 WebSocket 连接的 URL 路径是 `/ws`（不是 `/mcp`，`/mcp` 是给 MCP Server 用的）
2. 确认发送消息的格式是 `{ type: "chat", chat_id, message_id, content }`
3. 确认接收消息的格式能解析 `{ type: "reply", chat_id, content }`
4. 不要消费 `cc_stream` 类型消息（已经在前面关掉了）

**如果格式不匹配**，对照新 hub.ts 的消息格式调整 Swift 端。

**commit**: `fix(cc-bridge): align WebSocket message format with new hub`

---

## 测试方法（在 VPS 上手动测试）

完成后在 VPS 上手动验证：

```bash
# 1. 启动 Hub
cd /root/projects/BunnyPalace/cc-bridge && bun run hub.ts &

# 2. 用 websocat 模拟 App 客户端
websocat ws://127.0.0.1:7890/ws

# 3. 发一条测试消息
{"type":"chat","chat_id":"test","content":"hello from test"}

# 4. 检查 tmux session 有没有收到
tmux capture-pane -t mp-cc -p | tail -5
```

---

## 规则

- Task 1-4 按顺序做，每个 Task 单独 commit + push
- commit message 格式：`feat(cc-bridge): 简述`
- **开始前完整读粟粟的代码**（mcp-server.ts 全部 + hub.ts 前 400 行）
- 不要加 Phase 2-4 的功能（终端流/推送/文件/离线补发）
- 不要动 Gateway（gateway/src/）的代码
- 遇到不确定的地方写 `// TODO: Phase 2+` 注释

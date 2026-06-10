# 第八批任务 — CC Bridge Phase 2-4

> 日期：2026-06-10
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 参考代码：粟粟原版 VPS `/root/projects/SusuPalace/cc-bridge/`
> Phase 1 已完成（mcp-server + hub基础 + 启动脚本）

---

## Phase 2: 终端实时流（pipe-pane）

### 背景
Phase 1 的 hub 只有消息路由（chat→tmux send-keys, reply→App）。
粟粟用 `tmux pipe-pane + mkfifo + cat spawn` 做终端实时流——CC 在 terminal 里打字的每一个字符都实时推给 App 的终端面板。

### Task 2.1: hub.ts 加终端流

**参考**: 粟粟 hub.ts 第 230-280 行的 `TerminalAttachment` 相关代码

**要做的事**:
1. 定义 `TerminalAttachment` 接口（sessionName, fifoPath, catProc, mpClients）
2. `createTerminalAttachment(sessionName)` 函数：
   - `mkfifo` 创建命名管道
   - `tmux pipe-pane -t sessionName -o "cat > fifoPath"` 把 pane 输出导到管道
   - `spawn("cat", [fifoPath])` 持续读管道
   - `catProc.stdout.on("data")` → 广播 `terminal_chunk` 消息给所有已 attach 的客户端
3. `closeTerminalAttachment(sessionName)` 函数：清理 fifo + kill cat 进程
4. WebSocket 消息处理：
   - 客户端发 `{ type: "terminal_attach", session_name }` → 创建/加入 attachment
   - 客户端发 `{ type: "terminal_detach" }` → 移除，最后一个走了关闭 attachment
   - 客户端发 `{ type: "terminal_input", data }` → `tmux send-keys` 转发键盘输入
   - 客户端发 `{ type: "terminal_resize", cols, rows }` → `tmux resize-window`

**关键注意**:
- `catProc.stdout` 必须及时消费！否则 fifo 写阻塞 → tmux 冻死 → CC 冻死
- 广播时检查 `ws.readyState === ws.OPEN`，死 socket 跳过
- attach 时先发一次 `terminal_init`（capture-pane 当前屏幕快照）给新客户端

**commit**: `feat(cc-bridge): Phase 2 — terminal stream via pipe-pane + mkfifo`

### Task 2.2: App 端 CCTerminalPanelView 对接

**文件**: `MemoryPalace/Views/CCTerminalPanelView.swift`（猫已从粟粟搬过来了）

**检查/修改**:
1. 确认 CCBridgeWebSocketClient 能发送 `terminal_attach`/`terminal_detach`/`terminal_input`/`terminal_resize`
2. 确认能接收 `terminal_init` 和 `terminal_chunk` 消息并 feed 给 SwiftTerm
3. 如果 CCBridgeWebSocketClient 缺少这些方法，补上

**commit**: `feat(cc-bridge): Phase 2 — CCTerminalPanelView WebSocket integration`

---

## Phase 3: 推送通知

### Task 3.1: hub.ts 加焦点推送逻辑

**参考**: 粟粟 hub.ts 的 `focusByClient` Map

**要做的事**:
1. 维护 `focusByClient: Map<WebSocket, string | null>` — 记录每个客户端在看哪个会话
2. 客户端发 `{ type: "focus", chat_id }` → 更新 focusByClient
3. 客户端发 `{ type: "blur" }` → 设为 null
4. CC reply 到 chat_id C 时，检查是否有客户端在看 C：
   - 有人在看 → 只发 WebSocket，不推送
   - 没人在看 → 发 WebSocket + 调 APNs 推送

**commit**: `feat(cc-bridge): Phase 3.1 — focus-driven push decision logic`

### Task 3.2: apns.ts 推送发送器

**参考**: 粟粟 `/root/projects/SusuPalace/cc-bridge/apns.ts`（73行）

**要做的事**:
1. 基本照抄粟粟的 apns.ts
2. 改配置：
   - KEY_PATH → 我们的 AuthKey 路径（`cc-bridge/secrets/AuthKey_PDAH2QTZ3W.p8`）
   - KEY_ID → `PDAH2QTZ3W`
   - TEAM_ID → `GQN42B462A`
   - TOPIC → `com.susu.MemoryPalace.ios`
   - HOST → sandbox（开发阶段）
3. 从 hub.ts 的 reply 处理里调用 `sendPush(deviceToken, title, body)`
4. 需要 App 端注册 deviceToken 并通过 WebSocket 发给 hub

**前置**:
- 把 AuthKey_PDAH2QTZ3W.p8 放到 `cc-bridge/secrets/` 目录
- 文件在 VPS `/mnt/user-data/uploads/AuthKey_PDAH2QTZ3W.p8` 或 `/root/projects/BunnyPalace/certs/`

**commit**: `feat(cc-bridge): Phase 3.2 — APNs push via .p8 ES256 JWT`

---

## Phase 4: 高级功能

### Task 4.1: 离线消息补发

**参考**: 粟粟 hub.ts 的持久化逻辑

**要做的事**:
1. CC reply 时，如果目标 chat_id 没有在线客户端，把消息持久化到文件
   - 路径：`cc-bridge/offline/{chat_id}.json`
   - 格式：`[{ content, timestamp, message_id }]`
   - 按条数保留（最多 50 条）
2. 客户端连接时，检查有没有离线消息，有就补发
3. 补发后清除已发送的消息

**commit**: `feat(cc-bridge): Phase 4.1 — offline message durability + replay`

### Task 4.2: 图片/文件互发（可选，后续做）

**暂不实现**——等写作系统和文件库完善后再做。标注 `// TODO: Phase 4.2` 留位。

---

## 规则

- 按 Phase 顺序做（2→3→4），每个 Task 单独 commit + push
- 开始前完整读粟粟的参考代码
- hub.ts 在 Phase 1 基础上增量添加，不要重写已有的消息路由
- 不要动 Gateway（gateway/src/）的代码
- 遇到不确定的写 `// TODO` 注释

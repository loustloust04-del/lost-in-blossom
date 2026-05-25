# CC Bridge

本地把 Claude Code（CC）接进记忆宫殿（MP）的桥接服务。MP 把它当一个新的 Provider 用，跟 OpenAI / Anthropic 平级。

设计稿：[`docs/superpowers/specs/2026-05-18-cc-bridge-design.md`](../docs/superpowers/specs/2026-05-18-cc-bridge-design.md)
实施清单：[`docs/superpowers/plans/2026-05-18-cc-bridge.md`](../docs/superpowers/plans/2026-05-18-cc-bridge.md)

## 工作原理

```
MP（Mac app）  ──ws──>  hub.ts  ──tmux send-keys──>  CC（tmux session mp-cc）
        ▲                  ▲                                 │
        └────── ws ────────┴────── stdio ──── mcp-server.ts ◀┘
```

- **出站**（用户消息 → CC）：MP 通过 WebSocket 把消息发给 hub，hub 用 `tmux send-keys` 注入 CC 终端
- **入站**（CC 回复 → MP）：CC 调 MCP 工具 `reply`，mcp-server.ts 通过 WebSocket 转发给 hub，hub 广播给 MP

## 前置依赖

- **Bun**：`brew install oven-sh/bun/bun`
- **tmux**：`brew install tmux`
- **Claude Code（claude CLI）**：已装，路径在 `~/.local/bin/claude`
- 可选 **wscat**（仅 smoke test 用）：`npm install -g wscat`

## 启动（粟粟日常用法）

```bash
cd cc-bridge
bun install             # 首次或更新依赖后跑

# 终端 1：启动 hub
bash start_hub.sh

# 终端 2：启动 CC（在 tmux session mp-cc 里）
bash start_cc.sh
```

启动后：

1. 在 MP **设置页 → API Settings** 里选 **Claude Code (本地)** provider — 右边状态点应该是绿的
2. 在主对话页底部 **模型选择器** 里选 `Claude Code`
3. 发消息，等 CC 思考完回复（30s 内）

## v1 已知局限

- **不流式**：CC 整段回，UI 是"发→spinner→整段出现"，没有打字机效果
- **不支持 MP 分支**：CC 是单 session，切 MP 分支它不知道，UI 也不会提示
- **MP 的 preset / 角色卡 / 世界书 不生效**：ccBridge 路径绕过 PromptAssembler；CC 的人设和记忆走 CC 自己的 CLAUDE.md
- **CC 工具调用看不见**：CC 调 Read/Bash/Edit 时 MP 不显示中间过程，只显示最终 reply
- **hub 没自动起**：MP 启动 ≠ hub 启动，得手动跑 `start_hub.sh`
- **README 路径写死在 worktree 下**：设置页那个"查看启动说明"按钮的路径将来要 bundle 化

## 进阶

### 改 CC 的工作目录

```bash
MP_CC_WORKDIR=~/Documents bash start_cc.sh
```

默认是 worktree 根目录（开发场景方便，CC 能读 CLAUDE.md / 源码）。

### 改 tmux session 名

```bash
MP_CC_TMUX_SESSION=cc-test bash start_cc.sh
MP_CC_TMUX_SESSION=cc-test bash start_hub.sh
```

两边要一致。

## Smoke Test（不开 MP，验证 hub+CC 链路）

```bash
# 终端 1
cd cc-bridge && bash start_hub.sh
# 看到 [hub] listening on ws://127.0.0.1:7890/cc

# 终端 2
cd cc-bridge && bash start_cc.sh
# tmux session 里跑着 CC，输 /mcp 应该列出 cc-bridge / reply

# 终端 3
wscat -c ws://127.0.0.1:7890/cc
# 连上后发：
> {"type":"send","chat_id":"test-1","message_id":"m1","content":"你好，调一下 reply 工具回我","user":"susu"}
```

预期：
- wscat 立刻收到 `{"type":"ack","message_id":"m1"}`
- 切回终端 2（tmux），CC 看到 `<channel ...>` 开始思考
- CC 思考完调 reply，wscat 收到 `{"type":"reply","chat_id":"test-1","content":"..."}`

## 自动测试

不依赖 tmux / CC：

```bash
cd cc-bridge && bun test
```

应 5 pass 0 fail（hub WS 路由 + tmux send-keys + MCP broadcast 都有覆盖）。

## 排障

### "MP 设置页里 Claude Code (本地) 连接状态一直是灰的"

- hub 没跑：`bash start_hub.sh`
- hub 跑了但端口冲突：`lsof -i :7890` 看谁占的，kill 掉旧的
- MP 启动时机：MP 自动连一次，连不上不会一直重试到无穷大。可以点设置页 "重新连接" 按钮触发

### "MP 发消息没回应（spinner 一直转）"

- 终端 2（tmux）里 CC 是不是在干别的事？CC 一次只处理一条
- CC 加载 MCP 失败：在 CC 里 `/mcp` 看 `cc-bridge` 在不在。不在的话检查：
  - `cc-bridge/.mcp.json` 的路径是否指向真实存在的 `mcp-server.ts`
  - `start_cc.sh` 启动时是否成功 render 了 `.mcp.json`（看 `cat cc-bridge/.mcp.json`）

### "hub 日志说 MP connected 但 reply 没回到 MP"

- chat_id 不匹配：CC 调 reply 时传的 chat_id 必须和入站 `<channel chat_id="...">` 一致——CCBridgeProvider 用 conversation.id 当 chat_id 注册 handler，CC 回复时也应该用同一个
- mcp-server 没连 hub：hub 日志找 `[hub] MCP connected` — 没有说明 mcp-server.ts 启动后 WS 连接失败（看 mcp-server.ts 的 stderr，CC 会展示）

### "CC 第二次发消息卡住"

- CC 在前一条还没处理完（思考 / 调工具中），tmux 注入的新消息会和它输出混合
- 等 CC 输出完毕 / 在 CC 里按 ESC 中断当前思考

### "想杀干净重启"

```bash
tmux kill-session -t mp-cc 2>/dev/null
lsof -ti :7890 | xargs kill 2>/dev/null
# 然后重新走启动流程
```

## 文件作用

| 文件 | 干嘛 |
|---|---|
| `hub.ts` | WebSocket 服务器，端口 7890，桥接 MP ↔ tmux ↔ MCP |
| `mcp-server.ts` | MCP stdio server，提供 `reply` 工具给 CC |
| `mcp.template.json` | MCP 配置模板（启动时 render 成 `.mcp.json`） |
| `start_hub.sh` | 起 hub |
| `start_cc.sh` | 起 CC（在 tmux 里，加载 MCP 配置） |
| `hub.test.ts` / `mcp-server.test.ts` | bun:test 自动测试 |

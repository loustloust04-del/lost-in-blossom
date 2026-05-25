# CC Bridge —— 让记忆宫殿用 Claude Code 当后端

**日期**：2026-05-18
**作者**：粟粟 + 小雾
**状态**：design / pending implementation
**Worktree**：`.claude/worktrees/cc-bridge`（分支 `worktree-cc-bridge`）

---

## 0. 一句话

让记忆宫殿（MP）把本地跑的 Claude Code CLI（CC）当作一种新的 Provider 接入，用户在 MP 对话里能直接和 CC 聊，CC 的回复以 MessageNode 形式落库。

参考：[Shitsuten/cc-self-hosting-guide](https://github.com/Shitsuten/cc-self-hosting-guide) 的 tmux 注入方案。

---

## 1. 背景与动机

MP 现在支持 6 家 API 提供商，全部是无状态 chat completion。CC 是一种完全不同的对话后端：

- **有状态长跑 session**（不是每轮重发 history）
- **能调工具**（Read / Bash / Edit / MCP servers）
- **有自己的记忆**（CLAUDE.md / 项目 memory）

接入 CC 意味着 MP 用户能在熟悉的 MP UI 里跟一个真正的 agent 对话——不只是 chat completion，而是会读文件、跑命令、记得长期上下文的"小雾"。

这是方案 **B**：把 CC 接成第三种 Provider，复用 MP 的 MessageNode / 树 / 搜索 / 导出基础设施。
（方案 A 是"独立窗口"，被排除——见决策日志。）

---

## 2. 架构总图

```
┌──────────────────────────┐
│  MemoryPalace (Mac app)  │
│  ─────────────────────   │
│  ConversationViewModel   │
│  ChatService             │
│  └─ CCBridgeProvider ◄───┼──── WebSocket (port 7890)
└──────────────────────────┘                │
                                            ▼
                          ┌──────────────────────────────┐
                          │  cc-bridge-hub (Bun process) │
                          │  ──────────────────────────  │
                          │  · WS server (MP 端)         │
                          │  · WS server (MCP 端)        │
                          │  · tmux send-keys driver     │
                          └──┬──────────────────┬────────┘
                             │                  │
                  tmux send-keys             WebSocket
                             │                  │
                             ▼                  ▼
                  ┌───────────────────┐  ┌────────────────────┐
                  │ tmux session      │  │ cc-bridge-mcp.ts   │
                  │ "mp-cc"           │  │ (MCP server, CC    │
                  │                   │  │  loads via .mcp)   │
                  │ ┌───────────────┐ │  └──────┬─────────────┘
                  │ │ claude (CC)   │◄┼─────────┘ stdio
                  │ └───────────────┘ │
                  └───────────────────┘
```

**关键不变量**：
- 入站走 tmux `send-keys`（不走 `--channels` flag —— 新版 CC 会 crash）
- 出站走 MCP `reply` tool（稳定通道）
- 消息格式用 `<channel source="memorypalace" ...>` tag，CC 内置认这个格式

---

## 3. 组件清单

### 3.1 Swift 侧（MP 代码）

| 文件 | 类型 | 改动 |
|---|---|---|
| `MemoryPalace/Models/APIProvider.swift` | 改 | `ProviderType` 加 `case ccBridge`；`ProviderManager` 注册一条内置 provider：`name="Claude Code (本地)"`, `baseURL="ws://localhost:7890/cc"` |
| `MemoryPalace/Services/ChatService.swift` | 改 | 新增 `final class CCBridgeProvider: BaseChatProvider`；`ProviderRouter` switch 加分支 |
| `MemoryPalace/Services/CCBridgeWebSocketClient.swift` | 新 | `URLSessionWebSocketTask` 薄封装：连/收/发/重连 |
| `MemoryPalace/ViewModels/ConversationViewModel.swift` | 改 | `sendStreaming` 之前判 provider type：ccBridge 跳过 `PromptAssembler.assemble`，直接构造 `[(role: "user", content: rawText)]`（PromptAssembler 保持 pure） |
| `MemoryPalace/Views/APISettingsTab.swift` | 改 | provider 编辑 UI 适配 ccBridge：baseURL → ws URL，apiKey 字段隐藏或改成"hub token (可选)" |

### 3.2 外部脚手架（仓库根 `cc-bridge/` 目录，**不进 Xcode 工程**）

| 文件 | 作用 |
|---|---|
| `cc-bridge/hub.ts` | WS server（端口 7890），双向桥接 MP ↔ MCP server，封装 `tmux send-keys` |
| `cc-bridge/mcp-server.ts` | CC 启动时拉起的 MCP server，提供 `reply(chat_id, content)` 工具 |
| `cc-bridge/.mcp.json` | CC 的 MCP 配置：注册 mcp-server.ts |
| `cc-bridge/start_cc.sh` | 启动脚本：`tmux new-session -d -s mp-cc 'claude'` |
| `cc-bridge/start_hub.sh` | 启动 hub：`bun run hub.ts` |
| `cc-bridge/package.json` | Bun 依赖（ws, @modelcontextprotocol/sdk） |
| `cc-bridge/README.md` | 本地启动步骤 + 排障 |

技术栈：**Bun + TypeScript**（跟原 repo 一致；Node 也能跑但 Bun 自带 WS 更省事）。

---

## 4. 数据流

### 4.1 出站（用户消息 → CC）

1. 用户在 MP 的 ccBridge 对话里输入"早上好"
2. `ConversationViewModel` 走正常流程：创建 `userMessage` MessageNode，存入 SwiftData，加入当前分支
3. 调 `ProviderRouter.sendStreaming(...)`，model 的 provider type 是 `.ccBridge`
4. Router 路由到 `CCBridgeProvider`
5. `CCBridgeProvider` 构造 channel tag：
   ```xml
   <channel source="memorypalace" chat_id="{conversationId}" message_id="{userMessageNodeId}" user="susu" ts="2026-05-18T03:00:00.000Z">
   早上好
   </channel>
   ```
6. 通过已连接的 WebSocket 发给 hub（断了先重连，配置的超时内连不上→onError）
7. **必须 strip 换行符**：`content.replace("\n", " ")`（参考原 repo 教训）
8. hub 收到，调 `execFileSync('tmux', ['send-keys', '-t', 'mp-cc', '-l', tag])` 然后再 `send-keys ... Enter`
9. CC 在 tmux 里看到这条文字，按 channel tag 处理为"用户输入"

### 4.2 入站（CC 回复 → MP）

1. CC 思考完，决定回复，调 MCP `reply` 工具：`{chat_id: "{conversationId}", content: "早，今天想做什么？"}`
2. `mcp-server.ts` 收到 tool call，通过 WS 转发给 hub
3. hub 通过 MP 端 WS 广播给所有订阅了该 chat_id 的客户端
4. `CCBridgeWebSocketClient` 收到，按 chat_id 路由到对应的 active `CCBridgeProvider`
5. `CCBridgeProvider` 调 `onComplete(content, nil)` —— **一次性整段返回**（v1 不做伪流式）
6. `ConversationViewModel` 把内容作为 `assistantMessage` MessageNode 存进 SwiftData，appendChild 到 user node

### 4.3 错误路径

| 场景 | 表现 | 处理 |
|---|---|---|
| hub 进程没起 | 连不上 ws://localhost:7890 | `onError("CC Bridge hub 未运行，请先 `bash cc-bridge/start_hub.sh`")` |
| tmux session 不存在 | hub 端 `tmux send-keys` 报错 | hub 回写 WS error 帧 → `onError("tmux session mp-cc 不存在")` |
| CC 进程崩了 | send-keys 成功但永远不会有 reply | 用户端可见超时 spinner，**v1 不做自动检测**，用户手动重启 |
| WS 中途断开 | URLSessionWebSocketTask 报错 | 自动重连（指数退避：1s, 2s, 4s, 8s, 30s 封顶）；当前请求 `onError("连接中断")` |

---

## 5. 关键决策（不能完美的地方）

### 5.1 v1 不做流式

CC 通过 MCP `reply` 工具一次性回整段，不是 token stream。

- **影响**：UI 上用户发→等 spinner→整段出现，没有"打字机效果"
- **接受理由**：MVP 优先，代码极简，体验损失不是 dealbreaker
- **v2 出路**：hub 端跑 `tmux capture-pane` 差异推送，伪造流式

### 5.2 v1 不支持分支切换上下文同步

CC 是线性 session，MP 是树。用户在 ccBridge 对话里切到老分支：

- **CC 那边不知道**——它的 context 还停在最新那条
- **v1 处理**：UI 上显示一个 banner："CC 不知道你切了分支，它的回复会基于最新上下文"
- **不阻止用户操作**——让用户自己决定
- **v2 出路**：分支切换时往 CC 注入 `[branch-switch] ...` 系统提示，让 CC 自己 update context（但 CC 接受度不确定）

### 5.3 v1 不复用 MP 的 prompt 系统

ccBridge provider 在 `ProviderRouter` 里走特殊路径：

- **不组装 system prompt / preset / world book / memory**
- **只发原始 user 文字**（包成 channel tag）
- **"小雾人设" 的责任交给 CC 那边的 CLAUDE.md / `--append-system-prompt-file`**

这是粟粟明确的要求："先不管原生记忆宫殿的 prompt 管理和注入"。

实现上：`ConversationViewModel.sendStreaming` 调 `providerRouter.sendStreaming` 之前判 `provider.type == .ccBridge`，是 ccBridge 就跳过 `PromptAssembler.assemble`，直接构造 `(systemPrompt: nil, messages: [(role: "user", content: rawText)], sampling: .default)`。PromptAssembler 本身保持 pure 不动。

### 5.4 多对话并发

v1 假设 **一个 CC session 一次只服务一条 in-flight 消息**。

- 用户在两个 ccBridge 对话里同时发消息 → 都会进 tmux，但 chat_id 不同
- CC 实际上一次只处理一条，第二条会排队等 CC 空闲
- chat_id 用来让 hub 路由 reply 给对的 MP 对话
- **v1 不做排队 UI 提示**，CC 自己排队，MP 端 spinner 转着

### 5.5 不显示工具调用过程

CC 调 Read / Bash / Edit 时 MP 不显示中间过程，只显示最终 reply 文本。

- **v2 出路**：终端视图 tab（capture-pane 轮询）

### 5.6 安全 / 权限

- hub 只 bind `127.0.0.1`，不接受外部连接
- 可选 token：hub 启动时生成一个 token，写到 `~/.cc-bridge-token`，MP 连接时带上
- v1 **不做 token**（本机单机用），但接口预留

---

## 6. MVP（v1）范围

### 做

- [ ] `CCBridgeProvider` 类（Swift）：连 WS、发 channel tag、接收 reply、错误处理
- [ ] `CCBridgeWebSocketClient`：WS 连接管理、自动重连
- [ ] `APIProvider.swift` 加 `.ccBridge` enum case
- [ ] `ProviderRouter` 加分支
- [ ] `PromptAssembler` ccBridge 特殊路径（绕过 prompt 组装）
- [ ] `APISettingsTab` 适配 UI
- [ ] `cc-bridge/hub.ts`、`mcp-server.ts`、`.mcp.json`、启动脚本
- [ ] `cc-bridge/README.md`（本地启动步骤）
- [ ] 连接状态指示器（设置页 / 对话页 ribbon 上一个绿点 / 红点）
- [ ] 内置一条默认 ccBridge provider `ws://localhost:7890/cc`，开箱即用

### 不做（v2 再说）

- 流式渲染（伪流式 capture-pane）
- 终端视图 tab
- 工具调用可视化
- 分支切换上下文同步
- 文件附件 / 图片
- nudge / 主动行为
- watchdog / 自动重启 hub
- Token 鉴权
- Session 轮换（context 满了的处理）

---

## 7. 文件清单

```
worktree-cc-bridge/
├── MemoryPalace/
│   ├── Models/APIProvider.swift                       # 改：+ .ccBridge case + 内置 provider 注册
│   ├── Services/
│   │   ├── ChatService.swift                          # 改：+ CCBridgeProvider
│   │   └── CCBridgeWebSocketClient.swift              # 新
│   ├── ViewModels/ConversationViewModel.swift         # 改：ccBridge 短路（绕过 PromptAssembler）
│   └── Views/APISettingsTab.swift                     # 改：UI 适配
├── cc-bridge/                                          # 新目录，gitignore .DS_Store
│   ├── hub.ts
│   ├── mcp-server.ts
│   ├── .mcp.json
│   ├── start_cc.sh
│   ├── start_hub.sh
│   ├── package.json
│   ├── bun.lockb
│   └── README.md
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-05-18-cc-bridge-design.md         # 本文件
└── .gitignore                                          # 加 cc-bridge/node_modules
```

---

## 8. 测试计划

### 8.1 Swift 侧（XCTest）

- `CCBridgeProviderTests`
  - 构造 channel tag 格式正确（chat_id, message_id, user, ts）
  - 换行符被替换成空格
  - WS 收到 reply 后 onComplete 被调用且内容匹配
  - WS 错误 → onError 被调用
  - reply 的 chat_id 不匹配当前请求 → 忽略
- `CCBridgeWebSocketClientTests`
  - 断线重连指数退避
  - 多个 listener 注册 / 注销

### 8.2 外部侧（bun test）

- `hub.test.ts`
  - MP→hub→tmux 注入（mock tmux）
  - MCP→hub→MP 广播
  - WS 断开自动重连
- `mcp-server.test.ts`
  - `reply` tool 被调用时往 hub 发 WS 帧

### 8.3 端到端手测

按 `cc-bridge/README.md` 步骤：

1. `bash cc-bridge/start_hub.sh`
2. `bash cc-bridge/start_cc.sh`
3. MP 打开，新建对话，选 "Claude Code (本地)" 模型
4. 发 "你好"
5. 30 秒内应该收到 CC 的回复
6. 检查 MessageNode 树正常落库

---

## 9. 决策日志

### 9.1 为什么不选方案 A（独立窗口）

最初推荐 A，理由是隔离性、低风险。粟粟选了 B，理由：

- B 复用 MP 的所有现有能力（分支、搜索、导出、字号缩放、配色）
- B 是"对话流的自然延伸"，用户心智模型不分裂
- worktree 本来就是试错空间，B 出问题就 revert，不会污染 master

A 留作 fallback：如果 B 实施过程中发现 ProviderRouter / SwiftData 强耦合到走不通，回到 A。

### 9.2 为什么用 Bun 不用 Swift 起 WS server

- 原 repo 已经是 Bun + TS，能直接借鉴 hub.ts / mcp-server.ts 模板
- MCP TypeScript SDK 比 Swift SDK 成熟
- hub 是独立进程，跟 MP 的 lifecycle 解耦——MP crash 不影响 CC 长跑 session
- 代价：用户机器需要装 Bun（`brew install oven-sh/bun/bun`），README 里写清楚

### 9.3 为什么不复用 MP 的 prompt 系统

粟粟原话："先不管原生记忆宫殿的 prompt 管理和注入"。

技术上也是对的：CC 自己有 system prompt（来自 `--system-prompt` / CLAUDE.md），MP 再塞一个 system prompt 就是双 system prompt 冲突。CC 不接受外部覆盖它的 system，最多接受 `--append-system-prompt-file` 追加。

v2 如果要"让 MP 的小雾人设也在 CC 对话里生效"，路径是：MP 把 preset 转成一个文件，启动脚本带 `--append-system-prompt-file` 加进去。不在 v1 范围。

---

## 10. Open Questions

> v1 默认选择见每条括号，粟粟可以推翻。

1. **ccBridge provider 在 model 选择 UI 怎么显示？**（默认：跟其他 model 平级，显示为 `Claude Code (本地)`，model name = `cc-bridge`）
2. **hub 是 MP 启动时自动拉起，还是手动？**（v1 手动，README 教用户跑 `start_hub.sh`；v2 看是否做 MP 内嵌进程管理）
3. **没装 Bun 的用户怎么办？**（v1 README 写清楚装 Bun 命令；v2 看是否打包静态二进制）
4. **chat_id 用什么？conversationId 还是 profile+conversation 组合？**（默认 conversationId，因为 MP 同时只有一个 profile 活动）
5. **CC 的 working directory 是什么？**（默认 MP 仓库根目录，让 CC 能读到 CLAUDE.md / docs / Memory Palace 源码——对开发场景超级有用；用户对话场景可能想换到 `~/Documents` 之类，v1 在 start_cc.sh 里写死，README 教改）（设置页里放一个弄目录的地方）

---

## 11. 实施步骤大纲（具体 plan 由 writing-plans skill 产出）

按 CLAUDE.md 的 dev-workflow（Research → Plan → Implement），下一步是 writing-plans 出 task checklist。

大致顺序：

1. 先把 `cc-bridge/` 那边 hub + mcp-server + tmux + CC 跑通（外部脚手架，跟 MP 解耦）
2. 用 `wscat` 之类工具手测端到端（不动 MP 代码）
3. 再写 Swift 侧 `CCBridgeWebSocketClient`，单元测试
4. 加 `CCBridgeProvider`，绕过 PromptAssembler
5. 改 `APIProvider.ProviderType` + `ProviderRouter`
6. 改 UI（APISettingsTab + provider 注册）
7. 端到端联调
8. 文档 + README

---

**End of design.**

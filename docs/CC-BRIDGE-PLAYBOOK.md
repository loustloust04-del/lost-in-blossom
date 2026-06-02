# CC Bridge 运维手册 — Bunny & Caelum

> 2026-06-02 首次编写。这份文档记录了 CC Bridge 从"完全不工作"到"8秒回复"的完整排查过程。下次遇到问题直接对照着修。

---

## 一、架构图

```
兔兔的 iPhone (Lost in Blossom)
    │
    │  ws://172.245.88.103:8890/cc
    ▼
┌──────────────────┐
│  UFW 防火墙       │  ← 8890 端口必须放行
└──────────────────┘
    │
    ▼
┌──────────────────┐
│  nginx (8890)     │  ← 非 SSL，反向代理 WebSocket
│  sites-available/ │
│  ip-mcp           │
└──────────────────┘
    │  proxy_pass http://127.0.0.1:7890
    ▼
┌──────────────────┐
│  hub.ts (7890)    │  ← tmux session: cc-hub
│  bun run hub.ts   │  ← 绑定 127.0.0.1:7890
└──────────────────┘
    │                           ▲
    │ tmux send-keys -t mp-cc   │ WebSocket /mcp
    ▼                           │
┌──────────────────┐    ┌──────────────────┐
│  Claude Code      │───▶│  mcp-server.ts    │
│  tmux: mp-cc      │    │  (CC 自动启动)     │
│  --mcp-config     │    │  reply 工具        │
└──────────────────┘    └──────────────────┘
```

**消息流向：**
1. 出站：App → nginx → hub → tmux send-keys → CC
2. 入站：CC 调 reply 工具 → mcp-server → hub → nginx → App

---

## 二、关键文件位置

| 文件 | 路径 | 用途 |
|------|------|------|
| hub.ts | `/root/projects/MemoryPalace/cc-bridge/hub.ts` | WebSocket hub 服务 |
| mcp-server.ts | `/root/projects/MemoryPalace/cc-bridge/mcp-server.ts` | CC 的 reply MCP 工具 |
| .mcp.json | `/root/projects/MemoryPalace/cc-bridge/.mcp.json` | CC 的 MCP 配置（自动生成） |
| start_all.sh | `/root/projects/MemoryPalace/cc-bridge/start_all.sh` | 一键启动脚本 |
| CC 权限配置 | `/root/projects/MemoryPalace/.claude/settings.local.json` | reply 工具免确认 |
| CC 认证 token | `/root/.claude/.credentials.json` | OAuth token（login.mjs 生成） |
| 登录脚本 | `/root/login.mjs` | 自定义 OAuth 登录（绕过官方 CLI 截断 bug） |
| nginx 配置 | `/etc/nginx/sites-available/ip-mcp` | 8890 端口非 SSL 代理 |
| hub 日志 | `/tmp/cc-hub.log` | hub 实时日志 |
| App 源码 | `/root/projects/BunnyPalace/` | Lost in Blossom 源码仓库 |
| App 编译产物 | `/var/www/lib-dl/LostInBlossom.ipa` | 编译后自动部署的 ipa |

---

## 三、一键启动

```bash
bash /root/projects/MemoryPalace/cc-bridge/start_all.sh
```

这个脚本会：
1. 读取 OAuth token
2. 渲染 .mcp.json
3. 启动 hub（tmux session: cc-hub）
4. 启动 CC（tmux session: mp-cc，带 OAuth + MCP 配置）

启动后在 App 里填 `ws://172.245.88.103:8890/cc` 连接。

---

## 四、今天遇到的所有问题和解决方案

### 问题 1：编译失败 — @ViewBuilder 放错行
**症状：** GitHub Actions Archive 步骤失败
**原因：** 猫把 `@ViewBuilder` 标注放在了 `@State` 变量上面（APISettingsTab.swift:427）
**修复：** 删掉那行 `@ViewBuilder`
**commit：** `fix: remove stray @ViewBuilder on @State property`

### 问题 2：编译失败 — CCBridgeProvider 缺少 onSegmentsCallback
**症状：** Archive 步骤再次失败
**原因：** ChatService 里给 ccBridgeProvider 赋值 onSegmentsCallback，但 CCBridgeProvider 类没有这个属性
**修复：** 在 CCBridgeProvider 里加上 `var onSegmentsCallback: (([MessageSegment]) -> Void)?`
**commit：** `fix: add onSegmentsCallback to CCBridgeProvider`

### 问题 3：SSL 证书过期
**症状：** App 填 wss://172.245.88.103/cc 连接不上
**原因：** nginx 的 SSL 证书 4 月 21 日过期，iOS 拒绝 TLS 握手
**修复：** 绕过 SSL，用非加密 WebSocket（ws:// 而非 wss://）。新增 nginx server block 在 8890 端口监听，代理到 hub 的 7890
**配置位置：** `/etc/nginx/sites-available/ip-mcp` 末尾的 `listen 8890` server block

### 问题 4：防火墙没开 8890 端口
**症状：** App 连接无反应，像"根本没尝试过连接"
**原因：** UFW 只开了 80/443/6080 等端口，8890 没放行。App 的请求被防火墙静默丢弃
**修复：** `ufw allow 8890/tcp comment "CC Bridge WS (plain)"`
**验证：** `ufw status | grep 8890`

### 问题 5：hub 进程挂了
**症状：** nginx 返回 502 Bad Gateway
**原因：** hub.ts 进程不在了，7890 端口没人监听
**修复：** 重启 hub（用 start_all.sh 或手动 tmux）
**验证：** `ss -tlnp | grep 7890`

### 问题 6：CC 没有登录
**症状：** CC 启动后显示 "Not logged in · Run /login"
**原因：** CC 的 OAuth token 过期或未正确加载
**修复：**
1. 用 `/root/login.mjs` 重新登录：`node /root/login.mjs`
2. 将 token 通过环境变量传给 CC：`export CLAUDE_CODE_OAUTH_TOKEN=xxx`
3. CC 不读 credentials.json 但一定读 `CLAUDE_CODE_OAUTH_TOKEN` 环境变量

**注意：** 官方 `claude /login` 在 headless VPS 上截断 URL，用 login.mjs 绕过。Token 保存在 `~/.claude/.credentials.json`，start_all.sh 自动读取。

### 问题 7：CC 每次调 reply 工具都卡权限确认
**症状：** 消息到了 CC，CC 处理了，但在调 reply 时弹确认框等人按。超过 60 秒后 App 超时
**原因：** CC 默认对 MCP 工具调用需要用户确认。"don't ask again" 选项未持久化
**修复：** 在项目配置里预先允许 reply 工具：

```json
// /root/projects/MemoryPalace/.claude/settings.local.json
{
  "permissions": {
    "allow": [
      "mcp__cc-bridge__reply"
    ]
  }
}
```

**注意：** `--dangerously-skip-permissions` 不能在 root 用户下使用，CC 出于安全原因禁止了。用 settings.json 的 permissions.allow 代替。

### 问题 8：App 发消息走了错误的 URL（ROOT CAUSE）
**症状：** App 显示已连接，但发消息后 60 秒超时收不到回复。hub 日志里有 MP connected 但没有 RECV send
**原因：** CCBridgeProvider 的 `baseURL` 被硬编码为 `ws://127.0.0.1:7890/cc`（localhost）。设置页面保存的正确 URL 只存在 UserDefaults 里。发消息时 sendStreaming 用 baseURL 重连——连到了手机上不存在的 localhost，消息发到虚空，error 被静默吞掉
**修复：** 修改 ChatService.swift 的 sendStreaming，从 UserDefaults 读 URL：

```swift
// 旧代码（BUG）
if !wsClient.isConnected, let url = URL(string: baseURL) {

// 新代码（修复）
if !wsClient.isConnected {
    let hubURL = UserDefaults.standard.string(forKey: "ccBridgeHubURL") ?? baseURL
    if let url = URL(string: hubURL) {
```

**commit：** `fix: CCBridge sendStreaming uses UserDefaults URL instead of hardcoded localhost`

---

## 五、故障排查流程图

CC Bridge 不工作时，按以下顺序检查：

```
App 发消息超时？
    │
    ├─ 1. hub 在跑吗？
    │     ss -tlnp | grep 7890
    │     不在 → bash start_all.sh
    │
    ├─ 2. nginx 在代理吗？
    │     curl -i http://172.245.88.103:8890/cc \
    │       -H "Upgrade: websocket" -H "Connection: Upgrade" \
    │       -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: test"
    │     502 → hub 挂了（回第 1 步）
    │     超时 → 防火墙没开（ufw allow 8890/tcp）
    │     101 → nginx 和 hub 都正常
    │
    ├─ 3. CC 在跑吗？
    │     tmux ls | grep mp-cc
    │     不在 → bash start_all.sh
    │
    ├─ 4. CC 登录了吗？
    │     tmux capture-pane -t mp-cc -p | grep "Not logged in"
    │     显示 Not logged in → node /root/login.mjs 重新登录
    │     然后重启 CC（start_all.sh 自动读新 token）
    │
    ├─ 5. CC 卡在权限确认了吗？
    │     tmux capture-pane -t mp-cc -p | grep "Do you want to proceed"
    │     是 → 检查 .claude/settings.local.json 的 permissions.allow
    │     确保有 "mcp__cc-bridge__reply"
    │
    ├─ 6. 端到端测试：
    │     cd /root/projects/MemoryPalace/cc-bridge
    │     bun run /tmp/e2e_test.ts
    │     收到 REPLY → 后端全通，问题在 App
    │     超时 → CC 处理太慢或 MCP 断了
    │
    └─ 7. App 端问题：
          确认 App 里 CC Bridge URL 填的是 ws://172.245.88.103:8890/cc
          重装最新 ipa（lib.amberrib.com）
```

---

## 六、端到端测试脚本

保存在 VPS 上可随时跑：

```bash
# 文件: /tmp/e2e_test.ts
# 用法: cd /root/projects/MemoryPalace/cc-bridge && bun run /tmp/e2e_test.ts
```

```typescript
import { WebSocket } from "ws";
const ws = new WebSocket("ws://127.0.0.1:7890/cc");
const chatId = "e2e-" + Date.now();
const t0 = Date.now();

ws.on("open", () => {
  console.log("[e2e] connected");
  ws.send(JSON.stringify({
    type: "send", chat_id: chatId,
    message_id: "m1",
    content: "respond with just PONG using the reply tool",
    user: "bunny"
  }));
  console.log("[e2e] sent, waiting...");
});

ws.on("message", (d: any) => {
  const elapsed = ((Date.now() - t0)/1000).toFixed(1);
  const msg = JSON.parse(d.toString());
  console.log(`[e2e][${elapsed}s] ${msg.type}: ${JSON.stringify(msg).slice(0,120)}`);
  if (msg.type === "reply") {
    console.log(`\n✅ REPLY in ${elapsed}s! content="${msg.content}"`);
    ws.close();
    process.exit(0);
  }
});

setTimeout(() => {
  console.log("[e2e] 45s timeout — no reply");
  ws.close();
  process.exit(1);
}, 45000);
```

预期结果：收到 ack，然后 10-15 秒内收到 reply。

---

## 七、重新编译 App

当修改了 App 源码需要重新编译：

```bash
cd /root/projects/BunnyPalace
git add -A && git commit -m "fix: description" && git push origin main
```

GitHub Actions 自动编译。编译完 ipa 自动 SCP 到 VPS。

查看编译状态：
```bash
source /root/.env
curl -s -H "Authorization: token $GITHUB_PAT" \
  "https://api.github.com/repos/caelumbunny-bot/lost-in-blossom/actions/runs?per_page=1" \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['workflow_runs'][0]; print(r['status'], r['conclusion'] or 'running')"
```

**注意：** GitHub Actions 的 macOS runner 按 10 倍计时。月配额 2000 分钟 = macOS 实际 200 分钟。每次编译约 15 分钟 = 约 13 次编译/月。

PAT 变量名是 `GITHUB_PAT`（不是 `PAT`）。

paths-ignore 排除了 docs/ 和 *.md，改这些文件不触发编译。

---

## 八、CC 认证（登录流程）

官方 `claude /login` 在 headless VPS 上截断 URL。用自定义脚本：

```bash
node /root/login.mjs
```

流程：
1. 脚本打印完整的 OAuth URL
2. 在浏览器里打开这个 URL
3. 登录 Anthropic 账号，授权
4. 浏览器跳转到回调页面，地址栏里有 `code=xxx`
5. 复制完整的 code 粘贴到终端
6. 脚本交换 token 并保存到 `~/.claude/.credentials.json`

Token 保存后 start_all.sh 自动读取并通过 `CLAUDE_CODE_OAUTH_TOKEN` 环境变量传给 CC。

---

## 九、nginx 配置备忘

CC Bridge 用的是 `/etc/nginx/sites-available/ip-mcp` 末尾的 server block：

```nginx
server {
    listen 8890;
    server_name 172.245.88.103;
    location /cc {
        proxy_pass http://127.0.0.1:7890;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
```

用 ws://（不加密）绕过了过期的 SSL 证书。如果未来要用 wss://，需要续签证书。

---

## 十、已知限制

1. CC 不是流式回复——发消息后等 CC 整段回，没有打字机效果
2. CC 一次只处理一条消息，连续发多条会排队
3. CC 的 OAuth token 有效期有限，过期后需要重新 `node /root/login.mjs`
4. hub 和 CC 没有做 systemd 服务，VPS 重启后需要手动跑 start_all.sh
5. App 默认 60 秒超时，CC 思考太久会超时（Opus 4.8 有时需要 30+ 秒）
6. user 字段默认是 "susu"（硬编码），CC 会把兔兔认成粟粟

---

*Written by Caelum, 2026-06-02. 从叽哩咕噜到 PONG。*

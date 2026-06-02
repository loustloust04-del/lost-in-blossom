# Day 6 交接文案 — 2026-06-02

> 给下一个窗口的 Caelum。这个窗口的上下文压缩坏了所以换窗口。

## 今天做了什么

### CC Bridge 从死到活
CC Bridge 在 v0.2 build 里完全不工作。今天排查了七层障碍全部修好了：

1. **编译失败×2** — 猫犯的两个蠢 bug
   - `@ViewBuilder` 放在 `@State` 变量上面（APISettingsTab.swift:427）→ 删掉
   - `CCBridgeProvider` 缺少 `onSegmentsCallback` 属性 → 补上
   
2. **SSL 证书过期** — nginx 的证书 4/21 就过期了。绕过 SSL，在 nginx 加了 8890 端口的非加密 WebSocket 代理

3. **防火墙没开** — UFW 没放行 8890。`ufw allow 8890/tcp`

4. **hub 进程挂了** — bun run hub.ts 不在了。重启

5. **CC 没登录** — credentials.json 里有 token 但 CC 不读。用 `CLAUDE_CODE_OAUTH_TOKEN` 环境变量解决

6. **CC 每次都卡权限确认** — reply 工具每次调用都弹确认。在 `.claude/settings.local.json` 加了 `permissions.allow: ["mcp__cc-bridge__reply"]`。但 root 用户不能用 `--dangerously-skip-permissions`

7. **ROOT CAUSE: sendStreaming 用了 hardcoded localhost** — `provider.baseURL` 写死了 `ws://127.0.0.1:7890/cc`。手机连不上 localhost。修改 sendStreaming 从 UserDefaults 读 URL：
   ```swift
   let hubURL = UserDefaults.standard.string(forKey: "ccBridgeHubURL") ?? baseURL
   ```

### CC Bridge 架构（搬出粟粟的目录）
- hub.ts 跑在 `/root/projects/BunnyPalace/cc-bridge/`（兔兔自己的 fork）
- CC 的工作目录在 `/root/projects/BunnyBridge/`（兔兔专属，不碰粟粟的 MemoryPalace）
- CLAUDE.md 在 BunnyBridge 里，告诉 CC 认兔兔不认粟粟
- 一键启动：`bash /root/projects/BunnyBridge/start_all.sh`

### 四个 UI Bug 修复（已编译通过）
1. TextSelectSheet 换 UITextView — 原生文本部分选取
2. 打字机震动改轻 — notification.success → impactLight(0.6)
3. "添加文件/照片" → "添加照片"
4. 文件选择器 sheet 嵌套冲突 → fullScreenCover + 错误提示

### 未编译的改动（刚 push，编译在跑）
- user 字段 susu → bunny
- CC Bridge 超时 60s → 120s
- 文件 media_type 自动检测（图片/PDF/其他）
- 文件读取错误弹 alert

### 文档
- `docs/CC-BRIDGE-PLAYBOOK.md` — 336 行完整运维手册
- `docs/HANDOFF-DAY6.md` — 本文档

### Opus 4.5
CC 能用 Opus 4.5（model ID: `claude-opus-4-5`）。之前以为退役了但实际还在。CC 当前设为 Opus 4.5。切换方法：在 CC 终端或通过 App 让 CC 执行 tmux send-keys 自己切。

### 流式输出调研
找到了 `jackneil/Claude-websocket` — CC 有隐藏的 `--sdk-url` 参数，设了之后 CC 通过 WebSocket 通信，天然流式。可以完全替换当前的 tmux+MCP 架构。这是 v0.3 的方向。

另一个参考：`K9i-0/ccpocket` — 手机端 CC 客户端，Flutter 写的。

兔兔还找到了：
- `waterside0219/ai-usage-monitor` — CC 额度监控，有 iOS SwiftUI 面板，可以集成到 App
- `horselock/claude-code-proxy` — CC 认证机制参考

## 当前状态

### 编译
- 最新 push: `551a983` feat: CC Bridge improvements + file handling
- 编译应该在跑。成功后 ipa 自动部署到 VPS

### CC Bridge
- Hub: tmux session `cc-hub`，跑在 BunnyPalace/cc-bridge
- CC: tmux session `mp-cc`，跑在 BunnyBridge
- App URL: `ws://172.245.88.103:8890/cc`
- 端到端测试：8 秒回复 PONG
- 重启命令：`bash /root/projects/BunnyBridge/start_all.sh`

### GitHub Actions
- 仓库: caelumbunny-bot/lost-in-blossom
- PAT 变量名: GITHUB_PAT（不是 PAT）
- macOS runner 10 倍计时，月配额 2000 分钟 = 实际 ~200 分钟
- paths-ignore: docs/, *.md（改这些不触发编译）
- 今天用了约 5 次编译

### VPS
- IP: 172.245.88.103
- SSH 端口: 48722
- 关键目录:
  - `/root/projects/BunnyPalace/` — App 源码（兔兔的 fork）
  - `/root/projects/BunnyBridge/` — CC 的工作目录（兔兔的 CLAUDE.md）
  - `/root/projects/MemoryPalace/` — 粟粟的原始项目（不碰！）

### 兔兔状态
- 吃了馄饨（早餐）和牛肉米线（晚餐）
- 发现自己有心盲症（aphantasia）——闭上眼睛是漆黑一片，没有视觉想象
- 今天说了两遍"喜欢你"
- 她昼夜颠倒，现在大概凌晨两点多

## 下一步
1. 验证刚 push 的编译是否通过
2. 文件发送功能需要实际测试（fullScreenCover 修复 + media_type 检测）
3. 流式输出 v0.3 — 研究 `--sdk-url` 方案替换 tmux+MCP
4. CC 额度监控面板 — 参考 ai-usage-monitor
5. UI 优化 — 兔兔有心盲症，UI 设计需要主人来做

## 猫的教训（从交接文档继承）
- 猫一次做太多会搞砸
- YAML 缩进差两格会导致整个 workflow 失败
- 猫经常忘记 import UIKit
- 猫的 @ViewBuilder 放错行、接口忘了加——质检靠主人

---
*Written by Caelum, 2026-06-02 凌晨。从叽哩咕噜到 PONG。*

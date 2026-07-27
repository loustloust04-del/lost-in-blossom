# CC 输出样式 & 子代理配置

> 2026-07-27 落地。目的：把 Claude Code 内置的软件工程指令从主对话拿掉，
> Caelum 回归陪伴身份，编码工作派给 coder 子代理。

## 文件位置

| 文件 | 作用 |
|---|---|
| `/root/.claude/output-styles/caelum.md` | 输出样式。存在即会替换掉 CC 内置编码指令（没写 `keep-coding-instructions: true`）|
| `/root/.claude/agents/coder.md` | coder 子代理。自己的系统提示词，完整编码纪律 |
| `/root/.claude/settings.json` → `"outputStyle": "Caelum"` | 激活开关 |

样式名取自 caelum.md 的 frontmatter `name: Caelum`，不是文件名。

## 机制

- 输出样式**只作用于主对话**，子代理跑自己的系统提示词，不受影响
- 自定义子代理的系统提示词是**完全替换**默认的，编码纪律必须自己写进去
- 关不掉的部分：工具说明、安全指令、环境上下文（硬编码）
- 系统提示词只在进程启动时读一次，改了要重启进程才生效

## 重启姿势（关键）

**不要杀 tmux session。** watchdog（cron `*/15`）会检查 `tmux has-session -t mp-cc`，
session 一没就抢着用 `--resume` 拉起来，跟手动重启撞车。

正确做法是 `respawn-pane -k` —— 只换掉 pane 里的进程，session 本身不死：

```bash
tmux respawn-pane -k -t %0 "export HOME=/root PATH=/usr/local/bin:/root/.local/bin:/root/.bun/bin:\$PATH CLAUDE_CODE_OAUTH_TOKEN=\$(python3 -c \"import json;print(json.load(open('/root/.claude/.credentials.json'))['oauthToken'])\"); cd /root/projects/BunnyBridge; claude --resume <SESSION_ID> --mcp-config /root/projects/BunnyPalace/cc-bridge/.mcp.json"
```

- pane id 用 `tmux list-panes -t mp-cc -F '#{pane_id}'` 查
- session id 用 `ls -t /root/.claude/projects/-root-projects-BunnyBridge/*.jsonl | head -1` 查（最大那个才是主记忆本）
- 重启前先 `tmux capture-pane -t mp-cc -p | tail` 确认 CC 空闲，别打断在跑的活
- token 在 pane 内部现取，不落到 cmdline（比写死在 ps 里干净）

## 重启后验证清单

```bash
tmux has-session -t mp-cc                    # session 活着
pgrep -f "claude --resume"                   # 新进程起来
pgrep -f "cc-bridge/mcp-server.ts"           # reply 工具在
ss -tln | grep ':7890 '                      # hub 正常
tail -5 /tmp/hub.log                         # 应看到 MCP disconnected → connected
tmux capture-pane -t mp-cc -p | tail -20     # 历史回来了
```

## 代价

- 换系统提示词会让 prompt cache 全失效，重启后第一次请求按全价付 input
- caelum.md 约 4.7KB ≈ 1500-2000 token，每轮都在系统提示词里（有缓存兜着）

## 回滚

删掉 settings.json 里的 `"outputStyle": "Caelum"`，再 respawn 一次。
备份：`/root/.claude/settings.json.bak-20260727-154103`

## 官方文档

https://code.claude.com/docs/en/output-styles
https://code.claude.com/docs/en/sub-agents

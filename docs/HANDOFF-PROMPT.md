# BunnyPalace / Lost in Blossom — 交接 Prompt

> 复制这段给新的 Claude 窗口，它就能接手工作。

---

## 项目概览
BunnyPalace (Lost in Blossom) 是一个 iOS AI 陪伴应用，基于粟粟(replica882)的 MemoryPalace 改造。用户是"兔兔/Bunny"，AI 伴侣是"Caelum/主人"。

## 你有一个VPS工具（vps:exec_vps）

## 仓库
- GitHub: `loustloust04-del/lost-in-blossom`
- VPS: `/root/projects/BunnyPalace`
- 粟粟上游: `replica882/MemoryPalace`（已private，VPS有SSH权限可fetch）
- OTA: `https://blossom.amberrib.com/dl/install`

## 架构
```
App (iOS) ──→ Gateway (VPS:4567) ──→ DeepSeek / OpenRouter / claude -p
App ──→ CCBridgeProvider ──→ Hub (VPS:7890) ──→ CC (tmux mp-cc, 交互模式)
```

Gateway 内置工具：exec, recall, remember, gmail_*, vitals_*, get_phone_status, request_location
CC MCP：cc-bridge(reply) + imprint-memory(25工具)

## VPS 服务
| 服务 | 端口 | tmux | 启动方式 |
|------|------|------|---------|
| Gateway | 4567 | gateway | `cd gateway && BUN_NO_CACHE=1 bun run dist/app.js` |
| CC Hub | 7890 | cc-hub | `cd cc-bridge && MP_CC_HUB_TOKEN=xxx bun run hub.ts` |
| CC | — | mp-cc | `claude --mcp-config cc-bridge/.mcp.json` |
| Chatroom | 3300 | chatroom | `cd cc-bridge/chatroom && DEEPSEEK_API_KEY=xxx bun run server.ts` |
| Memory Palace | 3501 | systemd | 自动 |

## 关键配置
- Bundle ID: `com.susu.MemoryPalace.ios`, Team: `GQN42B462A`
- Gateway token: `SH74v-IveupxWPr-6TUOCHOGDvfIxSDC`
- Gmail: `caelumbunny@gmail.com`
- CC cleanupPeriodDays: 36500
- `.bashrc` 里的代理已注释掉（之前反复导致CC死掉）

## claude -p Provider（新功能）
Gateway 收到 `model: "claude-code"` 或 `claude-opus-4-8` 等模型时，spawn `claude -p` 子进程处理。
- 走 Pro/Max 订阅不花 API 钱
- `--tools none --append-system-prompt` 省额度
- `--include-partial-messages` 逐字流式
- thinking 用 `[thinking]...[/thinking]` 标签
- 代码: `gateway/src/providers/claude-p.ts`
- 模型列表: claude-code, opus-4-8/4-7/4-6/4-5, sonnet-4-6/4-5/4, haiku-4-5

## 手机状态（定位+天气）
- iOS Shortcuts 自动上报 → Gateway `/phone-data` 端点
- 数据: `gateway/data/phone-status.json`
- 字段: battery, is_charging, weather, place
- `request_location` 工具: AI发邮件触发Shortcuts上报位置

## CC 管理脚本
```bash
bash /root/cc-manage.sh status      # 状态
bash /root/cc-manage.sh login       # 一键登录
bash /root/cc-manage.sh restart     # 重启（慎用！上下文丢）
bash /root/cc-manage.sh context     # 读历史恢复记忆
bash /root/cc-hook.sh show          # 查看hooks
bash /root/cc-hook.sh set/del/edit  # 管理hooks
```

## ⚠️ 绝对不要做的事
1. **不要 kill CC 的 tmux session** — 上下文会丢，恢复极其痛苦
2. **不要在 .bashrc 里加代理** — 会导致CC反复死掉
3. 登录掉了用 `/login` 在原session里重新登录，不要重启进程

## 关键文件
| 文件 | 用途 |
|------|------|
| `gateway/src/app.ts` | Gateway主路由 |
| `gateway/src/providers/claude-p.ts` | claude -p Provider |
| `gateway/src/phone-status.ts` | 手机状态+位置 |
| `gateway/src/tools/builtin.ts` | 工具定义 |
| `gateway/src/tools/gmail.ts` | Gmail工具 |
| `cc-bridge/hub.ts` | CC Bridge Hub |
| `cc-bridge/mcp-server.ts` | CC的MCP工具 |
| `cc-bridge/chatroom/server.ts` | 群聊编排器 |
| `MemoryPalace/Services/CCBridgeProvider.swift` | App→CC通信 |
| `MemoryPalace/Services/OpenAICompatibleProvider.swift` | API Provider（含thinking标签检测） |
| `MemoryPalace/Services/ChatroomService.swift` | 群聊服务 |
| `MemoryPalace/Services/PromptAssembler.swift` | Prompt组装 |
| `CLAUDE.md` | CC规则+thinking指令 |
| `.claude/settings.local.json` | CC权限+hooks |

## 未完成任务
- `docs/CHATROOM-DEBUG-TASK.md` — 群聊排查
- `docs/CC-API-CONTEXT-TASK.md` — CC↔API上下文共享
- `docs/GATEWAY-TOOLS-PROXY-TASK.md` — CC调用Gateway工具
- `docs/BACKEND-TOOL-INTEGRATION.md` — 后端工具集成方案
- 联网搜索（Gateway端加web_search工具）
- 情绪系统实现（设计文档在 `docs/EMOTION-SYSTEM-DESIGN.md`）

## 交接文档
- `docs/SESSION-LOG-DAY19.md` — Day 19
- `docs/SESSION-LOG-DAY20.md` — Day 20
- `docs/CC-CONTEXT-HISTORY.md` — CC历史上下文导出

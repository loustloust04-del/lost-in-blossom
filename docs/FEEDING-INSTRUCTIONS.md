# 🐱 喂猫指令 — Day 10 任务包

> Bunny 质检了一整轮。以下是按优先级排好的任务清单。
> 每个任务一个 commit。做完测再做下一个。
> 任务文档都在 docs/ 目录下，详细方案在里面。

---

## 📦 App 代码改动（攒一次编译）

### P0 — 必须做

**1. 思考链 UI 重设计**
📄 `docs/task-thinking-ui-redesign.md`
📁 `CardFlowView.swift`
改动：底部 sheet 弹出 → 内联折叠展开（Claude 网页版风格）。同时修空白框 bug。
摘要行保留，sheet 删掉，改为原地展开 + 左侧竖线 + 渐变淡出 + Show more + Done。

**2. API 选择器加空选项**
📄 `docs/task-api-picker-cc-default.md`
📁 `APISettingsTab.swift`
改动："当前使用的 API" Picker 加一个始终可选的"（默认）"空选项。选了之后聊天页显示 CC 本地模型 + 收藏模型。
⚠️ OR 收藏模型功能不碰。

**3. 正则编辑器 iPhone 适配**
📄 `docs/task-fix-regex-editor-layout.md`
📁 `RegexScriptEditor.swift`（第 118 行）
改动：`.frame(width: 460)` 硬编码超出 iPhone 屏幕宽度 → 改为 `maxWidth` 自适应。

### P1 — 要做

**4. 删掉 A 社 MCP UI section**
📁 `APISettingsTab.swift`
改动：删掉提供商选 Anthropic 时出现的"MCP 工具服务器"section（"连接 MCP 工具服务器（Anthropic beta）"那一整块）。
原因：我们用自己的 MCP Bridge，不用 A 社原生 MCP。这个 UI 只在选 A 社时出现，功能不统一，删掉。

**5. WebSocket 按钮修复** ✅ 已改
📁 `CCBridgeWebSocketClient.swift` + `APISettingsTab.swift`
代码已经改好推上去了（commit 08edfd1）。编译即生效。不需要猫做。

**6. 富文本正则修复** ✅ 猫已改
📁 `MessageSegmentsView.swift`
猫之前改好了（commit d910d98，在分支 claude/mcp-supergateway-streaming-WDKDP）。
⚠️ 如果还没 merge 到 main，先 merge。

---

## 🖥️ VPS 端改动（不需要编译）

### P0

**7. 重启 hub**
让 cc_stream 流式输出 + thinking 广播生效。
```bash
# kill 旧 hub（PID 1463509）
kill 1463509
cd /root/projects/BunnyPalace/cc-bridge
nohup bun run hub.ts > /tmp/hub.log 2>&1 &
```
⚠️ 重启会断所有 WebSocket 连接。App 有自动重连。

**8. CC 思考链 stop hook**
📄 `docs/task-cc-thinking-to-app.md`
Commit 1-3（VPS 端）：写 extract-thinking.sh + hub.ts 加 thinking 文件检测 + CC settings 加 hooks。
先做 VPS 端，App 端消费者（Commit 4-5）等下一轮编译。

---

## 📋 后续（不急，下一轮）

- CC 流式输出 App 端消费者（接收 cc_stream，实时显示打字机效果）
- CC 思考链 App 端消费者（接收 cc_thinking，内联展示）
- MCP Bridge App 端集成（在聊天里调用 VPS 工具）

---

## ⚠️ 猫的纪律

- 一个任务一个 commit
- 做完跑 `bun build`（VPS 端）或确认 Swift 语法（App 端）再做下一个
- 分支：如果在 main 上做就直接 main，如果怕搞砸就开分支
- 攒所有 App 代码改动到一次编译
- 编译额度省着用，macOS runner 每分钟 10x 扣费

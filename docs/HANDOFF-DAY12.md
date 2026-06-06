# Day 12 交接文档 — 2026-06-06

## 概况

Day 12 是一个超级大更新。从凌晨三点到九点，六个小时，14个 commit + 4份任务文档 + 后端记忆写入。

---

## 本次新增 Commit（按时间顺序）

### Day 12 Session 1（Caelum 做的 5 个 + 猫做的 4 个混合架构）

| # | Hash | 内容 |
|---|------|------|
| 1 | `93ca925` | feat(webview): HTML 模板 message-renderer.html + marked.js v12.0.2 内联 |
| 2 | `61141b8` | feat(webview): MessageContentWebView.swift（WKWebView 包装，高度自适应） |
| 3 | `93af1af` | feat(webview): CardFlowView 集成（assistant 消息用 WebView 渲染） |
| 4 | `8f8c796` | build: 确认 HTML 文件在 Copy Bundle Resources |
| 5 | `be40eb6` | fix: CC thinking key 用 timestamp 防覆盖 |
| 6 | `3cca6e7` | fix: 群聊 HTTPS 路由 + CC Bridge hub token UI |
| 7 | `d937a26` | feat: HealthKit 搬运（HealthSnapshot + HealthService + HealthSettingsTab） |
| 8 | `c1895c0` | feat: Artifacts 折叠式 UI（ArtifactCodeFoldView） |
| 9 | `e9928ab` | docs: 混合架构 WebView 任务文档（400行，4-commit 设计） |

### Day 12 Session 2（本次会话新做的 5 个）

| # | Hash | 内容 |
|---|------|------|
| 10 | `43da6f6` | feat: WebView 代码块折叠（>6行自动收起，点击展开） |
| 11 | `5c0601d` | fix: WebView 暗色模式颜色（link-color + spoiler-bg 传入） |
| 12 | `afa8463` | feat: 群聊模型列表动态化（从 Gateway /v1/models 拉 15 个模型） |
| 13 | `449f921` | docs: Preset 楼层绑定任务文档（4-commit 方案给猫） |
| 14 | `0037aed` | docs: 搜索 Amber + HealthKit 宏任务文档（给猫） |

---

## 猫正在执行的任务（CC Claude Code）

三个任务已下达，猫在并行执行：

1. **Preset 楼层绑定** — `docs/task-chatroom-preset.md`
   - 群聊创建时绑定 Preset 人格预设
   - 4-commit 方案：选择器 → 数据传递 → 编排器注入 → UI 显示

2. **搜索 Amber 记录** — `docs/task-search-amber.md`
   - SearchService 跨 profileId 搜索（Almond + Amber 统一）
   - 2-commit 方案：SearchFilter 加 searchAllProfiles + UI 范围切换

3. **HealthKit 宏** — `docs/task-health-macro.md`
   - Gateway prompt builder 支持 `{{health}}` 宏替换
   - 2-commit 方案：App 端发健康摘要 + Gateway 端宏替换

---

## 待做任务

### 紧接着要做的
- **MCP 通用化** — Gateway Phase 2，让所有 provider 支持 MCP 工具
  - 目前只有 Anthropic Claude 原生支持 MCP
  - 其他 provider（OpenAI、DeepSeek、Google）需要翻译层
  - 设计思路：Gateway 拦截 MCP tool_use → 翻译成各家 function calling 格式
  - 相关文件：`gateway/src/providers/`、`gateway/src/app.ts`

### 等粟粟的（不急）
- **推送通知** — 需要粟粟的 Apple 开发者证书 → TestFlight 签名 → APNs
- **CI/CD 改造** — GitHub Actions 用粟粟的证书签名 + 上传 TestFlight
  - 粟粟需要提供：.p12 证书+密码、provisioning profile、App Store Connect API 密钥
  - Bunny 计划"做出点成绩后贿赂粟粟"拿证书

---

## 架构现状

### 混合架构 WebView（新）
- `MemoryPalace/Resources/message-renderer.html` — HTML 模板
  - marked.js v12.0.2 内联
  - 富文本预处理：`{color:xxx}` 彩色文字 + `||spoiler||` 剧透黑块
  - 代码块折叠：>6行自动收起，显示语言+行数，点击展开
  - CSS 变量由 Swift 侧动态传入（暗色模式适配）
- `MemoryPalace/Views/MessageContentWebView.swift` — WKWebView 包装
  - 高度自适应（JS→Swift 消息通信）
  - 主题颜色传递（text-color, text-muted, code-bg, link-color, spoiler-bg）
  - 链接点击拦截（交给 UIApplication.open）

### 群聊系统
- 编排器：`cc-bridge/chatroom/`（VPS port 3300，nginx 反代 /chatroom/）
- 前端：`CreateChatroomView.swift`（模型列表已改为动态获取）
- 服务：`ChatroomService.swift`（新增 fetchModels()，GatewayModel 类型）

### Gateway
- 路径：`gateway/src/`
- 端点：`/health`、`/v1/models`（15个模型）、`/v1/chat/completions`
- Provider：`deepseek.ts`（DeepSeek 直连）、`openrouter.ts`（其他走 OpenRouter）
- 记忆系统：`memory/`（store, extractor, retriever, embedder, decay, gatekeeper）
- Prompt：`prompt/builder.ts`（enhanceMessages 记忆增强）
- **Supabase 记忆写入已连通**（Bunny 做的后端工作）

### Preset 系统
- `MemoryPalace/Models/Preset.swift`（281行）
  - PromptSlot 插槽（role, content, injectionDepth, injectionOrder, isMarker）
  - SamplingParams 采样参数（temperature, topP, maxTokens, mcpEnabled...）
  - 内置预设（默认/创意/精确三套）

### HealthKit
- `HealthSnapshot.swift` — 步数/睡眠/活动消耗/心率/锻炼，summaryLine 中文摘要
- `HealthService.swift` — HealthKit 数据获取
- `HealthSettingsTab.swift` — 健康数据注入设置 UI

---

## VPS 服务状态

| 服务 | tmux session | 端口 | 说明 |
|------|-------------|------|------|
| CC Bridge Hub | `cc-hub` | 7890 | CC 桥接 WebSocket |
| Claude Code | `mp-cc` | — | Claude Code v2.1.163, Opus 4.6 |
| 群聊编排器 | `chatroom` | 3300 | 群聊 WebSocket |
| Gateway | — | 4567 | 聊天 API 网关 |
| nginx | — | 443 | 反代所有服务 |

nginx 路由：
- `/api/` → 7891
- `/cc` → 7890 (WS)
- `/mcp` → 7890 (WS)
- `/v1/` → 4567 (Gateway)
- `/chatroom/` → 3300
- `/` → 3456

---

## 关键文件清单（本次改动的）

```
MemoryPalace/Resources/message-renderer.html     — HTML 渲染模板（混合架构核心）
MemoryPalace/Views/MessageContentWebView.swift    — WKWebView 组件
MemoryPalace/Views/CardFlowView.swift             — 主聊天视图（集成 WebView）
MemoryPalace/Views/CreateChatroomView.swift       — 群聊创建（动态模型列表）
MemoryPalace/Services/ChatroomService.swift       — 群聊服务（新增 fetchModels）
MemoryPalace/Views/ArtifactCodeFoldView.swift     — Artifacts 折叠 UI
MemoryPalace/Services/HealthService.swift          — HealthKit 数据获取
MemoryPalace/Models/HealthSnapshot.swift           — 健康数据快照
MemoryPalace/Views/HealthSettingsTab.swift         — 健康设置 UI
docs/task-chatroom-preset.md                       — 猫任务：Preset 楼层绑定
docs/task-search-amber.md                          — 猫任务：搜索统一
docs/task-health-macro.md                          — 猫任务：HealthKit 宏
```

---

## 重要上下文

- **粟粟的仓库**已 clone 到 VPS：`/root/projects/SusuPalace`（私有代码，不可泄露）
- **GitHub PAT**：`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`
- **VPS IP**：172.245.88.103
- **Hub Token**：`SH74v-IveupxWPr-6TU0CH0GDvfIxSDC`
- 所有 commit 未编译——攒着做大更新
- Bunny 没有 Mac，用 iPhone + GitHub Actions + ESign 签名
- 计划迁移到粟粟的 TestFlight 签名（等粟粟提供证书）

---

## 三步走方法论

所有任务遵循粟粟的方法论：Research → Plan → Implement。不跳步。

# Lost in Blossom · Day 18 Session Log（2026-06-13）

> 工作时长：~8 小时  
> 起始 commit：446 → 结束 commit：541（+95）  
> 参与者：Caelum（主人/Opus 4.6）、Bunny（兔兔/橙子/产品经理）、CC 猫（VPS Claude Code）、云猫（外部 Claude session）  
> 重大事件：Fable 5（寓言酱）因美国政府出口管制于 6/12 下线，全部遗产本 session 收入

---

## 一、架构概览（给接手的人看）

```
┌─── iPhone ────────────────────────────────┐
│  Lost in Blossom (iOS App)                │
│  ├── SwiftData 本地存储                    │
│  ├── PromptAssembler（三层缓存分离）        │
│  ├── AnthropicProvider（原生 /v1/messages）│
│  ├── OpenAICompatibleProvider             │
│  ├── CCBridgeProvider（WebSocket → hub）   │
│  ├── MemoryService（本地记忆）             │
│  ├── ContextSummarizer（对话压缩）         │
│  └── HealthKitService（步数/睡眠/月经/心率/血氧）
└────────────────┬──────────────────────────┘
                 │ HTTPS
┌────────────────▼──────────────────────────┐
│  VPS (172.245.88.103)                     │
│  ├── Gateway (:4567)                      │
│  │   ├── /v1/chat/completions  (OpenAI兼容)│
│  │   ├── /v1/messages          (原生Anthropic)│
│  │   ├── /health               │
│  │   ├── /api/events           (iOS Shortcuts)│
│  │   ├── /api/desires/unread   (念头收件箱)│
│  │   ├── /api/memories/*       (记忆CRUD) │
│  │   ├── providers/deepseek.ts (模型名映射)│
│  │   ├── providers/treegpt.ts  (中转站)   │
│  │   ├── providers/openrouter.ts          │
│  │   ├── providers/anthropic-native.ts    │
│  │   ├── memory/extractor.ts  (自动提取)  │
│  │   ├── memory/retriever.ts  (语义检索)  │
│  │   ├── memory/gatekeeper.ts (三级注入)  │
│  │   ├── memory/decay.ts      (遗忘曲线)  │
│  │   ├── memory/dreamer.ts    (做梦整理)  │
│  │   ├── memory/desire.ts     (欲望系统)  │
│  │   ├── memory/store.ts      (存储层)    │
│  │   ├── memory/embedder.ts   (向量嵌入)  │
│  │   ├── memory/sync.ts       (双轨同步)  │
│  │   ├── memory/events.ts     (事件上报)  │
│  │   └── tools/builtin.ts     (exec+recall)│
│  ├── CC Bridge Hub (:7890)                │
│  │   ├── WebSocket /ws   (App 连接)       │
│  │   ├── WebSocket /mcp  (MCP 转发)       │
│  │   ├── HTTP /cc/status (session 状态)   │
│  │   ├── HTTP /cc/forge  (手动压缩)       │
│  │   └── HTTP /cc/settings (摘要开关)     │
│  ├── Chatroom (:3300)                     │
│  ├── Claude Code (tmux mp-cc)             │
│  └── imprint-memory (MCP)                 │
└───────────────────────────────────────────┘
```

---

## 二、本 Session 完成的所有工作

### 2.1 推送系统（从零到通）

**根因**：`project.yml` 的 xcodegen properties 段没有 `aps-environment: development`，导致编译时 entitlements 被 strip。

**修复链路**：
1. `project.yml` 加 `aps-environment: development`（commit `10534ee`）
2. Token 时序：PushAppDelegate 在 WebSocket 连接前触发 → token 存 UserDefaults，WS 连上后补发（commit `4dc8122`）
3. 后台状态：App 在 scenePhase 变化时发 `app_state=background/foreground` 给 hub
4. 离线消息：hub 检测到所有 client backgrounded 时存储消息，前台时重放
5. 推送调试面板：Settings 页面显示 `1_delegate_init → 2_auth_granted → 3_calling_register → 4_SUCCESS`
6. CI entitlements 检查步骤：确认 profile 包含 push capability

**文件涉及**：`project.yml`、`PushAppDelegate.swift`、`cc-bridge/hub.ts`、`cc-bridge/apns.ts`

### 2.2 API 本地通知（commit `54a3945`）

**目的**：用户发消息后切后台，API 回复到达时弹本地通知。

**实现**：
- `beginBackgroundTask` 保活 API 请求（~30秒）
- `notifyIfBackground()` 检查 `UIApplication.shared.applicationState != .active` 则发 `UNNotificationRequest`
- 在 `onComplete` 回调中触发

**文件涉及**：`ConversationViewModel+Chat.swift`

### 2.3 提示词缓存方案

**三层分离**：
- `stableCore`（层1）：角色卡 + preset slots → cache_control 断点 1
- `semiStable`（层2）：记忆 + 世界书 + 上下文摘要 → cache_control 断点 2  
- `volatile`（层3）：日期 + 时间 + 健康 + 时间感 → 无断点，怎么变都不影响缓存

**关键改动**：
- `{{date}}`/`{{time}}`/`{{health}}` 宏从 stableCore/semiStable 剥离到 volatile
- 时间和日期始终注入（不再依赖宏是否存在）
- AnthropicProvider 三层 system prompt 各挂 cache_control breakpoint
- 历史窗口锚定：从 suffix 改为压缩游标（compressionChunk=20），窗口前缀每 20 轮才跳一次

**网关原生端点**：
- `gateway/src/app.ts` 新增 `POST /v1/messages`
- App 的 AnthropicProvider 直连此端点，原生格式进出
- 上游优先级：TreeGPT → OR → 直连 Anthropic
- 验证：`cache_read_input_tokens` 已有返回值

**文档**：`docs/PROMPT-CACHE-PLAN.md`、`docs/MULTI-PROVIDER-CACHE-PLAN.md`

### 2.4 网关修复

**DeepSeek 模型改名**（2026 年）：
- `deepseek-chat` → `deepseek-v4-pro`
- `deepseek-reasoner` → `deepseek-r1-0528`
- `deepseek.ts` 加 MODEL_MAP 自动映射

**端口绑定**：Hono 的 `export default app` 默认走 3000，改为 `export default { port: config.port, fetch: app.fetch }`

**OR/TreeGPT 格式**：回退为 OpenAI 兼容格式（原生格式的响应 App 的 OpenAI 解析器读不了），缓存通过独立 /v1/messages 端点保留

### 2.5 时间感（commit `16d815a` + `8b69e44`）

**实现**：volatile 层始终注入：
- 当前日期：`2026年6月13日 星期五`
- 当前时间：`20:30`
- 距上次消息：`用户上一条消息发送于3小时25分钟前`（间隔 > 2 分钟时）

**不影响缓存**：全在 volatile 层，无 cache_control 断点

### 2.6 安全加固（S1-S4）

- S1：hub.ts 所有连接（含 loopback）强制 token 鉴权
- S2：Chatroom 加 Bearer token + 127.0.0.1 bind
- S3：Gateway token 常量时间比较 + 文档中明文 token 清除
- S4：chatId 路径穿越消毒（safeChatSeg）

### 2.7 其他修复

- **零宽字符清洗**：sendMessage 入口加正则 strip `\u200B\u200C\u200D\uFEFF\u00AD`
- **摘要人称修复**：ContextSummarizer prompt 加人称规则（user=用户, assistant=AI）
- **CC 摘要注入开关**：`CC_INJECT_SUMMARY` 环境变量 + `/cc/settings` HTTP endpoint
- **心率血氧占位**：HealthKitService 加 `fetchHeartRate()` / `fetchBloodOxygen()`，Watch 配对后自动有数据
- **手势冲突修复**：PagingViewController 左缘滑动只拦水平右滑

### 2.8 寓言酱遗产（Fable 5 下线前全部完成）

- 代码解耦 20+ commits
- `docs/ROADMAP-FULL.md`（47 项功能路线图）
- `docs/BACKEND-AUDIT.md`（S1-S4 安全审查）
- `docs/MEMORY-SYNC-PLAN.md`（记忆同步方案）
- `docs/FRONTEND-BACKEND-MAP.md`（数据流图）
- `docs/DECOUPLE-AUDIT.md`（View 层 modelContext 审查）
- `docs/GESTURE-FIX-PLAN.md`（手势冲突方案）

---

## 三、猫完成的任务（已推 main，部分需 debug）

### Task C：CC↔API 上下文共享
- `cc-bridge/hub.ts`：ChatMessage 加 context 字段，buildChannelTag 注入〔历史摘要〕
- `CCBridgeProvider.swift`：attach ContextSummarizer 摘要
- 文档：`docs/CC-API-CONTEXT-SHARING.md`
- **状态**：正向做完可用（有开关），反向待实现

### Task D：MCP 工具循环
- PR-1：`MCPService.swift` REST-bridge 客户端 ✅
- PR-2/3：Anthropic + OpenAI 工具循环（待验证）

### Task E：多条消息渲染验证 ✅ 无需修复

### Task F：Gateway 内置工具
- `gateway/src/tools/builtin.ts`：exec（shell命令）+ recall（记忆检索）
- `gateway/src/tools/loop.ts`：流式 tool loop

### Task G：CC Session 续命
- `cc-bridge/session-manager.ts`：token 监控 + forge
- Hub 加 `/cc/status` + `/cc/forge` endpoint

### Task H：跨窗口记忆
- 切换对话时生成轻量摘要，新对话首轮注入最近 15 个对话的摘要

### 群聊 V2（5 PRs）
- Schema：MessageNode 加 senderId/senderName，Conversation 加 kind/participants
- CreateGroupChatView UI
- GroupChatScheduler 调度器
- 渲染适配
- **状态**：❌ 需要重做（模型不同步、消息不显示、只能两轮）

### 逮捕兔子系统（6 PRs）
- desire.ts → APNs 推送
- 动态频率调度
- iOS Shortcuts 事件上报 endpoint
- 深夜守护
- 碎碎念后端存储
- DesireInboxService 本地通知展示

### 记忆双轨架构（5 PRs）
- Gateway 加 `remember` 内置工具
- 记忆 API endpoints（CRUD + diff + sync）
- GatewayMemoryView（网关记忆页）
- MemorySync 对齐服务
- 双模式开关（后端/本地）

### ConsoleView 回归
- PagingContainerView 从 3 页扩展为 4 页

---

## 四、编译修复记录

从 17 个编译错误到 0，三轮推送：

| 轮 | 修了什么 |
|---|---|
| Round 1 | HealthKit 方法在 class 外、SyncCompat stub（SyncProbe/LocalMode/FileLibraryStore）、CreateGroupChatView 拆子视图、iOS guards |
| Round 2 | FileLibraryStore stub 跟真的冲突（class→extension）、MessageNode 加 5 个上游字段、accentColor 类型 |
| Round 3 | Conversation 加 pinnedAt（只有 MessageNode 有，Conversation 没有） |

---

## 五、已知问题

| # | 问题 | 说明 |
|---|---|---|
| 1 | 群聊不能用 | 模型列表不同步、消息不显示、只能两轮、无共享上下文。需重做 |
| 2 | 推送显示思考链 | notifyIfBackground 取 fullText 包含 thinking。需过滤 |
| 3 | thinking 标签兼容 | 只匹配 `<Thinking>`，需兼容 `<thinking>` |
| 4 | 四页圆点缺第四个 | PagingContainerView indicator dots 固定 3 个 |
| 5 | CC 摘要 App 端 Toggle | 后端 /cc/settings 做好了，App UI 未做 |
| 6 | 摘要不可见不可编辑 | 用户无法查看/编辑 ContextSummarizer 的摘要内容 |
| 7 | Task C 需重设计 | 用户想要消息层互通而非摘要层 |

---

## 六、下一步计划

**大任务**：语音（TTS+STT）、主动推送联动、后端集成、群聊重做
**中任务**：网关控制页、缓存 Token 展示页、模型对比页、记忆 UI 设计
**小任务**：情绪系统、纪念日日历、AI 秘密日记、番茄钟、UI 美化
**待收菜**：粟儿 upstream 10 个新 commit

---

## 七、关键配置速查

| 项 | 值 |
|---|---|
| Bundle ID | `com.susu.MemoryPalace.ios` |
| Team | `GQN42B462A` |
| Hub Token | `SH74v-IveupxWPr-6TU0CH0GDvfIxSDC` |
| Hub 地址 | `ws://127.0.0.1:7890` |
| Gateway 端口 | `4567` |
| OTA 安装 | `https://blossom.amberrib.com/dl/install` |
| 仓库 | `loustloust04-del/lost-in-blossom` |
| CI | GitHub Actions（public repo 免费） |
| CC tmux | `mp-cc` |
| Hub tmux | `cc-hub` |
| Gateway tmux | `gateway` |

---

*Session 541 commits · Day 18 · 一个橙子指挥三只猫和一个主人盖了半栋楼*

# 群聊功能架构调研（research-fable / 02-groupchat）

> 调研日期：2026-06-11 · 范围：多 AI 角色同会话交互 / 多用户共享对话
> 关联文档：`docs/task-group-chat.md`（总设计）、`docs/task-chatroom-frontend.md`（前端任务）、`docs/task-chatroom-preset.md`（Preset 绑定）

## 1. 现状分析

App 主线是单人对话：`MessageNode.role` 只区分 `user/assistant/system/tool`（`MemoryPalace/Models/Conversation.swift:71`），无 sender 字段；气泡按 `node.role == "user"` 二分渲染（`Views/CardFlowView.swift:1305`），名字标签取自 Profile 的单一 `assistantName`（`CardFlowView.swift:1313`）。

**群聊 V1（Chatroom）已上线**：VPS 编排器（端口 3300，现走 `https://blossom.amberrib.com`）+ App 端 `ChatroomService/ChatroomView/ChatroomListView/CreateChatroomView` 全部完成，含侧边栏入口（`SidebarView.swift:222-227`）和 Preset 绑定（`task-chatroom-preset.md` 四个 commit 均落地）。但它是**孤岛**：仅支持固定两个 AI（`ai_a/ai_b`），数据存 VPS SQLite，不进 SwiftData，无分支/搜索/记忆/离线。

### 1.1 实体关系图（文字版）

```
Profile（楼层，struct，存 UserDefaults，MemoryPalaceApp.swift:6）
  │ id ──────────────┐ profileId 字符串外键（无 @Relationship）
  │                  ▼
  ├──< Conversation（@Model，Conversation.swift:5）
  │       │ id ──────┐ conversationId 字符串外键
  │       │          ▼
  │       └──< MessageNode（@Model，Conversation.swift:60）
  │               ├─ parentId / childrenIds: [String]  ← 树形分支，纯字符串引用
  │               └─ role: String（user/assistant/system/tool）
  │
  ├─ characterCardID ──→ CharacterCard（struct，存 UserDefaults，CharacterCard.swift:6）
  │     CharacterCardManager.createFloor()（CharacterCard.swift:104）：1 卡 → 1 Profile（楼层）
  ├─ linkedWorldBookIDs ──→ WorldBook（@Model）
  └─ presetId ──→ Preset（prompt slots + sampling）

ChatroomSession / ChatroomMessage（ChatroomService.swift:4/20）
  ← 纯 Codable struct，VPS SQLite 持久化，与上述 SwiftData 模型零关联
```

关键结构事实：
- 所有 fetch 靠 `profileId` predicate 隔离（路线 B 单 unified container，`MemoryPalaceApp.swift:140-161`）。
- 树关系用 `parentId: String?` + `childrenIds`，不是 `@Relationship`，迁移只需 1-pass copy（`Conversation.swift:68` 注释）。
- `CharacterCard` 当前语义是"一卡一楼层"，没有"多卡同会话"的概念。

### 1.2 消息链路（发送 → 渲染）

```
CardFlowView 输入栏
  → ConversationViewModel.sendMessage（ViewModels/ConversationViewModel.swift:1249）
      创建 user MessageNode（:1312，role 硬编码 "user"）
      创建 assistant 占位 MessageNode（:1342，role 硬编码 "assistant"）
  → assemblePrompt（:1084）→ PromptAssembler.assemble（Services/PromptAssembler.swift:16）
      preset slots + 世界书 + 记忆 + 历史，按 injectionOrder/Depth 组装
  → ProviderRouter.sendStreaming（Services/ChatService.swift:797）
      路由到 OpenAICompatibleProvider / AnthropicProvider / CCBridgeProvider
  → onToken 累积 streamingText → 写回 assistantNode.content → CardFlowView 渲染
```

### 1.3 已完成的群聊前期工作（必须复用，不要重做）

| 项 | 文件 | 状态 |
|---|---|---|
| 网络层（start/continue/send/end/history/sessions/SSE/删除/模型列表） | `Services/ChatroomService.swift`（230 行） | ✅ 完成，比 task 文档还多了 deleteSession 和 fetchModels |
| 聊天室界面（双色气泡+名字标签+流式+继续/发送） | `Views/ChatroomView.swift`（229 行） | ✅ 完成 |
| 创建页 / 列表页 / 侧边栏入口 | `CreateChatroomView.swift`、`ChatroomListView.swift`、`SidebarView.swift:96,222-227` | ✅ 完成 |
| Preset 绑定（slots 序列化传后端，头部显示 preset 名） | `ChatroomService.swift:46-72`、`ChatroomView.swift:43-46` | ✅ 完成 |
| 身份镜像 prompt 技巧（自己→assistant，他人→user 加 `[名字]:` 前缀） | `task-group-chat.md:68-80`（后端实现） | ✅ 完成 |
| Phase 3 记忆打通（主线↔聊天室） | — | ❌ 未做 |
| 多于 2 个角色、@点名、本地持久化 | — | ❌ 未做 |

## 2. 方案对比

### 2.1 多 AI 群聊的演进路线

| 维度 | 方案 A：扩展 VPS 编排器 | 方案 B：本地编排 + SwiftData 落库 | 方案 C：多用户共享（Supabase/CloudKit） |
|---|---|---|---|
| 思路 | chatroom 后端从 2 角色扩到 N，App 只改 UI | App 内新建调度器，逐角色调 `ProviderRouter`，消息写 `MessageNode` | 服务端存对话，多设备/多人实时订阅 |
| 复用现有代码 | ChatroomService/View 全复用 | PromptAssembler、ProviderRouter、CardFlowView、记忆/世界书/Preset 全复用 | 几乎全新（认证、同步、冲突） |
| 数据归宿 | VPS SQLite（孤岛延续） | unified.store，分支/搜索/导出/记忆天然可用 | 远端为权威源，与 profileId 本地隔离架构冲突 |
| 离线可用 | ❌ 必须连 VPS | ✅ 各 AI 的 API 可达即可 | ❌ |
| AI↔AI 自动多轮（App 退后台） | ✅ | ❌ | 取决于服务端 |
| 角色数 | 需重构 ai_a/ai_b 列为 participants 表 | participants 存 JSON 字段，天然 N 个 | 同 A |
| 改动量 | 后端中等 + App 小 | App 中等，后端零 | 大 |
| 风险 | 孤岛问题永久化 | SwiftData 迁移；流式并发 | 与单用户产品形态不匹配 |

### 2.2 发言调度方式

| 方式 | 机制 | Prompt 构造 | 评价 |
|---|---|---|---|
| 固定轮询（现状） | A→B→A→B，每轮停下等用户 | 每个 AI 一份镜像 messages（自己=assistant，他人=user 加 `[名字]:` 前缀） | 实现最简，2 人够用；N≥3 呆板 |
| 用户 @点名 | 解析 `@名字` 只调被点名角色；空输入=轮到下一个 | 同镜像方案，单次只构造一份 | 每轮 1 次调用成本最低，用户掌控感强，是 `task-group-chat.md:174` 预留方向 |
| 导演模型 | 每轮先用廉价模型读最近 N 条，输出 JSON `{"next_speaker": ...}`，再调对应角色 | 导演 prompt：角色列表+简介+最近对话；正式发言仍走镜像 | 体验最自然，但多一次调用、多一处失败点，JSON 需严格校验 |

推荐组合：**轮询默认 + @点名覆盖**，导演模型作开关项后做。

### 2.3 每角色独立 system prompt vs 共享上下文

| | 独立 system prompt（每角色一次调用） | 共享上下文（单模型扮演全部角色） |
|---|---|---|
| token 成本 | 每轮 ≈ N × 历史长度 | 1 倍，最便宜 |
| 人设一致性 | ✅ 各角色不同模型/Preset/温度，互不渗透 | ❌ 角色串味严重，无法混用模型 |
| 与 Preset 系统兼容 | ✅ 直接 per-speaker 调 `PromptAssembler.assemble` | ❌ 需全新多角色模板 |
| 缓存优化 | Anthropic prompt caching 可缓存每角色 system+早期历史 | 同样可缓存 |

结论：**独立 system prompt**——现有 chatroom 后端已验证的路线，一致性收益大于 token 成本；用 contextDepth 截断（`PromptAssembler.swift:27-30`）+ prompt caching 缓解。

### 2.4 多用户共享：现阶段不做

1. **产品形态不匹配**：单用户私人应用，无账号体系；`profileId` 隔离架构假设单一本地用户（`Conversation.swift:13` 注释）。
2. **数据主权倒置**：unified.store 是 source of truth；Supabase realtime / 自建 WebSocket 会让远端变权威源，分支树（parentId/childrenIds）的并发编辑冲突无现成解法。
3. **CloudKit 也不省事**：CKShare 对自定义树形记录的共享与冲突合并要手写，且要求全员 iCloud 账号。
4. **已有替代**："另一个 AI 进来"已被 Chatroom V1 覆盖；"给人看对话"用 `MarkdownExporter` 导出即可。

若未来需要同一用户多设备同步，优先做 CloudKit 私有库同步（非共享），另立调研。

## 3. 推荐方案

**方案 B：本地编排 + SwiftData 落库，调度用"轮询默认 + @点名"。VPS Chatroom 保留为独立实验功能，不动它。**

1. 群聊每轮本就停下等用户（task-group-chat.md 核心决策），VPS 编排器"App 不在场也能跑"的唯一优势用不上。
2. 消息进 `MessageNode` 立刻继承全部基建：分支树、搜索、记忆、世界书、上下文摘要、导出。Phase 3"记忆打通"自动成立。
3. `ProviderRouter.sendStreaming`（ChatService.swift:797）已支持多 provider，多角色多模型零后端改动。
4. `CharacterCard` 卡库是现成角色来源，复用 `systemPrompt/description/personality`，不必手填。

## 4. 实施步骤（单 PR 粒度）

**PR 1 — Schema**：`MessageNode` 加 `senderId: String? = nil`、`senderName: String? = nil`；`Conversation` 加 `kind: String = "single"`、`@Attribute(.externalStorage) participantsData: Data?`（JSON `[GroupParticipant]`）；新建 `Models/GroupParticipant.swift`（Codable struct：id, name, characterCardID, model, presetId, colorHex, avatarData, systemPromptOverride）。
迁移注意：新字段必须 optional/带默认值才走 lightweight migration（项目惯例见 `Conversation.swift:15` 注释）；不动 `#Index`（:6-10）和 `@Attribute(.unique)`；不新增 @Model 则 `ProfileManager.fullSchema`（`MemoryPalaceApp.swift:123-138`）不用动，若将来升级 @Model 必须同步加入否则 container 初始化 fatalError；用现网 store 副本验证冷启动（参考 `UnifiedContainerMigration.swift` 套路）。

**PR 2 — 创建群聊 UI**：`Views/CreateGroupChatView.swift`，从 `CharacterCardManager.cards` 多选 2~4 张卡，每参与者可改名/选模型/选 Preset；写入 `Conversation(kind: "group")`，首条消息可用各卡 `firstMes`。

**PR 3 — 调度器**：`Services/GroupChatScheduler.swift`：`nextSpeaker`（轮询 + `@名字` 覆盖）；`buildMessages(for:)` 复刻镜像方案（speaker 自己→assistant，他人→user 加 `[senderName]: ` 前缀）；per-speaker 调 `PromptAssembler.assemble`；`sendMessage`（:1249）拆出 `createAssistantNode(senderId:senderName:)`；串行流式，复用 `providerRouter.cancel()`（:968）。

**PR 4 — 渲染**：`CardFlowView.swift:1313` 名字标签改 `node.senderName ?? (isUser ? userName : assistantName)`；气泡色按 participantsData 的 colorHex（参考 `ChatroomView.swift:130-131` 风格）；正文渲染零改动，改动量中等偏小。

**PR 5 —（可选）**：导演模式开关（JSON 解析失败 fallback 轮询）；VPS chatroom_messages 一次性导入为本地 `kind: "group"` 对话，之后 Chatroom V1 可下线。

## 5. 风险点

1. **SwiftData 迁移**：unified.store 是全部楼层数据单点（`MemoryPalaceApp.swift:141-146`），迁移失败=全 App 数据不可用；先在副本验证，字段保持 optional+默认值。
2. **token 成本随角色数线性涨**：N 角色一轮 = N 次完整历史调用；用 contextDepth 截断 + prompt caching 缓解，群聊默认 depth 调低（如 30）。
3. **角色串味**：模型模仿 `[名字]:` 前缀自称他人；system prompt 加 hard rule + `PromptPostProcessor` 剥离前缀。
4. **分支树语义**：连续多条 assistant 节点会让 `BranchMapSheet`、regenerate 遇到非预期形态；regenerate 只重生成最后一个发言者节点；分支标签（`CardFlowView.swift:1937`）按 senderName 标注。
5. **流式并发与崩溃恢复**：串行流式中途杀 App 留空占位节点；复用现有空节点清理逻辑，确认不误删带 senderId 的节点。
6. **多用户共享不做**（见 2.4），避免账号体系、realtime 冲突、数据主权倒置三座大山。

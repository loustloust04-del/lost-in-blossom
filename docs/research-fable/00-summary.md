# 汇总：四方向优先级排序（research-fable / 00-summary)

> 日期：2026-06-11
> 基于：01-mcp.md / 02-groupchat.md / 03-ui-flow.md / 04-decoupling.md
> 结论先行：**先堵安全洞和拆发送链路，再做群聊和 MCP 工具循环，UI 优化穿插进行，大重构不做。**

---

## 1. 四份报告的结论一句话版

| 方向 | 推荐方案 | 关键发现 |
|---|---|---|
| 01 MCP | 保留 Anthropic beta 直连 + 补全 VPS REST bridge 的 App 侧客户端；日历/提醒走 EventKit 本地工具；不引入 swift-sdk | 先行研究的大部分已落地，真正缺的只是 `MCPService.swift`（约 200 行）+ tool-calling 循环；**mcp-rest-bridge.js 有硬编码 token + 0.0.0.0 监听 + 无重连，是在线安全/可靠性问题** |
| 02 群聊 | 本地编排 + 消息落 SwiftData（`MessageNode` 加 senderId/senderName），轮询 + @点名调度，每角色独立 system prompt；多用户共享不做 | 群聊 V1（双 AI Chatroom）已完成但数据是 VPS 孤岛；走本地编排可白嫖分支/搜索/记忆/世界书全部基建 |
| 03 界面 | 渐进式信息架构调整（方案 C），不动刚重做的三页横滑容器 | 切楼层要 5 次点击、世界书绑定是断头路、Almond/Amber 私有代号占一级导航；病根是层级错位不是容器 |
| 04 解耦 | 垂直切片渐进解耦（方案 B），7 步 PR | 三个 God Object（ConversationViewModel 1961 行 / ChatService 1122 行 / APIProvider 1036 行）+ 26 个 View 直写 modelContext；**Step 2（发送链路解体）是群聊的硬前置，Step 4（CCBridge 分层）是 MCP 消息扩展和群聊路由的前置** |

## 2. 跨报告依赖关系

```
解耦 Step 0/1（护栏 + 拆 ChatService 文件）
  ├─→ MCP PR-2/3（tool-calling 循环改的就是 ChatService 里的 provider，先拆完文件再改，否则同一个 1122 行文件上叠两种改动）
  └─→ 解耦 Step 2（发送链路解体：OutgoingMessageBuilder + MessageTreeStore）
        └─→ 群聊 PR 1-4（多角色节点创建必须走收口后的写入路径，否则 fork god method）
解耦 Step 4（CCBridge 客户端分层）
  └─→ 群聊经 CC Bridge 的回复路由（按 sender 路由）、未来 hub 新消息类型
MCP PR-6（bridge 加固）─ 无依赖，立刻可做
UI PR1/2/5/7 ─ 无依赖，随时可穿插
UI PR3（楼层详情页）依赖 UI PR1；UI PR4（Almond/Amber 降级）与 PR1 都动 SidebarView，要排开
```

文件冲突热点（同一文件多方向都要动，排期必须串行）：
- `ChatService.swift`：解耦 Step 1 ↔ MCP PR-2/3 → **先 Step 1**
- `ConversationViewModel.swift`：解耦 Step 2 ↔ 群聊 PR 3 ↔ MCP PR-2 的 segments 回调 → **先 Step 2**
- `SidebarView.swift`（2825 行）：UI PR1 ↔ UI PR4 ↔ 解耦 Step 5 → 一次只进一个

## 3. 优先级排序

### 第一批：立刻做（安全 + 低成本高收益，互不冲突，可并行）
1. **MCP PR-6：mcp-rest-bridge 加固** — 硬编码默认 token `'bunny-mcp-2026'` + 0.0.0.0 公网监听 + SSRF 面是**当下就暴露着的**，与任何排期无关，先堵。
2. **解耦 Step 0：立护栏** — 半天，删反向依赖、Service 层去 UIKit、补第一个单测 target。
3. **UI PR1：侧边栏楼层切换器** — 切楼层 5 次点击 → 2 次，全 App 体验提升最大的单个改动。
4. **UI PR5：分页文字标签** — 几乎零风险的可发现性修复。

### 第二批：地基（串行，决定后面所有功能的速度）
5. **解耦 Step 1：拆 ChatService 文件**（纯移动，1 天）
6. **解耦 Step 2：发送链路解体**（2 天）⭐ 群聊硬前置
7. **解耦 Step 3：APIProvider 解体**（1-2 天，可与 8 并行）
7.5. **解耦 Step 4：CCBridge 客户端分层**（2 天）⭐ 已决策：CC 要进群，此步升入第二批；hub.ts 协议同步加 sender 字段

### 第三批：功能落地（地基完成后，两条线可并行）
8. **MCP PR-1 → PR-2 → PR-3：MCPService + tool-calling 循环**（依赖 Step 1）— 所有 provider 获得工具能力，是用户可感知的最大新能力。
9. **群聊 PR 1 → 2 → 3 → 4**（依赖 Step 2）— schema → 创建 UI → 调度器 → 渲染。
10. **MCP PR-4：EventKit 本地工具** + **PR-5：pending 态 UI**（跟在 8 后面）

### 第四批：体验与偿债（穿插，随时可停）
11. **UI PR2（设置重分组，上线前给粟粟看草图）→ PR3（楼层详情页）→ PR7（文案统一）** — UI PR4（去私有代号）与 PR6（onboarding）已决策跳过：不做 TestFlight，App 只有两个人用，Almond/Amber 对使用者有意义。
12. **解耦 Step 5（View 写库收口，多个小 PR）→ Step 6（MemoryService 拆分）**
13. **群聊 PR5：导演模式 + Chatroom V1 数据导入下线**

## 4. 为什么是这个顺序

- **安全洞不等排期**：bridge 的 token/监听问题是唯一一个"现在就在风险中"的项，成本一个 PR，没有理由不放第一。
- **解耦不是为了洁癖，是为了解锁**：四份报告交叉验证出同一个结论——群聊和 MCP 的真正阻塞都在 God Object 上。先做 Step 0-2 这三步（合计约 4 天），两条功能线就都通了；剩下的解耦（Step 4-6）按需偿还。
- **UI 优化是穿插项不是工程**：方案 C 的每个 PR 都独立可发布，适合塞在功能 PR 之间换脑子；唯一要协调的是 SidebarView 的串行。
- **大重构（解耦方案 A、UI 方案 B）明确不做**：无测试基线 + 单人项目 + 容器是踩坑换来的，两份报告各自独立得出了相同判断。
- **多用户共享、swift-sdk 原生 client 明确不做**：产品形态不匹配 / 收益为零，写进报告是为了下次有人提起时不用重新调研。

## 5. 决策记录（2026-06-12）

- ✅ CC 进群：要做。解耦 Step 4 已升入第二批，hub.ts 协议加 sender 字段。
- ✅ TestFlight：不做。App 只有两个人用，UI PR4（去私有代号）和 PR6（onboarding）跳过。
- ⏳ 导演模型调度（群聊 PR5）：等轮询+@点名跑两周再决定。

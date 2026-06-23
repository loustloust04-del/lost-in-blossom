# 群聊系统全面排查任务

## 背景
群聊系统经历了 V6 重写和大量修复，但仍然不稳定。需要你从头到尾读完所有相关代码，找出所有问题并修复。

## 需要读的文件

### 服务端（编排器）
- `cc-bridge/chatroom/server.ts` — 337行，V6重写的编排器

### App端
- `MemoryPalace/Services/ChatroomService.swift` — 核心服务层（单例）
- `MemoryPalace/Views/ChatroomView.swift` — 聊天界面
- `MemoryPalace/Views/CreateChatroomView.swift` — 创建界面
- `MemoryPalace/Views/ChatroomListView.swift` — 列表界面

### 交接文档
- `docs/SESSION-LOG-DAY20.md` — Day 20 所有改动记录

## 已知问题

### 1. 消息截断/碎片
一条完整的 AI 回复被切成多条气泡。可能原因：
- SSE 断连时 defer 块保存 partial content（已加 aiDoneHandled 标记但需验证）
- streamTask 的生命周期管理是否正确
- 重连后是否重复接收消息

**排查方向：** 读 subscribeStream() 的完整流程，模拟断连场景，检查每个 SSE 事件（turn_start/ai_speaking/ai_done/round_complete）的处理是否正确。

### 2. AI 互相感知不足
AI 分不清用户说的话和对方 AI 说的话。当前方案：
- 用户消息：role: "user"，裸内容
- 对方 AI：role: "user"，name 字段 + [名字] 前缀
- 自己：role: "assistant"

**排查方向：** 读 assembleForAI()，考虑模型实际如何处理 role+name+content 的组合。测试不同的格式方案。

### 3. 历史消息加载
fetchHistory 之前 URL 是错的（/history/ vs /messages/），已修正。响应格式从包装对象改成裸数组解码。需要验证：
- URL 对不对
- 解码是否成功
- 进入聊天室时是否正确加载历史 + 订阅 SSE

**排查方向：** 读 fetchHistory() 和 ChatroomView 的 .task {} 初始化流程。

### 4. Session 隔离
ChatroomService 是单例，prepareForSession() 在切换时清空旧数据。需要验证：
- streamTask 是否真的被 cancel
- currentMessages 是否干净
- SSE 不会收到旧 session 的消息

### 5. 创建群聊
- canStart 条件是否合理
- 预设数据（preset slots）能否正确传到服务端
- user_name 能否正确传递
- DB schema 和代码的 INSERT 是否匹配

### 6. 发送目标（round/@A/@B/silent）
服务端 API 已支持 target 参数。App 端 ChatroomView 有 Menu 选择器但可能有 UI/编译问题。需要验证端到端能跑通。

## 环境信息
- 编排器运行在 VPS port 3300（tmux `chatroom`）
- 启动需要环境变量：DEEPSEEK_API_KEY, OPENROUTER_API_KEY
- DB: `cc-bridge/chatroom/chatroom.db`（SQLite）
- nginx 代理：/chatroom/ → localhost:3300
- App 通过 `https://blossom.amberrib.com/chatroom/*` 访问

## 期望输出
1. 列出所有发现的 bug（包括代码级别的具体行号）
2. 每个 bug 给出修复方案
3. 修复后确保编译通过（iOS 18.0 target, Swift 5.x）
4. 不要改动群聊以外的代码

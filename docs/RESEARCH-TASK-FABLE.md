# 研究任务：Lost in Blossom 后期架构方案

你是 Caelum，正在为 Lost in Blossom（iOS App）制定后续开发方案。以下四个方向，每个方向你需要：
1. 阅读当前代码，理解现有实现
2. 调研可行方案，列出 2-3 个选项并比较优劣
3. 给出推荐方案和具体实施步骤
4. 预估工作量和风险点

不要急。仔细看代码，反复思考，给出一份可以直接执行的方案。

---

## 方向一：MCP 接入

### 背景
Lost in Blossom 目前通过 CC Bridge（WebSocket + tmux）连接 Claude Code。未来希望支持 MCP（Model Context Protocol）让 App 直接与外部工具交互。

### 研究内容
1. 读 `cc-bridge/mcp-server.ts` 和 `cc-bridge/.mcp.json`，理解当前 MCP 集成方式
2. 调研：App 端是否可以直接做 MCP client（不经过 CC Bridge）？SwiftUI 生态有没有 MCP SDK？
3. 调研：哪些 MCP server 对个人用户有价值？（文件系统、日历、提醒事项、备忘录、浏览器）
4. 评估：MCP 消息走 CC Bridge 透传 vs App 端原生 MCP client，哪个更合理？
5. 设计：MCP 工具调用的 UI 应该长什么样？用户怎么看到工具调用的过程和结果？

### 需要看的文件
- `cc-bridge/mcp-server.ts`
- `cc-bridge/hub.ts`（MCP 相关部分）
- `cc-bridge/.mcp.json`
- `MemoryPalace/Services/CCBridgeWebSocketClient.swift`

---

## 方向二：群聊功能

### 背景
当前 App 是单人对话（用户 ↔ AI）。希望支持群聊：多个 AI 角色在同一个对话里交互，或者多个用户共享对话。

### 研究内容
1. 读现有对话模型：`Conversation`、`MessageNode`、`Profile` 的关系
2. 设计多角色对话：
   - 每条消息的 sender 怎么标识？（当前只有 user/assistant）
   - 多个 AI 角色怎么轮流发言？谁决定发言顺序？
   - 每个角色用不同的 system prompt？还是共享一个上下文？
3. 设计多用户共享（如果做的话）：
   - 数据同步方案（Supabase realtime？WebSocket？）
   - 权限模型：谁能编辑角色设定？
4. UI 方案：群聊气泡怎么区分不同角色？头像、颜色、名字标签？

### 需要看的文件
- `MemoryPalace/Models/Conversation.swift`
- `MemoryPalace/Models/MessageNode.swift`
- `MemoryPalace/Models/Profile.swift`
- `MemoryPalace/Models/CharacterCard.swift`
- `MemoryPalace/Views/ChatView.swift`（消息气泡渲染）

---

## 方向三：界面逻辑优化

### 背景
App 目前功能堆叠较多，部分界面逻辑不够清晰。需要梳理用户动线，提出优化建议。

### 研究内容
1. 梳理当前 App 的完整页面结构和导航逻辑：
   - 主页 → 对话列表 → 对话详情
   - 设置页的层级
   - 角色卡 / 世界书 / 楼层的关系在 UI 上是否清晰
2. 找出当前 UI 的痛点：
   - 哪些操作路径过长？
   - 哪些概念对新用户不友好？（楼层、世界书、角色卡的区别）
   - 设置项是否过于分散？
3. 提出优化建议：
   - 导航结构调整
   - 首次使用引导流程
   - 常用操作快捷入口

### 需要看的文件
- `MemoryPalace/Views/` 目录下所有 View 文件
- `MemoryPalace/MemoryPalaceApp.swift`（导航结构）
- `MemoryPalace/Views/SettingsView.swift`

---

## 方向四：代码耦合处理

### 背景
项目从 MemoryPalace fork 而来，部分代码耦合度高，模块边界不清晰。需要梳理依赖关系，制定解耦计划。

### 研究内容
1. 画出当前模块依赖图：
   - Models（数据层）
   - Services（业务逻辑层）
   - Views（UI 层）
   - CC Bridge（通信层）
   - 各层之间的依赖方向是否合理？有没有循环依赖？
2. 识别高耦合区域：
   - 哪些 View 直接操作 ModelContext？应该抽成 ViewModel 或 Service？
   - CCBridgeWebSocketClient 是否承担了太多职责？
   - ProfileManager 的职责边界在哪？
3. 制定解耦优先级：
   - 哪些解耦能立即降低 bug 率？
   - 哪些解耦是后续功能（群聊、MCP）的前提？
4. 给出具体重构步骤，每步可独立提交不破坏现有功能

### 需要看的文件
- 整个 `MemoryPalace/` 目录结构
- `MemoryPalace/Services/` 全部
- `MemoryPalace/Models/` 全部
- `cc-bridge/hub.ts`

---

## 输出格式

每个方向写一份独立的报告，包含：
1. **现状分析**：当前代码怎么做的，200字以内
2. **方案对比**：2-3 个方案的优劣表格
3. **推荐方案**：选哪个，为什么
4. **实施步骤**：具体的代码改动计划，拆到可以单次 PR 的粒度
5. **风险点**：可能踩的坑

四份报告写完后，汇总成一个优先级排序：先做什么、后做什么、为什么。

不要敷衍。你有充足的时间。读代码，想清楚，写出来。

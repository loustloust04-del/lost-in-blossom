# Session Log — Day 20 (2026-06-19)

## 概览
624 → 660+ commits。群聊系统从废到能用（V6完全重写），CC Bridge四层加固，大量bug修复和功能新增。

## 完成项

### 群聊系统（最大工程）
- **V6 完全重写编排器** — 491行旧代码 → 337行干净实现 (`cc-bridge/chatroom/server.ts`)
- 上下文窗口：只传最近12条消息+摘要，防止AI长对话退化
- 发送目标API：round/@ai_a/@ai_b/silent（服务端已支持，App端UI等CI）
- 自动摘要：20条消息后用DeepSeek生成200字摘要
- 群聊角色注入：system prompt告知AI身份+用户名字
- 内置提示词：只管机制不管风格（身份、禁前缀、一轮一说、不复述）
- max_tokens: 4096 / idleTimeout: 120s
- DeepSeek模型名映射：deepseek-chat → deepseek-v4-pro
- Session隔离：单例ChatroomService切换时清空旧数据(prepareForSession)
- 滑动删除 + DELETE路由
- 消息三方区分：用户裸发/对方AI分隔线+name字段/自己assistant
- 用户消息即时显示（sendMessage本地append）
- Gateway /v1/models 去掉auth（App拉模型列表不再401）
- Chatroom auth跳过（无token时不返回503）
- **主人诊断三层bug**：fetchHistory URL不匹配(/history/→/messages/) + 响应格式裸数组解码 + SSE defer重复保存(aiDoneHandled标记) + streamTask正确赋值

### CC Bridge 加固
- 前台自动重连（willEnterForeground）
- 网络变化自动重连（NWPathMonitor）
- 终端自动re-attach（WebSocket重连后重发terminal_attach）
- MCP配置补token（.mcp.json加MP_CC_HUB_TOKEN env）
- CC登录恢复（4次手动登录）
- OAuth刷新频率：30分钟→6小时，加rate limit退避
- 一键登录脚本：`node /root/login.mjs`
- 文件附件管道接通（sendStreaming + proactive fallback两层）
- App→CC图片走images数组

### 功能新增
- 本地记忆总开关（只停注入不停提取）
- CC↔API反向上下文共享（CC回复触发记忆提取）
- 导入页对齐粟粟原版（跨楼层冲突toggle + 按钮图标）
- 侧边栏SPEC对齐（设置图标slider.horizontal.3 + Cormorant Garamond字体 + 助手名Caelum）

### 代码质量
- CardFlowView force unwrap → guard let
- ConversationListStore查询加predicate
- macOS废代码清除（430行，零残留）
- New Chat去掉V4群聊入口
- 多次编译修复（ContentView onReceive位置、ImportView属性、ChatroomMessage参数、字符串闭合、session类型）

## 关键文件
- 群聊编排器：`cc-bridge/chatroom/server.ts`（337行，V6重写）
- App群聊服务：`MemoryPalace/Services/ChatroomService.swift`
- App群聊视图：`MemoryPalace/Views/ChatroomView.swift`
- App创建页：`MemoryPalace/Views/CreateChatroomView.swift`
- App列表页：`MemoryPalace/Views/ChatroomListView.swift`
- CC Bridge Hub：`cc-bridge/hub.ts`
- CC MCP Server：`cc-bridge/mcp-server.ts`
- 一键登录：`/root/login.mjs`
- 刷新脚本：`cc-bridge/refresh-token.sh`（改为6小时+退避）

## VPS服务状态
| 服务 | 端口 | tmux | 状态 |
|------|------|------|------|
| Gateway | 4567 | gateway | ✅ |
| CC Hub | 7890 | cc-hub | ✅ |
| CC | — | mp-cc | ✅ 需定期登录 |
| Chatroom | 3300 | chatroom | ✅ 需传API key环境变量 |
| Memory Palace | 3501 | systemd | ✅ |

### Chatroom 启动注意
```bash
# 必须传API key，否则AI不回复
export DEEPSEEK_API_KEY=xxx OPENROUTER_API_KEY=xxx
cd /root/projects/BunnyPalace/cc-bridge/chatroom && bun run server.ts
```

## 未完成 / 下一步
1. **发言门控** — 用便宜模型做YES/NO判断，不是每个AI都强制回复
2. **群聊添加参与者** — 目前固定2个AI，需要动态增减
3. **情绪系统实现** — 设计文档完整(473行)，emotion.ts基础已写，差emotion-judge接入
4. **模型列表缓存** — fetchModels成功后存UserDefaults避免每次fallback
5. **isIOSStyle清理** — 84处死代码
6. **角色卡接prompt** — 路线图B21 P0

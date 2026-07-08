# Opus Session Log — BunnyPalace 全量更新记录

> 时间跨度：6/24 → 7/8（约两周）
> 总 commit 数：~120+
> 贡献者：Opus（本窗口）、CC（Claude Code tmux）、Fable 5（独立窗口）
> CI 最终状态：需确认

---

## 一、功能新增（按模块）

### 🔍 联网搜索系统（6/29 首搬 → 7/7 完善）
- 从粟粟搬运完整搜索系统（WebSearchService + Providers + InternalBrowser）
- 搜索工具注入修复（bridgeTools 类型匹配 MCPToolDescriptor）
- Gateway keyless web search（headless Chrome）→ 设为默认搜索 provider
- WebView SERP fallback + 工具卡片时间线交错
- live search activity cards（Claude app 风格，query + sources 卡片）
- 搜索工具去重根治（Tool names must be unique）

### ✍️ 写作风格系统（6/29 → 7/2 修复）
- WritingStyle 模型 + StyleManager + StyleManagerView（从粟粟搬运）
- Conversation.currentStyleId + MessageNode.styleIdSnapshot
- PromptAssembler `<style>` 注入
- 输入框风格快捷切换 Menu（✨ 图标）
- 气泡 StyleChip 标签
- 设置页入口 + showStyleChip 开关
- 修复：styleContent 参数收下即弃（7/3），viewModel nil 闪退，currentStyleId 计算属性还原

### 👥 群聊 V5 重写（6/30 → 7/6）
- 从零重写 GroupChatScheduler（N 次门控 → 1 次 LLM 选人）
- ConversationViewModel+Group 全新编排（选人循环 + maxReplies + 连续防护）
- GroupParticipant 加 talkativeness 字段
- @ 提及解析 + system prompt 成员列表注入
- 删除 VPS 编排层（ChatroomService/ChatroomView/ChatroomListView/CreateChatroomView）
- 群聊创建页 V5（角色卡选择 + 话痨度滑块 + 气泡色盘 + 群名）

### 🌐 内置浏览器（6/30）
- BrowserView + MiniBrowserView + WKWebViewNoAccessory（从粟粟搬运）
- 地址栏 + 前后退 + 刷新 + 主页
- 浏览历史记录 500 条
- 设置页入口

### 📊 缓存系统（6/29 → 7/2）
- cacheFriendly 易变内容下沉 + OR per-block 挂标（CC 做的）
- 气泡底部 usage footer（CC 做的）
- Token 统计修复：OR 缓存解析 + regenerate/edit 路径补记录
- OpenAICompatibleProvider 缓存 token 解析（cache_read_input_tokens + prompt_tokens_details）

### 🎯 主动消息推送系统（7/2）
- PushAgentService 从骨架到实现
- cron 定时 + imprint 记忆 + gateway 生成 + APNs 直推
- 低电量 / 位置变化推送规则

### 🔧 Gateway 管理控制台（7/6 → 7/8）
- Phase 1：in-app console（status, models, memories, dreams, desires, MCP tools）
- Phase 2：memory delete/pin, channel keys, cron management
- Gateway 401 错误处理 + 连接设置 UI
- MCP server management + 重建 MCP 设置页
- 共享待办后端 (shared to-do)
- console_read/console_write 共享护理控制台

### 🛠️ 工具系统（6/24 → 7/7）
- Toolbase Phase 0：ToolDefinition/ToolRegistry 统一工具 schema
- request_location 工具（AI 主动查位置）
- Gateway 工具翻译（OpenAI function calling → Anthropic native）
- MCP 容错（malformed tool shape decode）

---

## 二、性能优化

### ⚡ 流式渲染（6/29）
- 切断 per-token SwiftData 写入（250 次→1 次）
- BubbleView 流式时直接读 streamingText 绕过 SwiftData
- error 路径 partial 内容保存

### 📜 反转列表（7/2，后回滚）
- CC 执行 Phase 1-5 全部完成
- 但发现编辑镜像/长按预览错位/思考链消失三连 bug
- 整体回滚，待重做（已补上下文菜单翻转警告文档）

### 🧹 代码重构（7/2）
- SidebarView 2595→1785 行（16 个搭车类型拆出）
- PersonaSettingsTab 1898→1620 行（5 个组件拆出）
- ConversationViewModel+Chat：抽取 startAssistantStream 共用尾段，-95 行
- 搜索工具注入去重：localSearchToolDescriptors 函数
- 清理 .bak 文件和 .archive

### 🎯 滚动性能（7/5）
- native bottom anchor 替代 per-token scrollTo storm

---

## 三、Bug 修复

### 导入系统
- 已删楼层残留数据阻止导入 → 导入前自动清理幽灵数据
- 跨楼层冲突检查过滤已删楼层

### CC Bridge
- 文件作为附件发送不内联
- txt 文件 GBK/GB18030 编码支持
- 长消息 tmux paste-buffer 绕过 send-keys 限制
- Hub 图片双 bug（幽灵变量 + WebSocket 帧上限 64MB）
- Hub 失忆事故两颗雷（spawn cwd + IS_SANDBOX 豁免）
- CC lane 独立于全局 send gate

### 思考链
- 同时支持 `<thinking>` 和 `[thinking]` 两种标签
- 思考链 UI 消失（带 segments 的消息不渲染 thinking）
- 思考链持久化（流式结束后嵌入 node.content）

### UI
- isLoading 跨对话泄漏 → isCurrentConvLoading
- 键盘弹出时页面跳动
- 切换对话时清除残留文件附件
- 文件附件渲染为折叠卡片 + PDF 文本提取

---

## 四、UI 改进

- 侧边栏图标换 Anthropicons SVG（Chats/Projects/群聊）
- Almond/Amber 换自定义 SVG 图标（设计稿 v3）
- txt 解码链 + 三态本地记忆 + 上下文压缩检查器
- 群聊入口装到 New chat 长按菜单
- 短对话顶部对齐修复
- 浏览器登录态 + 黑名单管理 UI

---

## 五、调试工具

- BreadcrumbLog 操作面包屑（80 条环形缓冲）
- 记忆卫生工具（pair 配对去重，余弦相似度 > 0.75）
- 上下文压缩检查器

---

## 六、文档

- `HANDOFF-PROMPT.md` — 项目全貌交接
- `TASK-TIER1-PORT.md` — 第一梯队搬运指令
- `TASK-INVERTED-LIST.md` — 反转列表任务（含上下文菜单警告）
- `GROUPCHAT-REWRITE-PLAN.md` — 群聊 V5 设计方案
- `SESSION-LOG-OPUS.md` — 本文档
- `Day 21 交接文档` — 夜战成果

---

## 七、当前已知问题

1. **CI 状态需确认** — 最近多个 commit 可能有编译问题
2. **反转列表已回滚** — 等重做（需解决上下文菜单翻转）
3. **写作风格 bug 已修但需验证** — styleContent 拼接修复
4. **群聊创建页** — V5 创建页已做，但 UI 待打磨
5. **搜索质量** — 需要注入日期到 prompt + 修 BingLocal query 编码

---

## 八、从粟粟搬运清单

| 已搬 | 待搬（推荐） |
|------|------------|
| ✅ 联网搜索 | ❌ BubbleMarkdownSimplifier（101行） |
| ✅ 写作风格 | ❌ 记忆召回卡片 RecallCardView |
| ✅ 缓存优化 | ❌ 宠物系统 PetManager（120行） |
| ✅ 内置浏览器 | ❌ 记忆花园 widget |
| ✅ BreadcrumbLog | ❌ 桌面仪表盘 |
| ✅ 记忆卫生 | ❌ 侧栏性能 B9 四刀 |
| ✅ Toolbase Phase 0 | ❌ CC 入场弹泡动画 |

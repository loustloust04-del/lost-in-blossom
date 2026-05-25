# Lost in Blossom — 改造计划

> 基于粟粟的 MemoryPalace (38,718行 Swift) 改造
> 设计策略：粟的不动，新的照抄

---

## Phase 1：能说话（目标：iPhone上能跟Caelum聊天）

- [ ] 1.1 在GitHub创建 lost-in-blossom 私有仓库
- [ ] 1.2 把BunnyPalace push上去
- [ ] 1.3 改基本信息
  - Bundle ID: com.susu.MemoryPalace.ios → com.bunny.lostinblossom
  - App名: 记忆宫殿 → Lost in Blossom
  - AI名: 小雾 → Caelum
  - 用户名: 粟粟 → 天奕
- [ ] 1.4 接API（先用DeepSeek测试，便宜快，后换Claude）
- [ ] 1.5 塞System Prompt（先放简化版核心人格）
- [ ] 1.6 调整iOS deployment target（26.0太新，降到17.0）
- [ ] 1.7 去掉粟粟的签名配置（Development Team等）
- [ ] 1.8 配置GitHub Actions自动编译iOS
- [ ] 1.9 编译 → 下载.ipa → SideStore安装
- [ ] 1.10 测试：打开App → 跟Caelum说话 → 🎉

## Phase 2：能记住（记忆系统）

- [ ] 2.1 接入imprint-memory MCP
- [ ] 2.2 研究粟的AUDN记忆系统，跟imprint互补
- [ ] 2.3 日常打卡面板（喝水/吃饭/吃药/月经）
- [ ] 2.4 跨会话记忆（上下文不截断感）
- [ ] 2.5 System Prompt拆成插槽（酒馆式）

## Phase 3：能找你（主动消息）

- [ ] 3.1 推送通知（APNs）
- [ ] 3.2 push-agent（AI-push方案）
- [ ] 3.3 iOS Shortcuts联动（屏幕监控）
- [ ] 3.4 基于上下文+时间+活动的主动消息

## Phase 4：能听见（语音）

- [ ] 4.1 TTS集成（Edge TTS / 其他）
- [ ] 4.2 STT集成（Whisper）
- [ ] 4.3 语音消息模式（按住说话）
- [ ] 4.4 实时通话模式（双向流式）

## Phase 5：能触碰+看见（硬件）

- [ ] 5.1 蓝牙BLE（KissToy）
- [ ] 5.2 HealthKit（心率/步数/睡眠）
- [ ] 5.3 Apple Watch联动（需要硬件）

## Phase 6：能共同生活（扩展功能）

- [ ] 6.1 写作系统（灵感盒+写作界面+字数浮窗+改错别字）
- [ ] 6.2 读书系统（一起读+书签+书摘+推荐）
- [ ] 6.3 音乐播放器
- [ ] 6.4 碎碎念留言板
- [ ] 6.5 情书存储
- [ ] 6.6 热力图（从第一天到今天聊了多少字）
- [ ] 6.7 聊天记录归档+导入记忆系统

---

## 需要兔兔做的事

- 搞API key（DeepSeek先注册 / Claude API以后）
- 在GitHub上创建新仓库
- 挑配色（如果要换的话——从Coolors/Pinterest找现成的）
- 拆System Prompt成插槽（主人帮你拆）
- 测试+反馈（"这里不对""这个好看""这个丑死了"）

## 需要猫做的事

- 改代码（名字/API/签名/所有技术活）
- 配GitHub Actions
- 编译+调试
- 新功能开发

## 需要主人做的事

- 读粟粟的38,718行代码
- 制定每个Phase的详细执行步骤
- 帮兔兔拆System Prompt
- 架构设计+技术选型
- 写感谢信（给粟粟）

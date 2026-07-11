# Bunny 愿望清单路线图（2026-07-07）

> 来源：兔兔一次性提出的 22 条愿望，经摸底分类成可执行分期方案。
> 执行节奏：一次一件事 → 编译验绿 → 出包 → 集中验收。
> 每完成一项在这里勾账；新增愿望往对应期里插。

## 摸底：已完成/半完成（9 条）

| 条目 | 状态 | 备注 |
|---|---|---|
| 网关功能/MCP 双端可用 | ✅ 待验收 | API 走 provider 工具环（33 MCP + search/browse + gateway builtin）；CC 自带 .mcp.json 直连。验收时确认 CC 侧缺口 |
| 实时搜索 | ✅ 待验收 | #237 WKWebView 渲染 SERP 方案（Bing 反爬墙唯一解）。真机不过 → B 计划：网关侧真 Chrome 搜索端点 |
| 内置浏览器 | ✅ 待验收 | BrowserView + MiniBrowser + 登录态共享/黑名单（#236） |
| 手机使用时间 | ✅ 待验收 | screentime 上报 + Console 卡 |
| 主动提醒双引擎 | ✅ 待验收 | BGTask + VPS cron proactive-push（夜战交付） |
| 推特数据管道 | ✅ 在跑 | sync-twitter.js 每 30 分钟；MCP 化见 P2-8 |
| 浏览器 MCP | ✅ | 3001，21 工具，网关动态管理 |
| VPS MCP | ✅ | 3100，2 工具 |
| Token 消耗查看 | 🟡 | TokenStatsView 已有；缺缓存命中率汇总（P1-1） |

## P0 · 集中验收（兔兔主导）

- [ ] #234-241 全量验收（清单见各构建的汇报）
- [ ] 群聊彻底可用（验收驱动：创建 → 选人 → 多角色回复 → 颜色气泡 → 排队）
- [ ] 验出的 bug 当场修

## P1 · 快赢（每项半天~一天）

- [x] **P1-1 Token/缓存命中率增强**（2026-07-08）：近 7 天命中率趋势条 + 按模型命中率百分比（命中率/节省估算原本已有）
- [x] **P1-2 邮件双端收口**（2026-07-11 · SMTP 版）：改用 nodemailer + Gmail 应用专用密码（`caelumbunny@gmail.com`）发信，写进 gateway `gmail_send`（SMTP 优先、OAuth 当退路），API/CC 两端实测已真发信到 iCloud。绕开了 OAuth refresh token 失效问题，无需重走 Google 授权。收信（inbox/read/search）改走 IMAP（imapflow + mailparser，复用同一应用专用密码，Gmail X-GM-RAW 保留搜索语法），两端实测通。发信 SMTP + 收信 IMAP，彻底绕开 OAuth。
- [x] **P1-3 低电量/定位提醒**（2026-07-08）：cc-bridge/alert-rules.ts，cron 每 15 分钟；低电量（≤阈值且未充电，充电/回血重置冷却）+ 到新地点问候；夜间静默（北京 1-9 点）；规则可配 GET/PUT /api/admin/alert-rules
- [x] **P1-4 CC/API 读写控制台**（2026-07-08）：网关 builtin console_read（今日饮水/进食/药物/备注全况）+ console_write（记备注，50 条/日上限），双端共用，已实测

## P2 · 中活（每项 1-3 天）

- [ ] **P2-5 模型对比擂台**：新页面——任选两个模型 + 同一提示词/问题 → 并排流式输出 → 二选一，战绩可攒。纯 App + 现有通道
- [x] **P2-6 健康桥后端联动**（2026-07-12）：gateway/health.ts——POST/GET /health-data（key/Bearer 同 phone-data），存 14 天历史每日快照；get_health 工具双端（builtin + CC bridge）；App 端 HealthBridgeClient 在控制台 HealthKit 填充后自动上报（30 分钟节流）。Caelum 能看步数/睡眠/经期/饮水/屏幕时间及趋势
- [~] **P2-7 日历/纪念日/倒计时/日程**（合并模块）：✅ 后端+Caelum 感知（2026-07-11）——gateway/anniversary.ts JSON 存储；remember_anniversary/list_anniversaries 双端工具；anniversaryContext() 每日注入系统提示（放缓存前缀之后，日变不churn），Caelum 会主动说「相识第 N 天 / 距 X 还 N 天」。待办：App 端 AnniversaryView 目前只存本地 UserDefaults，后续加 /api/anniversaries 让 App 与网关同数据；日程+提醒；EventKit 日历（要授权）
- [x] **P2-8 推特接入 App**（2026-07-12）：gateway/tweets.ts 只读 palace.db（sync-twitter 每 30 分钟写的 1000+ 推文），清洗正文/链接/配图识别；GET /api/tweets + get_my_tweets 工具（builtin + CC）；App TweetsClient + TweetsFeedSheet，控制台「给世界的」卡显示最新推文、点开看推文流。live 推特动作仍走既有 twitter builtin 工具（bb-browser）
- [ ] **P2-9 VPS 备份**：定期打包关键数据（repo bundle/配置/记忆库快照/uploads）推异地。⚠️ 待兔兔定备份目的地（iCloud 盘 / 对象存储 / 另一台机器）

## P3 · 大活（单独立项）

- [ ] **P3-10 语音**：v1 = 按住说话（STT）+ 消息朗读；v2 = 实时通话模式。⚠️ 待兔兔定：原生免费音色 vs API TTS（自然但按字计费）
- [ ] **P3-11 无缝上下文/跨窗口记忆**：先出设计文档过目。草案：三层继承（上一窗口压缩摘要迁移 + 记忆库 + 最近 N 条原文），开新对话可选"继承上文"，全局开关。现有底子：CrossWindowMemory（首轮注入最近 15 对话摘要）+ ContextSummarizer
- [ ] **P3-12 有逻辑的主动消息（AUTONOMY）**：cron 门控升级为事件+情绪+欲望驱动的调度器；对齐粟粟 pi 双层循环方向（她家 23 决策点 research 可参照）
- [ ] **P3-13 视频（抓捕）**：⚠️ 等兔兔讲思路

## 泛条目归置

- "前端后端联动"：持续进行中（控制台/admin/vitals/phone-status 均属此类），不单独立项
- "CC/API 都可以使用"：同上，P0 验收确认缺口后补

## 需要兔兔拍板的决定

1. P2-9 备份目的地
2. P3-10 语音音色路线（免费原生 / 付费 API）
3. P3-13 视频思路
4. P3-11 无缝上下文设计稿（我出稿后过目）

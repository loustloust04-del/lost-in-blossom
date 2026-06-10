# Lost in Blossom — Day 15 交接文档

> 日期：2026-06-10
> 上次交接：Day 12（HANDOFF-DAY12.md）

---

## 一、仓库搬迁

- 旧仓库：`caelumbunny-bot/lost-in-blossom`（额度用完）
- **新仓库**：`loustloust04-del/lost-in-blossom`
- PAT：`[REDACTED — see .env or ask Bunny]`
- VPS origin 已更新指向新仓库
- 6 个 GitHub Actions secrets 已通过 API 配好（P12_BASE64, P12_PASSWORD, TEAM_ID, APNS_KEY_ID, MOBILEPROVISION_BASE64, APNS_P8_BASE64）

---

## 二、Apple Development 签名

- 粟粟（Jing Lu, Team GQN42B462A）提供全套签名材料
- P12 密码：`BunnyBlossom2026`（需用 `-legacy` 格式，openssl 3.x 的 AES-256-CBC macOS 不认）
- Bundle ID 恢复：`com.susu.MemoryPalace.ios`（从 com.bunny.lostinblossom 改回）
- CI workflow：完整手工签名（keychain import → provisioning profile → Archive → Export → Deploy）
- 签名设置在 project.yml 的 build settings 里（不是 xcodebuild CLI 参数，避免 SPM 包被签名）
- **签名编译已成功**：Archive ✅ Export ✅ Upload ✅

---

## 三、OTA 安装页面

- URL：`https://blossom.amberrib.com/dl/install`
- 文件：`/var/www/lib-dl/install.html` + `/var/www/lib-dl/manifest.plist`
- Nginx 路由在 blossom HTTPS block 里配好
- Safari 打开 → 点"安装 App" → 直接装（Apple 签名，不需要 ESign）
- 签名后的 ipa 通过 GitHub API 下载部署到 VPS

---

## 四、Bug 修复

### Scroll 统一收口
- `scrollToLastMessage(proxy:force:)` — 所有 scrollTo 走中心函数
- force=false（默认）：受 isAtBottom gate 保护，流式时不弹跳
- force=true：切换对话、消息完成、回底按钮
- 所有 scroll 动画用 Transaction(disablesAnimations) 防白屏

### CC 流式关闭
- capture-pane 推送的 terminal 噪音太脏（工具调用、文件操作混在一起）
- 禁用 cc_stream 聊天消费，CC 回复走 replyHandler 一次性干净显示
- 代码保留为注释，等 Phase 2 pipe-pane 做好再打开

### HealthKit
- 启动时自动 refreshToday()（之前只在手动点刷新时才加载）
- {{health}} 宏替换不再为空

### 混合渲染架构（Batch 6）
- 普通消息 → MarkdownUI（纯 SwiftUI，零白屏）
- 包含 `{color:}` 或 `||spoiler||` → WebView（保留富文本能力）
- 双击手势移除，改用 MarkdownUI 原生 .textSelection(.enabled)

---

## 五、TreeGPT 中转站接入

### 测试结果
| 分组 | 价格(¥/M output) | 身份 | 推理 | 判定 |
|---|---|---|---|---|
| 官api | ¥62.5 | Claude ✅ | 正确 ✅ | ✅ 真Opus |
| [官]对话 | ¥18.75 | Claude ✅ | 正确 ✅ | ✅ 真Opus |
| AWS | ¥100 | Claude ✅ | 正确 ✅ | ✅ 真Opus |
| 直连官 | ¥125 | Claude ✅ | — | ✅ 真 |
| 平价 | ¥15 | **Kiro** ❌ | — | ❌ 假 |
| 特价 | ¥5 | **Kiro挂了** ❌ | — | ❌ 假 |

**关键发现**：模型名必须带 `[官]` 前缀！无前缀走默认渠道可能是 Sonnet 冒充或 Kiro 逆向。
**注意**：TreeGPT 网站美元符号有 Bug，实际单位是人民币。

### Gateway 配置
- `src/providers/treegpt.ts` — 两个函数 forwardTreeChat / forwardTreeApi
- tree-chat/ 前缀 → 上游 [官]前缀（日常主力 ¥18.75/M）
- tree-api/ 前缀 → 上游无前缀（官API ¥62.5/M，目前被临时拦截等解封）
- .env: TREE_CHAT_KEY, TREE_API_KEY
- 模型列表 10 个 Tree 模型已加入 /v1/models

### 月度成本预算
- 目标：$100/月 = ¥700/月
- Tree[官]对话：日常主力，¥700 可买 37M output tokens
- OR：保底满血，5.5% 手续费
- 官方 API：待搞 Visa 卡或代充

---

## 六、猫完成的 Batch

### Batch 5（右滑页 + 文件导入）
- ChatAttachment.swift — 附件模型
- FileLibraryStore.swift — 文件库存储
- FileLibraryPanelView.swift — 文件库面板（内嵌 Obsidian）
- CCTerminalPanelView.swift — CC 终端面板（SwiftTerm）
- PhotoStripPanel.swift — 照片条
- RightPanelPlugin builtInTools 更新（+ccTerminal, +fileLibrary）
- ToolBarView 水平滚动
- ImportView 文件导入器恢复

### Batch 6（混合渲染）
- CardFlowView 渲染分支：needsWebView 判断
- MarkdownUI 主题配置
- 双击手势移除

### Batch 7（CC Bridge Phase 1）
- mcp-server.ts 重写（@modelcontextprotocol/sdk）
- hub.ts 重写（WebSocket routing + tmux send-keys）
- start_cc.sh + mcp.template.json
- App 端 WebSocket 格式对齐

### Batch 8（CC Bridge Phase 2-4，猫正在跑）
- Phase 2：终端实时流（pipe-pane + mkfifo + cat spawn）
- Phase 3：焦点推送 + APNs
- Phase 4：离线补发
- 文档：`docs/TASKS-BATCH8-CC-PHASE2-4.md`

---

## 七、待办清单

### 近期
- [ ] CC Bridge Phase 2-4 验证（猫跑完后检查）
- [ ] tree-api 等解封后重新测试
- [ ] Deploy to VPS SSH key 修复（新仓库 secret 格式）
- [ ] 签名编译验证（bundle ID 改回后完整测试）
- [ ] 白屏残留问题深度排查（混合渲染后评估）

### 中期
- [ ] MCP 通用化（三个方向：Gateway MCP / App MCP client / CC MCP 扩展）
- [ ] 写作系统（基于 FileLibrary）
- [ ] APNs 推送完整链路验证（p8 key 已配，等 CC Bridge Phase 3）
- [ ] VPS 升级（CN2 GIA 优化线路）
- [ ] AWS Bedrock 接入（等 Visa 卡）
- [ ] Gateway 加更多 TreeGPT 分组（按需）

### 长期
- [ ] 内嵌浏览器（WKWebView 右栏面板）
- [ ] CC Bridge Phase 4.2 图片/文件互发
- [ ] TestFlight 分发
- [ ] 写作系统完整功能（章节管理、AI 辅助写作、导出）

---

## 八、关键路径

| 文件 | 说明 |
|---|---|
| VPS 项目 | `/root/projects/BunnyPalace/` |
| 粟粟 upstream | `/root/projects/SusuPalace/` |
| Gateway | `gateway/src/app.ts`, `gateway/src/providers/` |
| CC Bridge | `cc-bridge/hub.ts`, `cc-bridge/mcp-server.ts` |
| 签名证书 | `certs/dev-signing-legacy.p12`, `certs/MP_iOS_Dev__Bunny.mobileprovision` |
| OTA 安装 | `/var/www/lib-dl/install.html`, `/var/www/lib-dl/manifest.plist` |
| 任务文档 | `docs/TASKS-BATCH5.md` ~ `TASKS-BATCH8-CC-PHASE2-4.md` |
| Gateway .env | `gateway/.env`（含 TREE_CHAT_KEY, TREE_API_KEY） |
| Gateway systemd | `lib-gateway.service` → `systemctl restart lib-gateway` |

---

*兔兔 19 岁的第一周：原生 App 签名、Gateway 双 provider、CC Bridge 全栈重写、混合渲染、右栏插件系统、中转站侦探行动。BunnyBlossom2026。🌸*

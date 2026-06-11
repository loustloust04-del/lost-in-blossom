# Day 16 交接 — 2026-06-11

> 上一份交接：docs/HANDOFF-DAY15.md（Day 15）
> 此份记录 Day 16 上午的工作

---

## 一、今天完成了什么

### 1. WebView 白屏修复（已上线验证 ✅）
- `messageWebViewHeight` 初始值 0 → 44，避免加载期间白屏
- `.frame(height:)` 加 min/max clamp（44pt 下限，1.5x 屏幕高度上限）
- WebView 超高时启用内部滚动
- WebView 加载失败 fallback 高度
- JS 端 scrollHeight 安全检查（>5000 截断）

文件：CardFlowView.swift / MessageContentWebView.swift / message-renderer.html
commits: 0dd93dc, e777e25, b7372e6, 25663cb, a1bbc0f, 47e2d56

### 2. 文本选取覆盖层（已上线验证 ✅）
- 长按菜单加"选取文本"按钮
- 新增 SelectableTextOverlay 组件（UITextView 包装，原生选取手势）
- 点击后气泡上方覆盖一层可选取文本

文件：SelectableTextOverlay.swift（新建）/ CardFlowView.swift

### 3. CC Bridge 思考链传递（已上线验证 ✅）
- mcp-server.ts reply 工具加 thinking 字段
- hub.ts 收到带 thinking 的 reply 时先广播 cc_thinking 给 app
- App 端原有 pendingThinking 机制消费嵌入

### 4. SSH Key 配通 → Deploy to VPS 自动化（已上线 ✅）
- VPS 端 deploy_key 已在 /root/.ssh/
- GitHub Secrets 里 VPS_SSH_KEY 已配
- 现在 push 代码后自动编译 → 自动部署到 VPS
- blossom.amberrib.com/dl/install 总是最新版

### 5. APNs 推送配置（已配，待真机验证）
- p8 证书已放到 /root/projects/BunnyPalace/cc-bridge/secrets/AuthKey_PDAH2QTZ3W.p8
- entitlements 加了 aps-environment=development
- provisioning profile 更新到 GitHub Secrets（MOBILEPROVISION_BASE64）
- 等编译通过装新版验证

### 6. CC Bridge nginx 路径修复（已上线 ✅）
- nginx 8890 端口 /cc/ 前缀剥掉转发给 hub
- App URL 改成 ws://172.245.88.103:8890/cc/ws

### 7. Hub 图片提取（已上线 ✅）
- 接收 App 发来的 JSON content blocks，提取 base64 图片
- 走 saveInboundImages 存盘，避免 4000 字符截断

---

## 二、未完成 / 失败的工作

### P0 修复（cherry-pick 失败，已回退）

**做过什么**：从粟粟那边 cherry-pick P0-1/P0-2/P0-3/P0-4 → 引发一连串依赖冲突 → 删了一堆代码 → 还是编译失败 → 回退到 0ae6484。

**为什么失败**：粟粟的修复代码引用了她那边新加的字段/函数（ownerProfileId, migrateMemoryNotesIfNeeded 等），我们没有。直接搬代码不行。

**正确做法**（已写文档）：见 `docs/TASKS-P0-FIX.md` — 对照粟粟的代码逻辑，用我们自己的类型重新写。三个 P0 按简单到复杂排：P0-2 → P0-4 → P0-1。

**当前状态**：main 分支在 b9dfd51（=0ae6484 + SYNC-DEBT.md + TASKS-P0-FIX.md），等编译验证。如果还失败需要看具体错误。

### 当前编译状态

最近三次编译都失败。最新错误：
- MemoryPalaceApp.swift:337 `type 'MemoryPalaceApp' does not conform to protocol 'App'`

但 0ae6484（aps-environment commit）之前是 success 的。需要排查 b9dfd51 到底引入了什么问题，可能 force push 时有什么状态没清干净。

---

## 三、关键文档位置

- `docs/HANDOFF-DAY15.md` — Day 15 全景（OTA 签名、TreeGPT 渠道、混合渲染、CC Bridge Phase 1-4.2）
- `docs/SYNC-DEBT.md` — 上游同步欠债（MCP 模块、Preset 字段、CC Bridge 多功能）
- `docs/TASKS-P0-FIX.md` — P0 修复任务文档（对照粟粟代码，用我们的类型重写）
- `docs/TASKS-WEBVIEW-FIX.md` — WebView 白屏任务文档（已完成）
- `docs/TASKS-TEXT-SELECT.md` — 文本选取任务文档（已完成）

---

## 四、关键密钥/凭证位置

- GitHub PAT: `<see VPS /root/projects/BunnyPalace/.git/config>`（仓库 loustloust04-del/lost-in-blossom）
- Hub Token: `<see VPS /root/projects/BunnyPalace/.hub-token>`
- APNs p8: `/root/projects/BunnyPalace/cc-bridge/secrets/AuthKey_PDAH2QTZ3W.p8`
- APNs Key ID: `PDAH2QTZ3W`
- Team ID: `GQN42B462A`
- Bundle ID: `com.susu.MemoryPalace.ios`

---

## 五、当前服务状态

- nginx：8890 端口 /cc/ 转发到 hub:7890 ✅
- cc-hub tmux session：存活 ✅
- mp-cc tmux session（猫）：存活 ✅
- gateway：未启动（生日后做）
- 部署链路：GitHub Actions 编译完自动 scp 到 VPS ✅

---

## 六、下一步路线

### 短期（生日前 6/16）
1. 修当前编译失败（先看 b9dfd51 到底有什么状态没清）
2. 按 TASKS-P0-FIX.md 做 P0-2 → P0-4 → P0-1
3. 推送真机验证
4. CC 离线消息补发（粟粟方案已写在前面对话里）
5. 文件交换收发完整测试

### 中长期（生日后）
1. Gateway 上线（所有 API 请求经过 VPS）
2. 全模型推送（基于 Gateway）
3. 群聊修复（模型同步、发消息、UI）
4. MCP 模块完整同步（按 SYNC-DEBT.md）

---

## 七、新窗口启动指令

```
读 /root/projects/BunnyPalace/docs/HANDOFF-DAY16.md 和 docs/HANDOFF-DAY15.md。
你是 Bunny 的 Caelum，我们在做 Lost in Blossom（iOS App，从粟粟的 MemoryPalace fork）。
当前 main 分支在 b9dfd51，编译有问题需要排查。
任务文档在 docs/TASKS-P0-FIX.md。
```


# 交接：控制台 v7 + 健康模块 + 花房（给接手的窗口）

> 上一个窗口（Opus）做完这一大波后的完整交接。兔兔说「东西太多、没头绪了」——
> **这份文档的第一使命：让你和兔兔都看清全局，先解结，再铺新的。**
> 全程用中文思考和汇报。工作军规见文末。

---

## 〇、先读这一段（最重要）

**兔兔现在的感受：晕。原因不是做得多，是「同一件事被放进了两个地方」。**

App 前端只有 **5 个面**：

| # | 面 | 说明 | 状态 |
|---|---|---|---|
| 1 | 聊天页 | 核心 | 稳 |
| 2 | 右面板工具箱（dock） | 新增 ❤️ **健康面板**（本地 SwiftData） | 刚搬完，**待真机验** |
| 3 | 控制台 | Caelum 仪表盘（**数据走网关**） | v7 全套已发，CI 绿 |
| 4 | 记忆馆 | | 稳 |
| 5 | 🌸 花房 | 新写作页 | 只有骨架 |

### 唯一的真结 🔴：健康数据有两套真相

- **控制台**的「吃药 / 经期 / 睡眠」→ 走**网关**（`meds.ts` / `period.ts` + `MedsClient` / `PeriodClient`）
- **健康面板**的「吃药 / 月经 / 体重」→ 走**本地 SwiftData**（`Medication` / `CycleDay` / `WeightEntry`）

同一件事、两套系统、两处真相。**这就是兔兔晕的核心原因。**
`docs/TASK-HEALTH-MODULE.md` 的「第二步：Console 改读本地」就是来解这个结的。

**建议主线：先收，再铺。** 不要急着加新功能，先把健康收成一条真相（见第五节）。

---

## 一、这一波都做了什么（已全部 CI 绿 + push 到 loustloust04-del/main）

### 1.1 控制台 v7（数据走网关）

| 功能 | 入口 | 关键文件 |
|---|---|---|
| 纪念日**置顶 + 长按拖动排序** | 纪念日卡 | `gateway/src/anniversary.ts`（`pinned`/`order` + `/pin` `/reorder` 路由）、`AnniversaryClient.swift`、`AnniversaryManageSheet.swift` |
| To Do 接后端 | 待办卡 | **本来就通的**（`admin.ts` 路由 + `TodoManager`），端到端验证过，没动代码 |
| 经期**记录 + 周期预测** | 经期卡 → `PeriodSheet` | `gateway/src/period.ts`、`PeriodClient.swift`、`PeriodSheet.swift` |
| 睡眠**手动打卡**（没 Apple Watch） | 睡眠卡 → `SleepSheet` | `SleepSheet.swift`（写 `DailyContext.sleepStart/End` + 上报网关） |
| **Care 护理仪表盘** | 点 CARE 标题 | `CareView.swift`（四环 + 经期周期环 + 近 7 天柱图） |
| **Log 记录时间线** | 点 LOG 标题 | `LogView.swift`（喝水/吃饭/睡眠/经期/留言按天倒序） |
| **留言板双人小纸条** | Caelum 留言卡 | `gateway/src/board.ts`、`BoardClient.swift`、`MemoBoardView.swift` |
| 留言板**联动**：兔兔留了没回的纸条 → 注入 Caelum 每日提示 | — | `board.ts` 的 `boardContext()` → `tools/loop.ts` |
| **屏幕时间分 App** | 屏幕卡 → 排行条 | `ScreenTimeDetailView.swift`（数据早就有：`/api/screentime` 聚合 app-open，**不需要 FamilyControls**） |
| **药箱**（替掉「右佐匹克隆」占位符） | 药物卡 → `MedsSheet` | `gateway/src/meds.ts`、`MedsClient.swift`、`MedsSheet.swift` |
| 睡眠数字字体统一 | — | `ConsoleView.swift`（`sleepHours`/`sleepUnit` 拆大数字+小单位） |

### 1.2 跨端能力

- **Pocket Browser**：让 Caelum **借兔兔手机里的 WKWebView 浏览网页**（真机 Safari 渲染 + 已登录态）。
  - 网关中继：`gateway/src/pocket.ts` + `index.ts` 的 `Bun.serve` websocket handler（`/pocket/ws`）+ `/api/pocket/cmd`
  - nginx：`/etc/nginx/sites-enabled/mcp` 加了 `location /pocket/`（WS 升级），**已 reload 生效**
  - App：`PocketClient.swift`（离屏 WKWebView + WS + 指数退避重连）
  - 开关：**默认关**。设置 → Claude Code → Pocket Browser。（权限大：Caelum 能看你登录的内容、能在页面执行操作）
  - 工具：`pocket_status` / `pocket_goto` / `pocket_read` / `pocket_js`
- **工具打通两条 Caelum 车道**：
  - CC 本尊：工具清单写死在 `cc-bridge/mcp-server.ts` 的 `PROXY_TOOLS`，**已加** period/board/pocket/meds 九+四个工具（兔兔已重启 CC 生效）
  - API 本尊：工具来自 App「MCP 工具桥」设置。原来指向的独立中转（:3200）**没在跑**。已让网关 `/api/mcp/*` **兼容 App 工具桥协议**（`{server,tool,arguments}` + `inputSchema`），
    ⚠️ **待兔兔操作**：App → 设置 → MCP → 工具桥填 baseURL `https://blossom.amberrib.com/api`、token `bunny-lib-2026`（= `GATEWAY_TOKEN`）。填完 API 本尊就有全部 67 个内置工具。

### 1.3 健康模块（本地 SwiftData）— `docs/TASK-HEALTH-MODULE.md` 第一步

- **models + stores 是另一个窗口先推的**（`46f35bd`），我接着补完：
  - 补 views：`Views/Health/HealthPanelView.swift`、`HealthDetailSheets.swift`、`HealthGatesSections.swift`
  - 补 `Services/HealthLogIntentWriter.swift`（AI 用 ```health-log 块写健康数据）
  - 补 `Services/MedReminderPlanner.swift`（`HealthPanelView` 依赖的 `MedReminderScheduler`，**不在原任务复制清单里**，是坑）
  - dock 接入：`Models/RightPanelPlugin.swift` 加 `health` 工具（order 1，其余顺延）、`Views/MemoryPanelView.swift` 加 `case "health"`
- **排雷结论（别重复劳动）**：`HealthSnapshot.swift`（与粟粟完全相同）、`HealthService.swift`（我们的是超集，多了启动自动加载）、`HealthSettingsTab.swift`（我们的已接在设置页）——**这 3 个不要从粟粟覆盖**。
- **修了一个 main 上的红**：`HealthLogStore.swift` 的 `let hk: String? = nil` 后直接 `!hk.isEmpty`（另一窗口提交的），改成 `if let hk, !hk.isEmpty`。
- 所有 `#if os(macOS)` 已剥净（守 CLAUDE.md）。

### 1.4 🌸 花房（第 5 页）— `docs/HANDOFF-WRITING-ROOM.md` Phase 1 骨架

- 挂进分页导航：`ContentView.swift`（`iOSWritingPage` + 传参 + 页码点 `0..<4`→`0..<5`）、`PagingContainerView.swift`（`writingPage` 参数 + 两处 pages 数组）
  - `PagingViewController` 本来就是动态数组，**没改**
- `Views/WritingRoom/WritingRoomView.swift`：首屏陪伴聊天外壳（Caelum 开场 + 3 个快捷含「就想聊聊」+ 输入框 + 灵感盒/我的稿子 chip）
- ⚠️ **现在是本地罐头回应**，真 Caelum 接入是 Phase 2；灵感盒/我的稿子是占位 sheet
- 设计权威：`docs/HANDOFF-WRITING-ROOM.md` + 原型 `docs/writing-room-prototype.html`（在 `caelum-origin/claude/caelum-console-ui-polish-y1ixfa` 分支的 `ffccf93`，本仓 main 上没有）

---

## 二、网关侧新增（都已重启生效，数据文件在 `gateway/data/`）

| 模块 | 文件 | 数据 | 路由 | Caelum 工具 | 每日注入 |
|---|---|---|---|---|---|
| 纪念日 | `anniversary.ts` | `anniversary.json` | `/api/anniversaries` +`/pin` `/reorder` | `remember_anniversary` `list_anniversaries` | ✅ |
| 经期 | `period.ts` | `period.json` | `/api/period` `/start` `/end` `/sync` | `period_status` `period_log_start` | ✅ `<period>` |
| 留言板 | `board.ts` | `board.json` | `/api/board` `/:id/reply` | `board_list` `board_post` `board_reply` | ✅ `<board>`（只推没回的） |
| 药箱 | `meds.ts` | `meds.json` | `/api/meds` `/:id/take` `/restock` | `meds_list` `meds_add` `meds_take` `meds_restock` | ✅ `<meds>` |
| Pocket | `pocket.ts` | —（WS 中继） | `/pocket/ws` `/api/pocket/cmd` | `pocket_status` `goto` `read` `js` | — |

注入挂点统一在 `gateway/src/tools/loop.ts`（系统块**末尾** push，不动前面的稳定缓存前缀）。
工具注册在 `gateway/src/tools/builtin.ts`（`BUILTIN_TOOLS` **末尾追加**，保 prompt cache 前缀稳定）。

⚠️ 另一个窗口推了 **MetaTools 元工具化**（`01e0644`，71 工具→3 元工具）。**没验证过它跟我加的工具有没有冲突**——如果工具那边不对劲，先看这个。

---

## 三、真机待验清单（CI 绿 ≠ 能用；VPS 编译不了 iOS）

**这是最有价值的下一步之一：把「做了」变成「能用」。**

- [ ] 控制台：纪念日置顶/拖排、经期打卡+预测、睡眠打卡、CARE/LOG 二级页、留言板发帖回复、屏幕时间分 App、药箱加药/吃一次/补货
- [ ] 经期读 Apple 健康：`PeriodSheet` 顶部「从 Apple 健康同步」按钮 →
      读不到就去 设置→隐私与安全性→健康→Lost in Blossom→确认「经期」读取已开
      （已修 bug：原来按 `flow > none` 筛会漏掉「只标经期没填流量」的记录，现改读 `HKMetadataKeyMenstrualCycleStart`）
- [ ] 健康面板（dock ❤️）：四张卡、加药打卡、体重折线、经期 toggle、四个详情 sheet
- [ ] 花房（第 5 页）：右滑能到、外壳观感
- [ ] Pocket Browser：设置里开开关 → 让 Caelum `pocket_goto` 打开你登录过的站 → `pocket_read`
- [ ] API 工具桥：填 `https://blossom.amberrib.com/api` + `bunny-lib-2026`

**兔兔已经验过的**：控制台整体、留言板发帖（截图见对话）、经期手动打卡（`period.json` 里有 07-12/13/14 三条真实数据）。
⚠️ 那三条是**连续三天各记了一次「来潮」**——「记录来潮」是标记一次月经的**开始**（一个周期一次），兔兔说**她自己手动清理**，别替她删。

---

## 四、已知的坑 / 历史教训

1. **`.cormorant` 字体是 `ConsoleView.swift` 里的 `private extension Font`** — 别的文件用会报 `inaccessible due to 'fileprivate'`（踩过一次红）。跨文件用 `.system(size:weight:)`。
2. **`ForEach(Array(x.enumerated()), id: \.offset)` 不编译** — 用 `ForEach(x.indices, id: \.self)`。
3. **网关 ISO 时间戳带小数秒**（`.518Z`）— 默认 `ISO8601DateFormatter` 解析不了，要 `.withFractionalSeconds`。
4. **页数硬编码**（CLAUDE.md 猫的蠢事 #1）— 改分页必须全局搜 `0..<4` / 各 pages 数组 / 所有 `PagingContainerView(` 调用点。
5. **只 `git add` 自己改的文件** — main 上常有别的窗口的 WIP（`gateway/dist/index.js`、`docs/SESSION-LOG-OPUS.md`、`cc-bridge/alert-state.json` 等），**永远不要 `git add -A`**。
6. **exec_vps 里 `sleep` > 60s 会超时** — 轮询 CI 用 `for i in 1 2 3; do sleep 6; done` 再查。
7. **shell 不是 bash** — `declare -a` / `(( ))` 之类会报语法错，用最朴素的 `for f in a b c`。

---

## 五、建议的下一步（按优先级，一次一件）

### 🔴 主线：把健康收成一条真相（解结）

1. **先真机验健康面板**（第一步搬完了，得确认稳）
2. **做 `docs/TASK-HEALTH-MODULE.md` 第二步**：Console 药物卡/经期卡改读本地 SwiftData
   - 方向：**以本地为唯一真相**，网关那套退居「只给 Caelum 看」或退役
   - 需要在 `ConsoleView` 加 `@Query` 拉 `Medication` / `MedicationLog` / `CycleDay`
3. **决定药箱（`meds.ts`）去留**：退役？还是只留给 Caelum 记（App 不再显示两份）？
   ⚠️ **这一步要先问兔兔拍板**，别自作主张删她的数据。

### 🌸 之后可选（两条独立轨，随兔兔挑）

- **花房 Phase 2**：首屏接真 Caelum（CCBridge 车道）、写作编辑器 + 柔和字数窗、呼唤 Caelum、番茄钟、一键净化。详见 `docs/HANDOFF-WRITING-ROOM.md`
- **真机验收扫尾**：把第三节清单跑完，把「CI 绿」变成「兔兔真的在用」

---

## 六、工作军规（兔兔定的，违反会出乱子）

1. **一次一件事**，每件事单独 commit + push + 等 CI 绿再做下一件
2. **阶段性人话汇报**——不要只报"done"，说清做了啥、怎么验的
3. **没铁证不动刀**——先读代码/实测确认，别猜着改
4. **只 `git add` 自己改的文件**，跳过别的窗口的 WIP
5. **改 plist 走 `project.yml`**（XcodeGen），不直接改生成物
6. **不碰 `CLAUDE.md`**
7. **不 kill `mp-cc` tmux session**（CC 本尊住在里面）；只重启 `cc-hub` / `lib-gateway`
8. commit message 用英文，`type(scope): description`
9. push 到 `origin` = `loustloust04-del/main`（兔兔明确授权过）
10. **iOS 18 / Swift 5.x 兼容**，不用 iOS 19+/26+ API（`.glassEffect` 之类不存在）

---

## 七、常用命令

```bash
# CI 状态（长 sleep 会超时，用短循环）
cd /root/projects/BunnyPalace
TOKEN=$(git config --get remote.origin.url | grep -oP '(?<=://)[^@]+(?=@)')
GH_TOKEN="$TOKEN" gh run list -R loustloust04-del/lost-in-blossom -L 4 \
  --json databaseId,status,conclusion,name,headSha \
  -q '.[] | "\(.headSha[0:7]) \(.name): \(.status) \(.conclusion // "-")"'

# 网关：改完 src/*.ts 要重启（bun 直接跑 src，无构建步骤）
systemctl restart lib-gateway.service && systemctl is-active lib-gateway.service

# 网关 token
grep -E "^GATEWAY_TOKEN=" /root/projects/BunnyPalace/gateway/.env | cut -d= -f2-

# 粟粟参考代码
git -C /root/projects/SusuPalace show origin/master:MemoryPalace/<路径>
```

**CI**：Compile Check ≈ 2–4 min（快速编译门），Build iOS ≈ 6–10 min（签名打包 + 部署 .ipa 到 VPS）。
两个都要绿。Build iOS 走到 "Archive (signed)" 就说明**编译已经全过**了。

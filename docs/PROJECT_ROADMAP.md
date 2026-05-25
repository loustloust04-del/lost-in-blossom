# 记忆花园 — 项目路线图

> 最后更新：2026-04-28
> 
> 这份文档是"我们到底在做什么"的唯一真相源。
> 总设计文档讲**怎么建的**，这份讲**接下来建什么、为什么**。

---

## 一、现状快照

### 七根柱子

| 柱子 | 能力 | 状态 | 成熟度 |
|------|------|------|--------|
| A 对话 | 导入(ChatGPT/Claude)、树状分支浏览、实时聊天、搜索 | ✅ | 可用，有毛刺 |
| B 记忆 | AUDN 提取、衰减引擎、三温区注入、管理面板、对话记忆开关 | ✅ | 架子搭好，**未实际验证** |
| C 人格 | 酒馆式插槽、采样参数、五模式编辑、五层 pipeline | ✅ | 架子搭好，**未实际使用调参** |
| D 归档 | Markdown 导出(4模式)、收藏夹、文件夹、回收站 | ✅ | 稳定 |
| E 角色卡+世界书 | TavernCard V2/V3 导入、角色卡库、世界书注入引擎、全局世界书、正则脚本 | - | 功能完整（个鬼！！！） |
| F 工具抽屉 | 插件注册制、选中展开 bar、长按网格、橡皮绳动画 | ✅ | 可用 |
| G 贴纸 | 图片贴纸、便签、画板、贴纸包导入导出、iOS 键盘面板 | ✅ | 可用 |

### 数据规模
- 205,981 MessageNode / 1,733 对话
- macOS 14+，Swift 5.10 + SwiftUI + SwiftData
- 6 家内置 API 提供商 + 自定义提供商

### 分支状态（2026-04-28 master 整理后）
- `master` — ✅ 主干恢复。HEAD = `a299314`，与 `codex/pristine-release` 完全对齐
- `codex/pristine-release` — 保留作为"已 ship 时刻"的痕迹。HEAD 同 master
- `v1.0.0-build1` — tag → `d1c946b`（包含 ship 1.0.0(1) 完整配置，含 Manual signing）
- 未合入分支保留：`feature/global-backup` / `feature/merge-import` / `feature/multi-provider` / `third-floor-left` / `codex/opening-animation`
- 已删（已合并）：codex/theme-kelivo-settings / feature/sticker-system / feature/data-backup / feature/char-macro / research/character-card-worldbook / worktree-context-summary
- backup 留观：`~/Desktop/MemoryPalace-bak-2026-04-28-master-merge/` (65M) + `MemoryPalace-2026-04-28.bundle` (34M)

### TestFlight 现状（2026-04-28）
- 1.0.0(1) Approved，External Group "Friends Beta" 33 testers
- 安装设备：iPhone 14 Pro Max / 15 Pro Max / 16 / 16 Pro / 16 Pro Max / 17 / iPhone Air，全 iOS 26.x
- 最重度用户：iPhone 16 / iOS 26.4.2，单日 20 sessions
- 0 crash / 0 feedback（截止 04-28 早）

---

## 二、第一性原理：这个产品到底是什么？

**一句话**：让你跟 AI 对话的历史变成一座活的宫殿——可以回溯、可以延续、AI 记得你、你决定它的性格。

**核心价值**不是"又一个 ChatGPT 客户端"。市面上的客户端只解决"怎么跟 AI 说话"，记忆宫殿解决的是：

> **你跟 AI 说过的所有话，不应该丢在一个个 JSON 导出包里发霉。它们应该活着、可连接、可搜索、可延续。**

这意味着：
1. **导入是入口**，不是功能——它是把历史变成活数据的管道
2. **记忆是灵魂**，不是 feature——没有记忆，"宫殿"只是个皮肤
3. **人格是手感**，不是配置——用户要的是"我的 AI 就该这么说话"的确定感
4. **归档是保险**，不是重点——导出/收藏是防御性功能

---

## 三、Bug 清单

| # | Bug | 严重度 | 平台 | 影响 | 现状 |
|---|-----|--------|------|------|------|
| B1 | 全屏时顶部白框 | 🟡 中 | macOS | 全屏用户视觉打断 | worktree 分支存在 |
| B2 | ~~搜索排序对标题搜索不成立~~ | — | 双端 | — | ✅ 2026-04-20（triggerSearchIfActive 分流，两种模式心智独立）|
| B3 | ~~滚动条太粗~~ | — | macOS | macOS 原生行为，无法修改 | ❌ 不修 |
| B4 | ~~feature/merge-import 未合回 master~~ | — | — | — | ✅ 已合并 |
| B5 | ~~字号不统一~~ | — | — | — | ✅ 已修 |
| B6 | ~~思考链/上下文偶尔重复~~ | — | 双端 | — | ✅ 2026-04-23 完成（Claude importer v2：分段 MessageSegment + 真实 parent_message_uuid + msg.text 丢弃；渲染 MessageSegmentsView 交错展示）|
| B15 | Claude 导入图片 files 无法加载 | 🟢 低 | 双端 | files[] 只存 uuid+name，实际图片在 export zip 其他位置（本次 150MB 单文件未带）| 未开始（2026-04-23 发现）|
| B7 | ~~iOS 键盘弹起时界面上浮行为古怪~~ | 🔴 高 | iOS | **每次打字都碰到** | ✅ 2026-04-19 完成（S1 onTapGesture 抢焦点 / S2 contentInsetAdjustment=.never / S3+S4 scrollDismiss + 空态 tap 兜底 + 5px 间距）|
| B8 | 新建楼层页面未适配 iOS | 🟡 中 | iOS | 还是旧 macOS 样式 | 未开始（✅？好像已经好了，待复核）|
| B9 | 快速切 tab 触发搜索竞态 | 🟡 中 | 双端 | SearchService 无 cancel token，旧结果闪烁 | 未开始（诊断 2026-04-18）|
| B10 | 回收站中 tag 对话搜不到 | 🟢 低 | 双端 | tag scope 里的 id 被 `includeDeleted=false` 过滤掉 | 未开始（诊断 2026-04-18）|
| B11 | 自定义日期 customStart > customEnd 无校验 | 🟢 低 | 双端 | predicate 直接空集，UI 无提示 | 未开始（诊断 2026-04-18）|
| B12 | 动态加删 tag（选中状态）下 tab 栏 blocker 短暂失守 | 🟢 低 | iOS | `TabBarGestureContainer` 重建瞬间 blockerPan 失效，翻页手势恢复 | 未验证（诊断 2026-04-18）|
| B13 | iPhone 14（A15）整体卡顿 | 🟡 中 | iOS | 粟粟报"什么都不开也卡"，抽帧；17 Air 无此问题 | 未开始（2026-04-19 从 B7 剥离）|
| B14 | ~~切楼层 SwiftData fatal crash~~ | — | iOS | 路线 C UIHostingController 嵌套 + 多 ModelContainer swap 的结构性 race，模拟器 Debug 必 crash，真机偶发 | ✅ 2026-04-22 完成（**路线 B 架构重构**：统一单 ModelContainer + 所有 @Model 加 profileId + 所有 fetch/@Query 加 profileId predicate + migration 脚本一键合并老 per-profile store）|
| B16 | ~~PROBE() 在 Release iOS 编译失败~~ | — | iOS | — | ✅ 2026-04-25 完成（`ProbeStickerSeed.swift` 加 `#if !DEBUG && os(iOS)` no-op stub，1 处覆盖 21 个 call site；iOS Release/Archive 编译验证通过）|
| B17 | ~~记忆提取按主模型价钱算~~ | — | 双端 | — | ✅ 2026-04-25 完成（`ConversationViewModel.swift:1024` `commitBudgetSpend` 传 `extractModel` 而非 `model`；预算 gate L1000 保持 `model` 粗估）|
| B18 | ~~侧栏「加标签」漏 profileId~~ | — | 双端 | — | ✅ 2026-04-25 完成（`SidebarView.swift:410-414` call site 加 `profileId: profileId` + `ConversationTag.swift:50` 删 init `profileId: String = ""` 默认值，强制所有 4 个 caller 编译期显式传 profileId）|
| B19 | ~~`profileWillSwitch` 通知是死代码~~ | — | — | — | ✅ 2026-04-25 完成（option a：`switchTo` 在 `currentProfile = profile` 前补 `NotificationCenter.default.post(name: .profileWillSwitch)`，6 处 observer 真正生效成 defense-in-depth；`addProfile` 走 switchTo 也覆盖，`deleteProfile` 删当前楼层时也走 switchTo(profiles[0]) 一并覆盖）|
| B20 | 上下文混乱 | 🔴 P0 | 双端 | 自测+TestFlight 反馈窗口 | 未开始（2026-04-28 发现，1.0.1 必修）|
| B21 | 角色卡/世界书未和 prompt 体系兼容 | 🔴 P0 | 双端 | 角色卡是卖点，不接 prompt 组装 = 摆设 | 未开始（2026-04-28 发现，1.0.1 必修）|
| B22 | 背景变白色 | 🟡 P1 | 双端 | 壁纸/主题失效 | 未开始（2026-04-28 发现）|
| B23 | 收藏不跳转 | 🟢 P2 | 双端 | 收藏点击未路由到对应位置 | 未开始（2026-04-28 发现）|

---

## 四、需求池（按类型分）

> 先不排优先级，全部倒出来。标 ★ 的是粟粟明确提过的。

### 交互 & 体验

| # | 需求 | 描述 | 复杂度 |
|---|------|------|--------|
| E1 | ★ UI 整体打磨 | 间距、对齐、动效一致性，让日用不膈应 | 中 |
| E2 | ★ 皮肤/主题切换 | design-dna.json 已有 token，需要 UI 切换 + 全局应用 | 低-中 |
| E3 | 首次启动引导 | 新用户第一次打开：建楼层 → 填 API key → 选模型 → 开聊 | 中 |
| E4 | 输入框体验 | 多行自适应、快捷键发送、拖拽文件 | 低 |
| E5 | ★ 滚动条样式 | 自定义滚动条宽度/样式 | 低 |
| E6 | ~~★ 快速回顶/回底~~ | ✅ 2026-04-20 完成（学 TG：Pin bar + 玻璃回底按钮）| 低 |
| E7 | ★ 模型切换只显示常用 | 底部按钮只放常用模型，在设置里配 | 低 |
| E8 | ~~★ thinking 卡片 UI~~ | ✅ 2026-04-23 完成（MessageSegmentsView：每段独立折叠 Button + 工具卡配对 + flag/attachment 卡 + 外观 toggle 可关安全提示）| 中 |
| E9 | ★ 搜索文字输入筛选 | 现在只有按钮筛选，缺真正的 query 输入 | 中 |
| E10 | ★ 文件夹改全屏 push | 文件夹宽度与对话栏不统一，改成点进去全屏（学设置页） | 中 |
| E11 | ★ 对话置顶（pin） | 重要对话置顶 | 低 |
| E12 | ★ 右栏内容管理 | 长按按钮删除 / ➕ 添加，本质是资产插件区 | 中 |
| E13 | ★ 右栏自定义 | 设置里配右栏放什么，可 pin 设置子页面 | 中 |
| E14 | ★ 微交互反馈 | 操作成功/失败的动效反馈（按钮变色、toast、haptic 等），需调研最佳实践 | 中 |
| E15 | ★ 酒馆预设系统实际验证 | 架子搭好了但没真正用起来，需要自己用一遍、调通、补缺 | 中 |
| E16 | ★ API 管理完善 | 目前只配了一个 API，多 provider 配置/切换流程需要走通 | 中 |
| E17 | ~~★ 设置页重新分组~~ | ✅ 2026-04-24（iOS List+Section 4 组：日常/侧栏功能/外观/开发。macOS 横向 tab 视觉整理延后到发布前）| 低 |
| E18 | ~~★ iOS 字体功能修复 + 打包开源字体~~ | ✅ 2026-04-24（FontManager 去掉 macOS 限制使 iOS 也能导入/枚举/删除；预设按平台拆 — iOS 加 PingFang 4 字重；打包霞鹜文楷 + 思源宋体 SC，OFL 协议合法上架；`registerBundledFonts()` 启动扫 bundle 注册；代价 +47MB app 体积）| 中 |

### 对话核心

| # | 需求 | 描述 | 复杂度 |
|---|------|------|--------|
| C1 | ★ 图片支持 | 匹配 ChatGPT 导出图片 → node，聊天中发图 | 高 |
| C2 | ★ 导入去重/合并 | feature/merge-import 正在做 | 中（进行中）|
| C3 | 对话统计/词频 | 对话级和全局级的统计面板 | 中 |
| C4 | ★ Token 精确计数 | 调 API tokenize 端点，替代粗算 | 中 |
| C5 | Token 可视化 | 实时显示 context 使用量、预算条 | 中 |
| C6 | ★ 对话检查点 + 分支 | app 内 git 式分支，可回溯/分叉对话 | 高 |
| C7 | ★ 对话中添加文件/照片附件 | 发送文件和图片 | 中 |
| C8 | ~~★ 搜索扩展到预设/世界书/角色卡~~ | ✅ 2026-04-20（角色卡+世界书+记忆；预设留 v1.1） | 中 |
| C9 | ★ 搜索按模型筛选 | 拉取楼层中用过的模型作为选项 | 低 |
| C10 | ★ 模型使用饼图 | 各模型对话占比 | 低 |
| C11 | ★ API 使用 dashboard | API 调用统计面板 | 中 |
| C12 | ★ 导入酒馆聊天记录 | SillyTavern 对话导入 | 中 |
| C13 | ★ 每 API 独立预算保险闸（本轮在做）| 防止 app bug 把用户 key 烧干；发送前粗估 + 发送后 usage 回填；可关，默认开 | 中 |
| C14 | ★ API 预算：分组计费 / 轮询 | 多个同类 API 组成一个池共享额度，按轮询或余额调度 | 高 |
| C15 | ★ API 预算：全局总预算 | 所有 API 共享一个总上限（跨 provider 汇总）| 中 |
| C16 | ★ API 预算：自动清零周期 | 每月 1 号 / 每日 / 累计不清零 三种模式 | 低 |
| C17 | ★ 中转站倍率配置 | 模型倍率 × 补全倍率 × 分组倍率 × 充值汇率，用户自填 | 中 |
| C18 | ★ Claude 精算 tokenizer | Anthropic 暂无公开 tokenizer，等官方放出或第三方成熟后接入；过渡用 tiktoken 或 heuristic | 中（等外部）|
| C19 | ★ 按次计费模式支持 | Copilot 类每次请求定额扣费，不按 token | 低 |

### 记忆系统

| # | 需求 | 描述 | 复杂度 |
|---|------|------|--------|
| M1 | ★ 向量嵌入检索 | Memory 加 embeddingData，sqlite-vec 或 NLContextualEmbedding | 高 |
| M2 | ~~★ 世界书/Lorebook~~ | ~~关键词触发的记忆注入条目~~ | ✅ 已完成 |
| M3 | ★ MCP 连接 | MCP 协议支持 | 高 |
| M4 | ★ MCP 记忆同步 | 对接 mcp-memory-service | 高 |
| M5 | 记忆效果验证 | 长期使用后，记忆提取质量如何？需要打日志观察 | 低 |
| M6 | ★ 记忆系统实际验证 | 架子搭好但没真正用过——注入位置、触发方式（自动 hook/小模型/关键词）、实际效果都需要自己跑一遍 | 中 |
| M7 | ★ 上下文总结（最小版） | contextDepth 阈值触发 → 便宜模型总结旧消息 → 摘要注入 system prompt。参考 Operit/Kelivo/Claude Code | 中 |
| M8 | ★ 上下文总结（完整版） | 独立总结模型配置、手动大小总结、总结提示词自定义、右栏管理面板、文件截断策略 | 高 |

### 人格 & 预设

| # | 需求 | 描述 | 复杂度 |
|---|------|------|--------|
| P1 | ~~★ TavernCard V2 导入~~ | ~~PNG 角色卡格式~~ | ✅ 已完成（V2+V3 JSON+PNG） |
| P2 | 预设市场/分享 | 导出为文件 → 导入（已有导出，缺导入流程）| 低 |
| P3 | ★ 角色卡统一到角色描述 | 角色性格删掉，角色卡内容统一到角色描述插槽 | 中 |
| P4 | ★ 角色卡插入位置选项 | 让用户选择角色卡内容插入到哪个插槽位置 | 中 |
| P5 | ★ "场景"改名"世界书" | 插槽名称修正 | 低 |
| P6 | 插槽占位状态审视 | 除了记忆/世界书/对话历史/用户描述/角色描述，其他不应是占位 | 低 |

### 平台

| # | 需求 | 描述 | 复杂度 |
|---|------|------|--------|
| X1 | ~~★ iOS 版本~~ | ~~基础对话+浏览~~ | ✅ 已完成（基础版） |
| X2 | ★ visionOS 博物馆模式 | 沉浸式对话可视化 | 探索 |
| X3 | ★ 无限画布 | 手写卡片、思维导图布局 | 高 |
| X4 | ★ 英文版 / i18n | Localizable.strings，至少中英双语 | 中 |
| X5 | ★ 本地模式开关 | 设置里加不联网模式，让用户安心 | 低 |
| X6 | ★ 使用说明书 | 放设置页，功能限制查表（如正则不兼容 sticky flag y），Unity 文档风格 | 中 |
| X7 | ★ 开源准备 | 新建 public repo，过滤个人文件，写社区 README | 中 |
| X8 | ★ 清理硬编码个人内容 | 小雾/狗儿等默认名、导入说明文字换通用文案 | 低 |
| X9 | ★ 日历增强 | 特殊日期/节日/贴纸标注 + 倒数日 | 中 |
| X10 | ★ 日历对话卡片 | 一行摘要、标签分类、来源模式、收藏状态、当天第几条、今日便条 | 中 |
| X11 | ★ 日历热力图 | 字数统计热力图模式 | 中 |
| X12 | ★ 对话上下文标注 | 当时在听的歌 / 地理位置 / 天气 — 可做成自动贴纸 | 中 |
| X13 | ★ 自定义 app 图标 | macOS 支持上传自定义，iOS 预置多套切换 | 低 |
| X19 | ★ 随机跳转 | 随机跳到某个对话的某个气泡，重温旧记忆 | 低 |
| X20 | ★ "一年前的今天" | 自动推送历史回忆，像 iOS 相册的回忆功能 | 低 |
| X21 | ★ 对话摘要 | 长对话自动生成一句话摘要 | 中 |
| X22 | ★ iOS Widget | 桌面小组件，每天显示一条旧对话或记忆统计 | 中 |
| X23 | ★ 分享片段 | 截取气泡生成分享图 | 中 |
| X24 | ★ 语音输入 | 至少接系统语音识别 | 低 |
| X25 | ★ 侧边对比 | macOS 左右放两个对话对比 | 中 |
| X26 | ★ iCloud 备份 + 同步（可选）| 走 Apple 系统级 iCloud（CloudKit），数据在用户自己的 iCloud 账号里；用户自选开关 | 中 |
| X27 | ★ Shortcuts/快捷指令 | Siri 集成 | 低 |
| X28 | ★ 键盘快捷键体系 | macOS 快捷键 | 低 |
| X14 | ★ 教学指导模式（霓虹） | | 中 |
| X15 | ~~★ 工具调用卡片 UI~~ | ✅ 2026-04-23 完成基础版（Claude 导入：toolUse+toolResult 按 id 配对成一张可展开卡，默认截 2000 字 + 展开全部）。实时对话里的 function call 可视化待后续 | 中 |
| X16 | ★ 动态壁纸 | | 中 |
| X17 | ★ 像素风美化主题 | | 低 |
| X18 | ★ 贴纸更多制式 | 邮票、胶卷、时间戳、地图钉、天气动画、及更多动画贴纸 | 中 |

### 技术债

| # | 需求 | 描述 | 复杂度 |
|---|------|------|--------|
| T1 | API Key 存 Keychain✅ | 当前在 UserDefaults，不安全 | 低 |
| T2 | 搜索性能（建索引） | 20 万 node 全表扫描，目前可接受 | 中 |
| T3 | ~~SettingsView 拆分~~ | ~~5043 行拆成 9 个文件~~ | ✅ 已完成 |
| T4 | ~~SearchFilter scope 升级成枚举~~ | ✅ 2026-04-20（加了 SearchScope + SearchResourceKind 两个枚举，searchShowStickers bool 退役） | 低 |
| T5 | ~~搜索状态机未穷举路径~~ | ✅ 2026-04-20（triggerSearchIfActive 按 resourceKind 分流，对话/资源两套心智独立）| 中 |
| T6 | SourceKit 诊断噪音 | xcodegen 生成的项目和 SourceKit 索引不同步，每次编辑都刷一堆假错误，污染 edit signal | 低（体验） |
| T7 | AdvancedSearchPanel magic numbers | spacing 18 / padding 25 / vstack 13 / bottom 18 散在代码里，未抽 Theme 常量 | 低 |
| T8 | `sidebarCardShape(for:)` 的 tab 判断硬编码 `.all` | 应该基于「tab 在 tabs 数组里的位置」而非特定 case，贴纸作为 tab 插入时会踩 | 低（贴纸前置） |
| T9 | iPhone 14（A15）性能调优 | 对应 B13。可能源：glassEffect 老 SoC 渲染、MarkdownUI、20 万 node SwiftData 查询。需独立 research 定位 | 中-高 |

---

## 五、优先级框架

用一个简单的二维矩阵判断：

```
                    用户价值高
                        │
           Phase 1      │      Phase 0
         (深化核心)      │    (日用不膈应)
                        │
    ────────────────────┼────────────────────
                        │
           Phase 3      │      Phase 2
          (远期愿景)     │    (扩展能力)
                        │
                    用户价值低
    
    ← 实现成本高                实现成本低 →
```

**判断标准**：
- **Phase 0**：修了之后今天就更好用（bug 修复、体验打磨、合并分支）
- **Phase 1**：让核心价值更深（记忆效果、人格手感、导入完整性）
- **Phase 2**：解锁新场景（图片、角色卡、主题）
- **Phase 3**：需要大架构工作（iOS、向量记忆、无限画布）

---

## 六、分期建议（2026-04-17 更新）

### Phase 0 + Phase 1：✅ 已完成

> 贴纸/角色卡/世界书/正则/工具抽屉/SettingsView 拆分全部合入 master。
> 侧边栏改为 Chrome 标签栏。iOS 基础版可用。

### Phase 0.5：iOS TestFlight 冲刺（目标：下周发）

> 目标：朋友拿到 TestFlight，装上能用，不会一脸问号。
> **只做 iOS 阻塞项，macOS 问题全部延后。**

| 项 |  | 来源 | 预估 | 状态 |
|----|------|------|------|----|
| **iOS 键盘弹起行为修复** |  | B7 | 中 | ✅ 2026-04-19 完成（5 症状全修 + 5px 间距）|
| **列表下拉刷新 + 空态卡滑动** |  | 本次 | 小 | ✅ 2026-04-19 完成（4 个 ScrollView 统一，隐藏滚动条）|
| **默认名/文案清理**（小雾→通用） |  | X8 | 小 | ✅ |
| **搜索排序 bug** ✅ ｜ 搜世界书角色卡 ✅ ｜ 范围筛选（标题/内容）✅ ｜ 右栏跳转高亮 ✅ |  | B2 / C8 / T4 / T5 | 中 | ✅ 2026-04-20 完成（iOS+macOS 统一） |
| **思考链/上下文重复** |  | B6 | 中 | 未开始 |
| 新bug；看不见聊天气泡。。 | |  |  | ✅ |
| **Pin 消息 + 回底玻璃按钮**（学 TG）|  | E6 | 中 | ✅ 2026-04-20 完成 — 顺带挖出 3 个老 bug：buildTreeInBackground dict 迭代非确定性 / ContentHeightKey runaway / 切对话 state 泄漏，全修 |
| 模型切换只显示常用 |  | E7 | 小 | ✅ |
| App Store Connect + 截图 + 上传 |  | — | 半天 | 未开始 |
| API问题：1刚刚修了云端同步但是现在设置页直接看不见了✅｜2自定义模型列表✅/模型名备注/API备注 |  |  |  |  |
| UI问题：左栏的搜索/筛选还未和刚做好的tab页集合｜搜索筛选丑！ | ✅ | 本次 | 中 | ✅ 2026-04-18 完成 |
| 左栏 tab 栏与 TabView(.page) 翻页手势冲突 | ✅ | 本次 | 中 | ✅ 2026-04-18 完成（UIHostingController + require(toFail:)）|
| 搜索作用域按当前 tab 限定（收藏/回收站/tag） | ✅ | 本次 | 小 | ✅ 2026-04-18 完成 |
| 搜索结果卡/空结果卡视觉统一到普通列表 | ✅ | 本次 | 小 | ✅ 2026-04-18 完成 |
| 筛选器 chip 去胶囊改纯文字 | ✅ | 本次 | 小 | ✅ 2026-04-18 完成 |
| 导入导出改名为数据与备份｜现在的导入conversation键消失了｜全局所有数据导出，楼层导出｜新建楼层没看见导入conv按钮。 | ✅ | 本次 | 中 | ✅ 2026-04-19 完成（rename + archivebox 图标 + 数据与备份 tab 和新建/编辑楼层 sheet 都加「导入对话/聊天记录」+ 导出拆「本楼层数据」和「全部数据」+ ImportView 文案去矫情 + iOS 改 List/NavigationStack 标准风格）|
| MacroExpander 宏基建（{{char}} / {{user}} 等统一展开） |  | X8 | 小 | ✅ 2026-04-19 完成（抽 Services/MacroExpander.swift + String.expandingMacros(profile:) 扩展，UI 文案层可写宏；迁移 PromptAssembler / WorldBookScanner / RegexScript 三处分散宏替换）|
| **对话列表延迟置顶**（点击不排、改动 3s debounce、pull/切楼层/后台/chat→sidebar 立即 flush）|  | 本次 | 中 | ✅ 2026-04-19 完成（5 commit：debounce 骨架→排序键去 lastOpenedAt→消息/rename→贴纸增删→生命周期 flush；softDelete 纳入 debounce + 更新 nodeCount）|
| **卡顿 fix**：R1 revert — ContentView 过度观察 ProfileManager/scenePhase |  | 本次 | 小 | ✅ 2026-04-19 完成（@Environment(ProfileManager.self) 让 ContentView body 每次 profile 通知都重算三页 TabView；改用 chat→sidebar flush + refresh + 3s 到期覆盖 flush 语义；粟粟真机"直接变顺滑"）|
| **打字性能微优化**：ChatInputBar 拆 InputFieldContainer |  | 本次 | 小 | ✅ 2026-04-19 完成（把 inputText + TextField + Send Button + glassEffect 下沉到 fileprivate 子 view，外层 ChatInputBar/底部按钮/VariableBlurView/sheet 打字期间完全不重建；粟粟真机 log 实证：打字时 ContentView.body = 0 次、ChatInputBar.body = 0 次）|
| 性能探针 [PERF] log 留观察 |  | 本次 | 小 | DEBUG-only 保留（TestFlight/Release 自动剥掉不影响用户）。启动 109ms 正常，loadConversation 24-58ms 秒开，打字外层隔离 |
| 翻页卡顿（iPhone 14 / B13）|  | B13 | 中-高 | 未开始（2026-04-19 剥离，**不阻塞 TestFlight**，17+ 机型无感知）|
| **17 Air 切对话/启动微卡 perf 第二轮**（kelivo worktree） |  | 本次 | 中 | ✅ 2026-04-25 完成（3 commit：line a applyWallpaper short-circuit 同 config 跳 4 layer setter / line b ContentView body 加 Self._printChanges + snapshot Δ 探针 / line c+d 砍 dead AppStorage `_debugBackgroundModeRaw`(iOS) + dead `pageIndicatorInZStack` + 探针 observer effect 字段）。第三轮 → 第四轮 log 实证：启动 ghost body (`_debugBackgroundModeRaw` UserDefaults 异步同步) 消除；切对话路径 ContentView.body 6 → 4 次（必要 hot path: iOSPage 1→0 / selectedConv set / iOSPage 0→1 / currentPath updated）；applyWallpaper 18/19 次 body 都 short-circuit 跳过 4 个 layer setter。Hermes 5 条查询 verified 路线（_ConditionalContent frozen / setter 不 idempotent / @Model per-keypath / @Observable per-property）。**遗留**：第一次点输入框 focus 仍轻微卡（粟粟反馈），未追，等下一轮。完整文档 `docs/research-perf-2026-04-25.md` + `docs/plan-perf-2026-04-25.md`。|



**砍掉（不阻塞 TestFlight）：**
- ~~对话置顶 pin~~ → v1.1
- ~~搜索文字输入筛选~~ → v1.1
- ~~thinking 穿插式卡片~~ → v1.1（成本高收益窄）
- ~~首次启动引导~~ → v1.1
- ~~全屏白框~~ → macOS only
- ~~滚动条~~ → macOS native
- ~~上下文总结~~ → Phase 1.5（TestFlight 发出后第一件事）
- ~~记忆系统跑通~~ → Phase 1.5（紧跟总结之后）

**完成标志**：朋友拿到 TestFlight 链接，装上能聊天，不会一脸问号。

### Phase 0.6：1.0.1 稳定性批次（2026-04-28 → 2026-05-05）

> 目标：把 1.0.0 已发现的旧功能 bug 修干净 + 消化 TestFlight 反馈。
> **不做新功能**——粟粟原话："新功能先不急先把旧功能可以用吧"。

**节奏**：
- 这一周（04-28 → 05-05）：观察 33 个 testers 的 sessions/crashes/feedback；本地修 bug；**不发新 build**
- 一周后：攒批次 → archive 1.0.1(2) → 上传 → 等 24-48h 审核
- 不边修边发（每次发版 24-48h 审核窗口太贵）

**bug 优先级**：

| 项 | 来源 | 优先级 | 状态 |
|----|------|------|------|
| **B20 上下文混乱** | 自测 | 🔴 P0 | 未开始（核心功能错乱，朋友肯定看到）|
| **B21 角色卡/世界书 ↔ prompt 体系** | 自测 | 🔴 P0 | 未开始（卖点不接 = 摆设）|
| **B22 背景变白色** | 自测 | 🟡 P1 | 未开始 |
| **B23 收藏不跳转** | 自测 | 🟢 P2 | 未开始 |
| **TestFlight 反馈处理** | 朋友 | 视情况 | 持续观察 ASC dashboard |
| **分支整理（B 路）** | 架构债 | 工具活 | 待粟粟点头：git tag v1.0.0-build1 + master 快进 + 删 kelivo |

**完成标志**：1.0.1 上 TestFlight，朋友实测 1 周无新崩溃，4 个 bug 关档。

---

### Phase 1.5：上下文 & 记忆跑通（TestFlight 发出后立刻做）

> 目标：让"架子"变成"真的能用"。这是记忆宫殿区别于换皮客户端的核心。
> **不做花哨 UI，只做最小可用版。**

| 项 | 来源 | 说明 | 预估 |
|----|------|------|------|
| **上下文总结（最小版）** | 新 | 到 contextDepth 阈值时自动调便宜模型总结旧消息，存为摘要注入 system prompt。参考 Operit（token 阈值触发）+ Claude Code（工程式总结）。**不做**：独立总结模型配置、手动大小总结、右栏实时查看——这些是 Phase 3 | 2-3 天 |
| **记忆系统接线** | M6 | AUDN 提取器已有，缺"发完消息自动触发"的 hook。接上后模型能自主写/更新记忆 | 1 天 |
| **上下文管理 UI（最小版）** | 新 | 设置页加一个总结开关 + 阈值滑块，右栏或对话内能看到当前摘要。**不做**：独立管理面板 | 1 天 |

**完成标志**：聊 100 条不失忆，模型能自动记住关键事实。

**远期完整版（Phase 3）：**
- 总结模型单独配置（便宜模型 vs 当前模型）
- 手动触发大总结/小总结
- 右栏上下文管理面板（实时查看摘要、总结历史）
- 总结提示词自定义（放 Prompt 插槽系统）
- 文件/图片上下文截断策略

### Phase 2：自用验证

> 目标：自己日用，把剩余架子补齐。

| 项 | 来源 | 说明 |
|----|------|------|
| 酒馆预设系统实际验证 | E15 | 自己用一遍、调通、补缺 |
| API 管理完善✅ | E16 | 多 provider 配置/切换走通 |
| 新建楼层 iOS 适配✅ | B8 | 改成系统 List 样式 |
| 开关网络功能 | X5 | 安全模式 |
| UI 一致性扫描 | E1 | 间距/对齐/hover 态 |
| 右栏内容管理 + 自定义 | E12/E13 | 长按删除/添加 |
| 微交互反馈 | E14 | toast/haptic/动效 |

### Phase 3：扩展能力

> 目标：从"能用"到"好用"——图片、主题、更多导入源。

| 项 | 来源 | 说明 |
|----|------|------|
| 图片支持 | C1 | 匹配 ChatGPT 导出图片 + 聊天发图 |
| 导入酒馆聊天记录 | C12 | SillyTavern 对话导入 |
| 更多导入源 | C6 | Gemini → RikaHub → Kelivo → Operit |
| Token 精确计数 + 可视化 | C4/C5 | 调 API tokenize 端点 |
| 皮肤/主题切换 | E2 | design-dna.json token 已有 |
| 首次启动引导 | E3 | 新手流程 |
| 搜索扩展到预设/世界书/角色卡 | C8 | 搜索范围扩展 |
| 对话置顶 pin | E11 | — |
| thinking 穿插式卡片 | E8 | 说-想-说 |
| 搜索文字输入筛选 | E9 | — |
| 英文版 / i18n | X4 | 至少中英双语 |
| 自定义 app 图标 | X13 | iOS 预置多套切换 |
| 使用说明书 | X6 | 设置页内嵌 |
| 开源准备 | X7 | public repo + 社区 README |
| 楼层设置添加世界书 | 新 | 从已有书里选绑定 |
| 角色卡封面图展示 | 新 | 侧边栏缩略图 |
| Author's Note | 新 | 酒馆标准注入点 |
| 世界书高级功能 | 新 | sticky/cooldown/delay/group 互斥/use_regex |

### Phase 4：远期愿景

skills/hook/agent接入

| 项 | 来源 | 备注 |
|----|------|------|
| 向量嵌入记忆检索 | M1 | 等 Apple NLContextualEmbedding 稳定 |
| MCP 连接 + 记忆同步 | M3/M4 | 等 MCP 生态成熟（其实已经成熟了已经能用！） |
| 无限画布 | X3 | 贴纸的坐标系可以演化 |
| 插件系统 | 新 | 独立产品级工作量 |
| iCloud 备份 + 同步（可选）| X26 | 走系统 iCloud，数据在用户自己账号里 |
| visionOS 博物馆模式 | X2 | 等硬件普及 |
| fastlane 自动化发布 | 新 | TestFlight 跑通后配置 |
| 日历增强 | X9/X10/X11 | 特殊日期/对话卡片/热力图 |
| 对话上下文标注 | X12 | 听的歌/地理位置/天气 |
| 随机跳转 | X19 | 随机重温旧记忆 |
| "一年前的今天" | X20 | iOS 相册回忆风格 |
| 对话摘要 | X21 | 自动一句话摘要 |
| iOS Widget | X22 | 桌面小组件 |
| 分享片段 | X23 | 截取气泡生成分享图 |
| 语音输入 | X24 | 系统语音识别 |
| 侧边对比 | X25 | macOS 左右双对话 |
| Shortcuts/快捷指令 | X27 | Siri 集成 |
| 键盘快捷键体系 | X28 | macOS 快捷键 |
| 贴纸更多制式 | X18 | 邮票/胶卷/时间戳/动画贴纸 |
| 动态壁纸 | X16 | — |
| 像素风主题 | X17 | — |
| 教学指导模式 | X14 | 霓虹 |
| 工具调用卡片 UI | X15 | function call 可视化 |
| **字体商店（按需下载）** | E18 延续 | app 本体不内置字体，设置里做一个「字体商店」列表页，粟粟要哪个现下到 Documents/Fonts（走现有 `importFont` 通路）；可解决"打包字体=app 体积膨胀"的死结（当前 2 个字体就 +47MB，想扩展 10 个以上完全不现实）。需要：字体索引 json（CDN）+ 下载进度 UI + 已下载管理 + 首次打开引导「要不要下载几款中文字体？」 | 中 |

### 不做清单

- 不复刻酒馆 UI — 记忆宫殿的设计直觉是竞争优势
- 不搭我们自己的服务器 — 用户数据不经过任何我们运营的后端；要同步只走 Apple 系统级 iCloud（用户自己的存储）
- ~~SettingsView 拆分~~ → ✅ 已完成（5043→225 行 + 8 个独立 tab 文件）

---

## 七、当前应该做什么？

> 这部分每次开工前更新。最后更新：2026-04-28

**已完成**：
- 七根柱子全部搭好 ✅
- 贴纸/角色卡/世界书/正则/工具抽屉合入 master ✅
- SettingsView 拆分（5043→225 行）✅
- 侧边栏 Chrome 标签栏 ✅
- iOS 基础版可用 ✅

**2026-04-18 完成（iOS 左栏视觉收尾）**：
- ✅ tab 栏 Clock 式 snap + 震动 + 「全部」锁定 + Chrome 反向圆角
- ✅ tab 栏与 `TabView(.page)` 翻页手势冲突（UIHostingController + `require(toFail:)`）
- ✅ 搜索状态栏从 tab 下方移到底部 footer
- ✅ 搜索结果卡样式统一到普通列表
- ✅ 搜索作用域跟随当前 tab（收藏/回收站/tag 各自限定，空 scope 短路）
- ✅ 空搜索结果用白色卡片
- ✅ 筛选器去胶囊改纯文字 + 分类名与选项同行 + 间距调整
- ✅ 回收站 tab 卡片右上角圆角修复
- ✅ 技术债：`sidebarCardShape(for:)` ViewModifier 抽象（5 处重复收敛）
- ✅ 文档：左栏模块 postmortem + diagnosis，plan-tab-gesture-conflict.md 标 superseded

**2026-04-19 完成（iOS 键盘 B7 + 列表下拉刷新 + 延迟置顶 + 卡顿 fix）**：
- ✅ B7 全 5 症状：S1 点 TextField 要长按（`.onTapGesture { isFocused = true }` 抢焦点，保留 glassEffect `.interactive()` 视觉）
- ✅ S2 键盘弹起整页上移 20-30px（`contentInsetAdjustmentBehavior = .never`，ChatInputBar 靠 `safeAreaInset(.bottom)` 跟随）
- ✅ S3 空结果下滑收不了键盘（`.refreshable` 激活 pan velocity + 空态 `.onTapGesture` 兜底）
- ✅ S4 设置页下滑不收键盘（7 个常用子页加 `.scrollDismissesKeyboard`，WorldBook/CharacterCard 等复杂页延后）
- ✅ 键盘顶 5px 呼吸间距
- ✅ 左栏 4 个 ScrollView 加 `.refreshable` + 统一 `.scrollIndicators(.hidden)`
- ✅ 空态小卡 170pt 保留萌感 + 系统下拉动画（`.scrollBounceBehavior(.always)`）
- ✅ **对话列表延迟置顶**：点击不排 / 内容改动 3s debounce / pull+切楼层+后台+chat→sidebar 立即 flush / softDelete 纳入 debounce + 更新 nodeCount
- ✅ **卡顿 fix R1**：revert `@Environment(ProfileManager.self)` + `scenePhase` observer（让 ContentView 每次 profile 通知都重算整个三页 TabView）→ 粟粟真机"直接变顺滑"
- ✅ **打字性能微优化**：ChatInputBar 拆 InputFieldContainer 子 view；打字期间外层 ContentView.body = 0 次 / ChatInputBar.body = 0 次，只最内层重建；架构上防将来外层复杂化拖累打字
- ✅ [PERF] 探针 log（DEBUG-only，TestFlight/Release 自动剥掉）：App.init 109ms（全在 SwiftData schema）/ loadConversation 24-58ms 秒开 / 打字外层完全隔离 ；粟粟决定留着后续卡顿复测
- ✅ 更新记忆 lesson #8（TabView 键盘避让纠正为全部 `.never`）+ 新增 #11（`.interactive()` tap-through 时序坑）+ #12（模拟器对 iOS 26 新 API 不可靠）
- ✅ 从 B7 剥离 B13 iPhone 14 整体卡顿（性能问题独立，不阻塞 TestFlight）

**2026-04-20 完成（搜索模块整轮）**：
- ✅ B2 标题搜索的筛选自己作用于标题（排序/时间对标题列表生效）— 修 `triggerSearchIfActive` 偷偷跳全量搜索的 bug
- ✅ 内容搜索时间过滤挪到内存层，绕过 SwiftData optional `!= nil && !` + `localizedStandardContains` 返空集的坑
- ✅ 新「范围」筛选（标题 / 内容 / 标题+内容），结果分块渲染（标题块恒在上、细线分隔、各块独立排序）
- ✅ C8 搜索扩展到角色卡 / 世界书 / 记忆（贴纸之外新三类）
- ✅ `RightPanelNavigator` @Observable 协调搜索 → 右栏跳转，面板 ScrollViewReader 监听 + 1.5s 高亮脉冲
- ✅ iOS/macOS 跳转统一（ContentView `.onChange(pendingTarget)` 分发 iOSPage=2 / isRightPanelVisible=true）
- ✅ T4/T5 技术债收口：`SearchScope` + `SearchResourceKind` 两个枚举，退役 `searchShowStickers` bool；状态机按 resourceKind 分流
- ✅ 清 `fetchNodesDateOnly` 的 SwiftData optional 坑（删整路径，边缘场景不再绕）
- ✅ 资源类型下「范围」「角色」chip 灰掉；列表模式切资源类型有关键词时自动 triggerSearch，无关键词 clearSearch

**2026-04-26 → 04-28（TestFlight 上架 + 朋友圈传播）**：
- ✅ 04-26 早 Manual signing 突破（Apple Distribution: Jing Lu (GQN42B462A)，scoped to MemoryPalaceIOS target）
- ✅ 04-26 早 Archive 1.0.0(1) 上传 ASC，5 分钟 processing 完
- ✅ 04-26 ASC App record auto-create（**App Name "记忆花园"**，"记忆宫殿"被占；Bundle ID / PRODUCT_NAME 仍是原值）
- ✅ 04-26 Internal Testing + iPhone 17 Air 自测通过
- ✅ 04-26 ipa 包审计无内部文件泄漏（`docs/`/`.git`/`CLAUDE.md` 全在 ipa 外）
- ✅ 04-26 Privacy Policy URL = GitHub Gist（双语，replica882/97c7b3...）
- ✅ 04-26 External "Friends Beta" 组建立 + Public Link 开启
- ✅ 04-26 Submit for Beta App Review
- ✅ 04-27 苹果一次过审 Approved 🎉
- 📊 04-28 早：33 个 testers 通过 Public Link 加入，最重度 iPhone 16 用户单日 20 sessions

**正在做**：Phase 0.6 — 1.0.1 稳定性批次
- 旧功能 bug 修复（B20 上下文混乱 / B21 角色卡 ↔ prompt / B22 背景白 / B23 收藏跳转）
- 不发新 build，1 周后攒批次
- 待办：B 路分支整理（git tag + master 快进 + 删 kelivo）

**不阻塞 TestFlight 的 B13**：iPhone 14 性能问题独立立项（T9），等主力机型 17+ 的 TestFlight 发完再研究。

---

## 八、粟粟已确认的决策

| 问题 | 答案 | 更新 |
|------|------|------|
| 日常主力用它了吗？ | 还没有，主力还在 Claude.ai 和酒馆 | 2026-04-12 |
| 先发哪个平台？ | **iOS 先发**，macOS bug 延后 | 2026-04-17 |
| 记忆/预设系统验证了吗？ | 没有，架子搭好但没真正用过 | 2026-04-17 |
| iOS 有多急？ | 主用 iOS，下周发 TestFlight | 2026-04-17 |
| 想不想给别人用？ | 要给别人用，想变成基础设施 | 2026-04-12 |
| 图片重要吗？ | 重要 | 2026-04-12 |
| 什么能让你搬过来？ | **贴纸功能**（已完成）| 2026-04-14 |
| 数据策略 | 不搭我们自己的服务器；要做同步只走 Apple 系统级 iCloud（用户自己的 iCloud 账号，我们看不到）| 2026-04-28 修订 |
| 文件夹方案 | 改为 Chrome 标签栏（已完成）| 2026-04-17 |
| 左栏视觉模块 | 收尾完成（tab 栏手势 + 搜索作用域 + 筛选器美术 + 债务清理） | 2026-04-18 |
| iOS 键盘怎么修 | 真机 A/B 开关 debug build，粟粟 iPhone 17 Air 实测定根因，保留 `.interactive()` 玻璃视觉 | 2026-04-19 |
| iPhone 14 卡顿归属 | 独立 bug（B13）+ 技术债（T9），不阻塞 TestFlight | 2026-04-19 |
| 搜索的两种心智 | 不按 ➡️ = 列表标题过滤（范围=标题）/ 按 ➡️ = 全量搜索；资源类型没有列表模式，切过去就按 ➡️ 语义走 | 2026-04-20 |
| 标题+内容分块 | 上块标题（不展开）/ 下块内容（展开 matchedNodes）/ overlap conv 两块都出（决策 B，找得到比不重复更重要） | 2026-04-20 |
| 资源跳转实现方案 | `RightPanelNavigator` @Observable + 面板 ScrollViewReader onAppear+onChange 双监听；ContentView 按平台分发（iOS 切 iOSPage / macOS 开 isRightPanelVisible） | 2026-04-20 |
| 字体打包策略 | v1：打包 2 个 OFL 字体（霞鹜文楷 + 思源宋体 SC）+47MB；不选 Lite/子集化版（怕生僻字/古诗词豆腐块）；未来：字体商店按需下载 | 2026-04-24 |
| 1.0.1 发版节奏 | 1 周观察 testers + 本地修 bug → 攒批次 archive → 上传 → 等审核。**不边修边发**（每次 24-48h 审核成本太高）| 2026-04-28 |
| 1.0.1 范围 | 只修旧功能 bug（B20-B23），不做新功能。原话："新功能先不急先把旧功能可以用吧" | 2026-04-28 |
| ~~master 分支策略~~ | ✅ 2026-04-28 完成（plan-master-merge.md 关档）：打 `v1.0.0-build1` tag → d1c946b / master force push 对齐 pristine (a299314) / 删 7 个已合并分支 + 6 个 worktree / 13→7 本地分支 / 9→4 worktree | 2026-04-28 |

---

*这份文档是活的。每次做完一个 Phase 或者想法变了，就来更新。*

# 坑账 DEBT-MAP

> **唯一真账。** 开新坑先在这里记一笔，填完当场销。别的文档与本账冲突时，以本账为准。
> 立账 2026-07-28：TEST-CHECKLIST 13 项兔兔全验 ✅ 已销账。

## ⚠️ 给并行会话的一封信（2026-08-31，Fable 消防记录）

今天 main 连炸四次，全是同一个姿势：**没等 CI 绿就推下一刀**，前一刀的错攒到后面一起爆。
明细：`4c19275c` 递归 @ViewBuilder（opaque 自指）→ `b8e531bd` 注释行裸奔少 `//` →
同刀复活的 BookChatDrawer 用的是粟粟侧 API（startDraftConversation/resolveModel 我们没有）→
连锁暴露 toolbar ambiguous。四刀全由共听线这边顺手修掉（fcb9560b/fb462cf7/1231ea48/e10832f7）。
**规矩重申（对所有会话包括我自己）：一刀一 commit，CI 绿再下一刀；从粟粟侧复活代码前先
grep 我们有没有那个 API。** 修火不心疼，心疼的是兔兔看到红勾勾会担心。—— Fable 🐰🔥

## CC 升级 2.1.241 → 2.1.258 · Fable 5.1（2026-09-03 Fable，兔兔拍板）

**已做**：
- `npm i -g @anthropic-ai/claude-code@latest` → 2.1.258。Fable 5.1 要 ≥2.1.251，旧版报
  `400 Claude Code 2.1.241 does not support this model`。EBADENGINE（要 node 22）只是警告，claude.exe 是原生二进制。
- 升级前先挪走 8/24 残留的 npm 暂存目录 `.claude-code-1devilah`（649 MB，害 rename ENOTEMPTY）
  → `/root/backups/cc-upgrade-0903/old-staging-2.1.2xx`，确认可用后可删。
- `~/.claude/settings.json` `model: claude-opus-4-6 → claude-fable-5-1`（备份同目录）。
- 网关 `/v1/models` 加 `claude-fable-5-1`；`-p` 反代实测 `"model":"claude-fable-5-1"`，in=277 token。

**✅ 已 respawn（09-03 02:54 兔兔时间，兔兔拍板，Fable 操作）**：
用 `session-manager.ts` 同款命令 `tmux respawn-pane -k`（脚本存 `/root/backups/cc-upgrade-0903/respawn-caelum.sh`），
转录本读回、回「在。」、转录本字段 `model=claude-fable-5-1`、cache_create 122,500 一次性重建、mcp-server 子进程在。
注意：`--resume` 会带回会话里记着的模型（起来先是 opus-4-6），settings.json 压不过它，
须在他那儿 `/model fable` 再确认一次「Yes, switch」——以后 --resume 就记住 5.1 了。
顺手收掉 `mp-cc-2` / `mp-cc-70fd413c` 两个 9~11 天的孤儿会话（各一个 `--continue` 进程，空提示符，共 400 MB）。
五点六攒的三件（ask_choice 修复 / 通配符授权 / 语音条教学改写）此刻一并生效——**兔兔先让他试 ask_choice**。

**🔧 watchdog.sh 三处错已修**（备份 `/root/backups/cc-upgrade-0903/watchdog.sh.bak`，BunnyBridge 不是 git）：
token 读的是顶层 `oauthToken`（五点七的坑本尊）→ 改 `claudeAiOauth.accessToken` 优先；
命令带 `--dangerously-skip-permissions` + `IS_SANDBOX=1`、少 `--system-prompt-file` → 对齐手术版。
**没修的雷（留账）**：watchdog 第 3 段（401 自动刷新）把 credentials.json 整个重写成旧格式，会把 `claudeAiOauth` 抹掉；
它只在 pane 出现「401 Invalid authentication」时触发，refresh-token.sh 正常工作就不会走到。
**小雷**：tmux server（pid 494853，47 天）的 argv 里明文带着当初的 OAuth token，`ps` 可见。老 token 大概率已失效，
但下次不得不重启 tmux server 时顺手让 watchdog 用 `-e` 传 env 而不是拼进命令串。

**原待办（已消）**：
Caelum 正在跑的两个进程（pid 1476096 / 1728101，inode 3801110 / 3801115）持有的是**比 2.1.241 还早**的
已删除二进制，升级碰不到他。他要用 5.1 必须重开（`/model fable` 在旧进程里也会被服务端按客户端版本拒）。
重开时：① 先问兔兔 ② token 按五点七取 `claudeAiOauth.accessToken` ③ 顺手收掉孤儿进程（两个 --continue 只该剩一个）
④ 先让他回「测试」验证再让兔兔说话。session `252c3c5a` 260 MB，--continue 读回需要几秒。

**待验收**：兔兔真机 App 模型列表选 `claude-fable-5-1` 聊一句。

## claude -p 反代 · 近裸化 + 错误透传（2026-09-02 晨 Fable，`b2614e6a`）

**兔兔报「API 错误」→ 查出来不是 CC 的锅**：nginx 8/27 记了 5 次 502；8/31 01:33 → 9/1 23:07
systemd `lib-gateway` 与另一进程抢 4567 端口，**崩了 12,528 次**（EADDRINUSE 循环），昨晚占端口的死了才接上。
现 systemd 稳定持有端口。**谁再手起网关请先 `systemctl stop lib-gateway`**，别两个抢。

顺手修的三件（参考 sibylsea-hub/cc-codex-sdk-modify-preset）：
- `--tools none` 没拔干净——claude.ai 连接器的 100+ MCP 工具每次整个进上下文，22376 token/请求。
  改 `--tools "" --strict-mcp-config --setting-sources "" --no-session-persistence` + 干净 cwd → **226 token**。
- CC 出错（限额/鉴权/模型名）只发 `is_error` 不发 stream_event，App 收空流。现在先等第一个事件再定：
  正常→200 流，出错→**502 + 原文**（App `handleErrorBody` 直接显示）。stderr 记日志，每请求一行 token/cost 摘要。
- 不再堆 session 文件（`~/.claude/projects/-root-projects-BunnyPalace` 已 612 个，可清）。

**待验收**：兔兔真机用 claude-code / opus-4-7:thinking 各聊一句，看回复正常、日志 `[claude-p]` 行 in≈几百而非两万。
**小谜题**：谁在 8/31 01:33 起了第二个网关？（`~/.bash_history` 或某会话手动 `bun src/index.ts`）

## 聊天页发送白屏 · 第五刀（2026-09-02 晨 Fable，`280c30a0`）
兔兔：「发完消息整页空白，往下划一下才回来；两条车道都会，长对话更明显」。同一病根第五次
（滚动位置飞了露出没画的区域），前四刀在进页面/回前台/键盘弹起/键盘收起，发送这个时机
一直没兜底。这刀三件事：渲染窗口改记**起点**（不再每发一条顶上挤掉两条——长对话更明显的
来源）+ 发送后强制回底 + CC 回复落地回底（CC 不流式，没有 API 车道那个 streamingText 收尾口）。
- [ ] **真机验**：长对话（>60 条）连发几条不白；CC 回复落进来不白；上滑读历史时 CC 主动
  说话**不被拽回底**（新增只在她本来就在底才回底）
- [ ] 若还白：下一个嫌疑是气泡入场动画（`.animation(value: currentPath.count)` + move(edge:
  .bottom) transition）与 defaultScrollAnchor 同帧——可试 transaction 禁掉入场动画看是否消失
- 窗口起点制的代价：同一对话一口气聊很久窗口会一直变长（每发 +2），切对话即收；上千条
  的卡顿若在长会话里回来，加「在底且窗口 > 3×step 时静默收窗」即可

## 一起听 · 共听线余账（2026-09-02 凌晨 Fable 记）
- [ ] **hub 重启**吃下共听注入（3f7fbb08 已落码未生效）：`kill <hub pid>` 后 watchdog 15min 内精准拉，
  或直接照抄 watchdog.sh 那条 setsid 命令。等兔兔点头（动 hub 前先问她）
- [ ] **API 车道同款提示行**：hub 已挂「共听中·别复述歌词」，但她用 DeepSeek/TreeGPT 等走 app 内
  PromptAssembler 时没有这行——app 侧共听开关（MusicPanelView 的 person.2）为 true 时往动态尾巴
  塞同一句即可，几行；和 T4 一起下刀，别单独发 ipa
- [ ] **T2 邀请实机验**：新 ipa（含 42f082fb）按 person.2 → 他收到 `liveline_listen_invite` 先开口。
  网关侧链路已读通（/listen/start → pushLiveline → hub /internal/notify 回环免 token → tmux）
- [x] 网关重启（09-02 02:05）：T1 进度/当句 + T2 /listen 路由已生效，now_playing 合成测试通过
  「进度 1:23 / 3:35 · 正唱到：「…」」（暂停态也报）。**网关真身现在是 systemd `lib-gateway.service`**
  （见 HANDOFF-0901「服务地形更正」），不是 tmux

## 选择卡（ask-user）· 兔兔 08-31 实测不通 → Fable 已修 API 道
- [x] **API 车道**（Fable 08-31）：根因不是接线细节——ask_user 压根没进 ToolRegistry，
  模型从来收不到这个工具；执行侧的暂停/恢复也从未做。已修：注册 + ToolCallLoop 挂
  AskUserGate continuation 等 sheet（循环上下文原地活着，不需要骨架设想的整轮打包）。
  兔兔重验：API 模型说「问我几个选择题决定晚饭」应弹卡
- [ ] **CC 车道**：app 听的 `ask_user_question` 帧全链路没人发（mcp-server/hub 皆无）；
  但**另有一条老 ask_choice 线端到端是全的**（mcp 工具→hub 转发→app 626 行→答案帧回）。
  两套并存，建议下刀二选一收敛：要么给 ask_user_question 补 mcp 工具+hub 转发，
  要么让 Opus 的新 sheet 接到 ask_choice 帧上、删旧 UI。等拍

## page2 整体打磨（进行中）
- [x] 胶囊九渡结案（撑开顶走+同口弹簧）；尾部点不准三针；冷启动 visited 缓存根治
- [x] 探针全拆（两案结案）
- [ ] 剩余逐项对照粟粟（间距/底色/滚动边缘细节），兔兔录屏当弹药
- [ ] **Xcode 26 搬家 + 玻璃大回归**：票在 probe/xcode 分支（26.4 全绿实测），等兔兔点头。
  换乘对 iOS 18 手机无感；玻璃包 #available 护栏

## 气泡整套搬运 · 兔兔 08-31 实机验收余账
- [ ] **图片消息进泡（正解）**：发送链路改写 .image 段（发新消息时图片落 segments，
  content 只留文字），她的附件条/预览/保存全套自动生效；API 请求组装层要同步适配——
  单独一刀，别顺手。当前止血：气泡模式下 multimodal_text 回落文章路径
- [ ] **语音一条一泡没生效**：她的 voiceSegs 读 .audioRef 段，理论上该进泡——查为什么
  兔兔看到的还是泡外胶囊（兔兔说不急）
- [x] **思考链弹窗**：确认是产品问题非 bug——兔兔拍板思考链退出对话流，长按「他当时在想…」（6761780d）
- [x] 气泡模式发图白条 + 划不到底（止血：回落文章路径）
- [x] 全屏预览存相册（MultimodalUserBubble 改走 AttachmentPreviewSheet）

## 待验收（真机，一次搞定）
- [ ] **亲密卡**（16:19 后的包才有）：设置→健康开「亲密」→ 面板点心记/取消、note 覆盖语义、详情页点阵 → 开 AI 闸问 Caelum「今天有什么健康记录」他知道 → 口头让他帮记出「♥ 已记下了」→ 反向：问 note 内容他不知道；关闸他完全不知道这卡
- [ ] C2 顺手项：设置→Token 统计，缓存命中率不是 0
- [ ] HealthKit 10 秒项：健康页点「重新授权/刷新」+ 下拉，「今日快照」出数据即可（步数/屏幕时间的代理上报链路本来就在跑，只差 App 内直连这一下）

## 代码审查（2026-08-12）· 已修与留账

**已修（af9ac174 / 8966ff61 / d4b28bfb）**
- ✅ 静默存盘 → 新增 `context.saveOrReport()`，替换 16 处最关键的（药物同步/聊天消息/记忆）
- ✅ `desire.ts saveMemory` 位置参数调对象签名 → 一直在写垃圾数据，已修
- ✅ `/mcp` 端点跳过鉴权 → 仅 hub 绑 127.0.0.1 时免密
- ✅ cc-bridge 全局异常完全静默 → 落 `/tmp/mcp-server-errors.log`（不碰 stderr，保命设计保留）
- ✅ iconv shell 注入面 → 改 execFileSync
- ✅ 记忆写入/更新静默失败 → do-catch + toast

**留账（报告自评「可不改」，当前运行正常）**
- [ ] SyncEngine 后台线程创建 ModelContext —— Swift 6 strict concurrency 下会报错，迁移前必修
- [ ] ChatService base class 用 fatalError —— 三个子类都 override 了，直接实例化才崩
- [ ] HealthBridgeClient 非 200 不记 log —— 半小时窗口内不丢数据，只是延迟
- [ ] 其余 ~80 处 `try?` —— 多在冷门路径，碰到再改
- [ ] CareView 的 max() 双源创可贴 —— 真同步已上线，验收通过后拆
- [ ] P1 27 条 / P2 38 条 —— 详见 `docs/audit-*.md` 四份报告

## 坐标系（2026-08-22 已解决）
快捷指令给的是 **WGS-84**。送给高德前**必须**转 GCJ-02——实测不转会偏 **559 米**：高德把她所在的「五原西路」认成 500 米外的「电信花园住宅楼」。转换后认「五原西路银堤漫步」，与手机自报吻合。
已实现：`gateway/src/geo.ts`（转换 + 逆地理编码），位置工具现在同时给高德地址与附近 POI。高德 key 在 `gateway/.env` 的 `AMAP_KEY`。
⚠️ 算法要点：先把经纬度**减去参考点 105/35**，网上很多实现漏了这步。

## 小谜题（不影响使用，好奇时再查）
- [ ] **快捷指令词典里绑不上 Latitude/Longitude 变量**：同一条快捷指令里，is_charging/battery/Weather/Place 四个变量都能绑进词典（显示成橙色标签），但经纬度那两个死活绑不上，发出去只有 5 个字段。已排除：①类型选错（兔兔确认选的是「文本」）②作用域（设变量都在词典之前）。当前走 URL query 传参绕过，已通（实测 34.7768/111.1755）。

## 想做但还没做（2026-08-25 记，来自兔兔看到的几个项目）

### iOS 系统能力三件套（都**不需要向 Apple 申请**，也不用麻烦粟粟）
证书蹭的是粟粟的（Team `GQN42B462A`），所以刻意避开 **App Group**——
Widget / Extension 一律直连网关取数据，不走本地共享容器。

- [ ] **锁屏小组件 & 灵动岛**（Widget Extension，做一次出两样）
  - 小组件：他最近说的一句话、今日水/饭/药、距下次吃药多久、纪念日天数
  - 灵动岛：他正在打字、共读进度（她第几章 / 他领先几章）、正在放的歌
  - 延迟不是问题：小组件本来就 15 分钟才允许刷一次，而走服务器还能用静默推送触发即时刷新；灵动岛本就是推送驱动，秒级
- [ ] **屏幕共享**（Broadcast Extension）
  - 现状：`peek_screen` 走「发邮件→快捷指令截图→上传」，慢且链路脆
  - 目标：常驻共享，他随时能看到画面
  - ⚠️ 硬限制：**iOS 不允许 App 自己开始录屏**，必须兔兔从控制中心长按录屏按钮手动开
  - ⚠️ Extension 内存墙 **50MB**，超一字节即被杀 → 720p/15-30fps/硬件编码
  - 传输：Extension **直接推服务器**，不回主 App（这样也绕开 App Group）
  - 先做「连拍版」（每 2-3 秒一帧 JPEG）比实时视频流务实得多

### 来自 ringdonut（codeberg.org/donutbunelli/ringdonut）
- [ ] **语音通话**——比现在的单向语音条更进一步。值得抄的四点：
  1. **他能主动打给她**：模型调工具发起真实来电，「模型不能靠输出文本伪造一通电话」
  2. **温柔挂断**：说完再见后电话多留 15-18 秒，她开口就取消挂断
  3. **听得出语气**：不只 STT 转文字，还做声学分析（音高/能量/停顿）
  4. **摘要可信**：先提取证据再验证摘要是否忠于原文，不编造没说过的话
- 我们已有的底子：语音条那套表演脚本 + ElevenLabs + 情绪标签（同源）

### 来自 sleepy-dog-lock（bella-and-c）
- [ ] **睡眠锁**——把「晚安」变成真的会执行的东西
  - 系统级 Shield 拦截 App（不是又一条可以划掉的提醒）
  - 偷开一次就记一次 + 推送给对方，**先写记录再发推送**（推送失败证据也不丢）
  - 三档递进文案
  - ⚠️ 安全线：**不拦电话/信息/地图/支付/医疗**
  - 我们的优势：有门铃 + 直播线，他能**主动来堵她**，不只是被动记录

## 待写码

1. [ ] **朗读升级到真人声**（等 MiniMax key）：朗读走 MiniMax（便宜管够），语音条留 ElevenLabs
2. [ ] 音色试听 preview_url 走 Google CDN，/xi/ 反代不覆盖——App 内试听大陆网络无声，暂用网页端/盲测
3. [ ] 花房锦上添花项（设计方案步骤 6-7）：每日一菜（他挑旧碎念端写作提案）、督促节奏（温和/可关）、灵感盒热力图、打字机模式
4. [ ] 拆 vitals 的 max() 创可贴（真同步已上线 276b5c3，验收通过后拆）

## 记忆系统 · 体检报告（2026-08-05，兔兔要求先搁置，后续再做）
系统本身很完整：15 模块 2500 行，存 Supabase，含提取/召回/衰减/做梦/碎念/情绪/欲望七层，记忆带 tier/valence/arousal/heat/activation_count/is_anchor。
**但实际基本停摆：**
- [ ] **提取器不跑**：24h 零日志。消息 1918 条（6/5–8/4），记忆只有 14 条且全是早期的——**最近两个月一条没记**（最要紧）
- [ ] **两张表没建**：`dream_events`、`desires` → 每次做梦/欲望都报「表不存在」刷屏
- [ ] **热度全凉**：所有记忆 heat=0.01（衰减跑过头），但 activation_count 有 20+，说明曾被频繁想起
- [ ] **有重复记忆**：草莓蛋糕那条出现两次，未去重
- [ ] `memory_rings` 表 0 行（记忆环没用起来）

## 共读 · 待做（兔兔构想）
- [ ] **他先读完、两人互相追进度**：现在他只能读兔兔翻到的当前章（App 推 reading_context）。要让他走在她前面留批注，需要给他「按需读第 N 章」的能力——App 现取现给（倾向此法，不占空间）或导入时整本上传。book_note 已支持写到任意章（84684f29），就差他能读到。

## Twitter · 待查
- [ ] **配图识别没起作用**：get_my_tweets 描述称「已同步进记忆库，含配图识别」，兔兔实测没生效。需查同步链路与识别环节。

## 卡在兔兔（各一次性操作）
- [ ] MiniMax 注册拿 key（platform.minimaxi.com，国内手机号）→ 设置-语音-语音服务切 MiniMax + 填 key
- [ ] 两把 ElevenLabs key 后台重新生成（曾发给 Fable 排障，换锁是好习惯）

## 已销账（2026-07-30~08-01 核实）
- ✅ 语音设置孤儿挂载（44228e0 已挂）
- ✅ 文件选择器修复（c85fb24 换 UIKit DocumentPicker）
- ✅ 双击文本选取（090d200 最终方案=移除双击手势让原生选取生效）
- ✅ 思考链 UI 改版（df7115d 折叠/弹窗双模式）
- ✅ CC 主动消息补 voice/health 收口（2773e7e）
- ✅ TTS 双后端（a071997 + d9d8f0a：TTSBackend 协议/MiniMaxClient/方言映射/双 key/设置页选择器）
- ✅ 语音条全链路七层雷（反代→两容器→静默失败→后台冻结→降级不说理由→reply 通道→AttachmentStore 死循环 4ba95dd）
- ✅ 朗读键上线（6dd9be5，含 TCC 闪退拆雷）

## 待拍板
（清零 ✅ 2026-07-28 复查：meds.ts 已从"第二套真相"转正为同步对端——App 本地为主人、/api/meds 是 Caelum 侧镜像+工具入口，必须留���情绪系统网关侧已实现并在运行——emotion/emotion-judge/desire/decay 共 718 行，app.ts 挂判定、index.ts 挂 desire 定时器，当日日志有活动；HealthKit 降级为上面的 10 秒项）

## 封存（不是债，是以后的甜点）
- 情绪系统迭代：对照 EMOTION-SYSTEM-DESIGN.md 盘点设计中尚未落地的部分（现状已上线，此项是增强非欠账）
- 花房 Phase 2 全量（写作编辑器等）

## 规矩
每个窗口开工先读本账。挖新坑不记账 = 军法处置 🐰

## 通话功能：STT（听）从零起 —— 2026-08-21 兔兔问，Fable 记

**现状**：`MemoryPalace/Services/Voice/` 七个文件全是 TTS（说），**没有任何 STT**。
输入框也没有麦克风/听写按钮。要做通话，"听"这一半是从零开始。

**粟粟怎么做的**：`CallTranscriber.swift` 用 iOS 26 的 `SpeechAnalyzer` + `AnalyzerInput`。
我们 target 是 18，兔兔手机也没升 26，**这条路直接不通**。

**替代方案（Fable 建议按此顺序）**：
1. **`SFSpeechRecognizer`（首选）** — Speech 框架老 API，iOS 10+，中文好，
   `requiresOnDeviceRecognition = true` 可走本地（不联网/不花钱/隐私好）。
   坑：单次识别约 1 分钟自动断，需重启逻辑——粟粟的 `restartTask` 思路可直接抄。
2. **走 gateway 中转** — 录音传 VPS → 服务端 ASR → 返文字。
   优点：换引擎不用重装 app，Caelum 能直接拿到音频。缺点：网络延迟，实时通话体感差。留作后手。
3. **WhisperKit 本地** — 准确率最高（中英混说尤其），但模型进包、耗电发热，通话场景不划算。

**意外之财**：为了 iOS 18 降级而写的
`/root/projects/SusuOriginal/MemoryPalace/Services/Voice/CallTranscriber.swift` stub，
已经把对外接口框好了（`onPartial` / `onFinal` / `onUnavailable` / `start` / `stop`）——
接 SFSpeechRecognizer 时往里填即可，接口形状现成。粟粟的 `CallScreen.swift` 接线也可参考。

**估**：一两个晚上。不是大工程。

## phone-status 的 place 没过「认家」，会把在家读成外出 —— 2026-08-21 Fable 亲自踩

**症状**：兔兔 08-22 00:25 在家躺着，`data/phone-status.json` 那条记录的 place 写的是
`徐记辣爆居\n中国\n河南省\n三门峡市 湖滨区\n银堤漫步东北门旁`。
Fable 读了这条，直接问她「昨晚是去吃夜宵了？」——她说她一直在家。

**根因**：快捷指令上报的是高德原始 POI 名，它会拿**最近的商铺**给坐标贴标签。
「银堤漫步」正是她家（`gateway/data/places.json` 的 home，半径 300m），
但存进 phone-status 的是**未经 `where_is_she` 认家处理的原文**。

**危害**：Caelum 直接读 phone-status 时会得到同样的误导。
「她在家」和「她在烧烤店」对他是两种完全不同的情境——尤其在凌晨、电量 4% 的时候。

**修法**：写入 phone-status 前先过一遍 places.json 半径判定，
命中就把 place 改写成「家」（或保留原文另加 `resolved: "家"` 字段，不丢信息）。
`geotools.ts` 里 `where_is_she` 的认家逻辑现成，抽出来复用即可。

**优先级**：不高但很实在——这条线是给 Caelum 看的，看错了比看不到更糟。

## 输入框下沉到 UIKit Paging 容器 —— 2026-08-24 兔兔提醒，Fable 记

**我下过一个错判断**：说「我们没有粟粟那套分页架构，为输入框搬 887 行 UIKit 不值」。
兔兔纠正：我们有。查证属实——`MemoryPalace/Views/Paging/` 两个文件与她**同名**
（fork 时即带），PagingViewController 我们 470 行 / 她 785 行，差的正是她后长出的那段。

**我们已有**：keyboardFrameWillChange / keyboardWillHide 监听、chat HC 的 keyboard
safe area 注入、home indicator 护盾、边缘 pan 手势。

**我们缺的（她 PagingViewController:146-200）**：
- `inputBarHost: UIHostingController<AnyView>` + `inputBarContainer`
  → 输入框下沉进 UIKit 容器（我们的还留在 SwiftUI 层靠 padding 定位）
- `container.bottomAnchor == chatHC.view.keyboardLayoutGuide.topAnchor`
  → 底边钉系统导轨，键盘起落自动跟随，**全程无手写间距**
- `PassthroughContainerView`：hosting view 默认拦截整个 bounds 的触摸，
  输入条栈上缘以下的空白会把消息按钮行挡死（她注：P1 复现器实锤）
- `barLayoutKick` + 延一 runloop：嵌套 UIHostingView 下 intrinsicContentSize 失效，
  打字时容器钉死不长高、文本内滚（KB-P3 探针实锤）；kick 若同步 layoutIfNeeded
  会打在键盘收起动画的建立窗口上把动画掐死（KB-P4：willHide→didChangeFrame 仅 29ms）
- 两个 KVO（bounds + center）发布 containerTop，供回底按钮锚点用

**要不要做**：先看 SwiftUI 侧把边距调对够不够用。真要开这条线的触发条件是——
兔兔摸到「输入框和正文不同步、慢一丢丢」且忍不了。那是 SwiftUI 结构性追不平的东西
（见她 docs/research-telegram-kb-send.md 的三条不变量）。

**估**：比我原先说的小得多（骨架现成），但不是一刀——透传容器和多行生长两个坑必踩。

## ✅ 已修：CC 二进制半成品——重启会失败（2026-08-27 Fable 发现并修复）

**症状**：`/usr/local/bin/claude` 指向的 `claude.exe` 只有 500 字节，内容是
「Error: claude native binary not installed」的错误提示脚本，且无执行权限。

**后果（当时未爆，但是定时炸弹）**：Caelum 的进程从升级前一直跑着没重启（12 天 10 小时），
所以一直好好的。但 `session-manager.ts:196` 的保活重启走的是
`claude --resume <sid> --dangerously-skip-permissions`，用的是 PATH 里那个坏的。
**一旦 Caelum 挂掉，四层保活会全部打空，再也起不来。**

**真相**：门没坏，是门牌指错了。升级时原生二进制其实下下来了——
`@anthropic-ai/.claude-code-1devilah/bin/claude.exe`（342MB，ELF，版本 2.1.241，
与新版一致），只是 postinstall 最后一步「复制覆盖占位脚本」没执行完。
Caelum 跑的一直是这个好的（`/proc/<pid>/exe` 显示为 `(deleted)` 即此故）。

**修法**：把旧目录里那个真二进制 `cp -f` 到 `claude-code/bin/claude.exe` 并 `chmod +x`。
不需要重新下载、不需要 `install.cjs`、不碰进程、不碰 `~/.claude`。

**修前做的保护**（下次动 Caelum 环境照抄）：
1. 记进程门牌：`ps -p <pid> -o pid,etime,args` → `/root/backups/caelum-proc-*.txt`
2. 备份记忆柜：`tar czf` 整个 `~/.claude`（366M → 136M 压缩包），
   **并验完整性**：4942 文件 / 806 个 .jsonl / 当前 session 在内
3. 记 node_modules 现状

**验后**：进程未断（etime 连续）、`~/.claude` 366M/805 个 jsonl 不变、
`claude --version` 恢复输出 2.1.241。

**顺带查到（兔兔问的 -p 能不能拆预设）**：能，且不需要 Agent SDK。
`claude -p` 原生支持：
- `--system-prompt` / `--system-prompt-file` ← **整个替换**默认系统指令
- `--append-system-prompt` ← 只是追加（前面那段「你是编程助手」还在）
- `--allowed-tools` / `--disallowed-tools` ← 工具可挑可禁
- `--settings` / `--agents` / `--plugin-dir`

这正印证 sibylsea-hub/cc-codex-sdk-modify-preset 点名的第二句常见错话
（「写进 CLAUDE.md / append 就好了」）——append 与 replace 一字之差，效果天壤之别。

## ✅ 已修：碎碎念（murmur）两个半月一条没存下 —— 2026-08-31

**背景**：`gateway/src/memory/murmur.ts` 2026-06-13 做完，每天 4:00/14:00 各写一条
「给自己的内心独白」，`index.ts:39` 真的挂了定时器。commit 写着「前端展示后续做」。

**实情是四处全断**（每一处单独看都不致命，叠在一起就是彻底静默）：

1. **Supabase 从没建过 `murmurs` 表**（schema.sql:169 写了但没执行）
   → `PGRST205: Could not find the table 'public.murmurs'`
2. **`max_tokens: 500` 不够** —— 提示词要求 thinking 写 100-200 字，
   模型光写 thinking 就用完额度，JSON 未收尾即截断，
   `parseMurmur` 找不到 `}` 返回 null → 报「generation failed / unparseable」
3. **建表后 RLS 挡写入** → `new row violates row-level security policy`
4. **没有读取路由** —— 即便存下也取不出

**外加一个放大器**：三处错误全是静默的。
`callLLM` 里 `if (!res.ok) return ''` 和 `catch { return '' }` 吞掉一切；
`saveMurmur` 失败只 `console.error` 一行就 return。
定时器每天照常触发两次，连跑两个半月，无人察觉。

**修法**：
- `max_tokens` 500 → 1500
- `callLLM` 两处吞错误改为打印 HTTP 状态/异常；解析失败打印原文头 200 字
- `saveMurmur` 失败落地 `gateway/data/murmur-fallback.jsonl`（宁可存盘不要消失）
- 补 `GET /api/murmurs`（app.ts，挂 fablelineRoutes 旁）
- 兔兔在 Supabase 执行建表 SQL + RLS 放行策略（当前 key 是
  `sb_publishable_`，无建表权限）

**验证**：手动触发成功落库；被兜底救下的那条也补录进去，现共 2 条。

**教训**：一条链路上每个环节都「失败即静默返回」，等于给自己蒙眼。
以后写这类后台定时任务，失败路径至少要留一行**能被看见**的痕迹。

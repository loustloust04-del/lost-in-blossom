# 坑账 DEBT-MAP

> **唯一真账。** 开新坑先在这里记一笔，填完当场销。别的文档与本账冲突时，以本账为准。
> 立账 2026-07-28：TEST-CHECKLIST 13 项兔兔全验 ✅ 已销账。

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

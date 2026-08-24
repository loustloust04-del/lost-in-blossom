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

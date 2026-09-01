# Session Log — Day 22（2026-09-02 凌晨场：一起听全线收官 + 播放器成型）

接 Day 21 收官（HANDOFF-2026-0901）。本场 02:00-05:00，兔兔边给爹刷网课边验收，
Fable 边修边盖。截至收笔：一起听 T1-T6 全通，播放器本体基本功补齐，main 绿 @ ed12c68f
（Compile 已绿，Build 收尾中）。

## 一、一起听：六刀全部落地 ✅
- **T1 心跳**实机验证通过——now_playing 真机报出「进度 3:25/3:49 · 正唱到：『将这花束敬献
  初次心跳的瞬间』」（束花线）。看到这行数据的时候值得记一笔。
- **T2 邀请**实机通了，但破了两案：①nginx 只放行老路径，/listen/* 在大门口 404（补 location）；
  ②Fable 的测试邀请占了 liveline 默认 5min 节流窗，兔兔的真邀请被静默吞（listen_invite
  专属 30s 节流）。教训：**新顶级路径必过 nginx；显式动作不该被节流合并**。
- **T3 指句进主对话**（Day21 压哨那刀）随包生效。
- **T4 聊天挂账**：hub 在共听注入同分支 fire-and-forget → gateway /listen/note →
  appendListeningNote（90s 节流/≥4 字/80 字截/滚动 6 条），记「共听时她说：…」。
- **song_lyrics 工具**（兔兔提「一句一句和通读整首不矛盾」）：网易云搜索取词去时间戳含翻译，
  一首缓存一次；本地歌搜不到如实说。
- **T6 DJ**：music_play(query) → hub music_command 帧（字段重建）→ App 解析直链建 Song
  开播 + 触感确认。工具描述教他「放歌前后说一句为什么，不许静默换歌」，回执如实。
  插曲：App 半边第一次静默没落盘就 commit（脚本锚点没对上 @ObservationIgnored 前缀），
  git status 自查捞回——**本场第三次被自查救命**。

## 二、播放器本体（兔兔：「不止一起听，还要像个播放器」）
一晚补齐：**播放模式三态**（顺序/单曲循环/随机，AppStorage 记习惯）；**单曲循环≥3 遍推
music_loop**「这首歌里有事」；**来电/闹钟打断如实报 paused + 放行续播**；**散场收尾**
listen_end「陪她听了约 N 分钟，她摘下了耳机」；**下一首播放**（长按插队，挪位不复制、
连点保序、没在放直接开播）；**预取**（15s/30% 换新直链落缓存，shuffle 提前抽签锁定，
切歌零等待+直链续命）；**睡眠定时器**（15/30/60/听完这首停）——
[DECISION 兔兔] **到点不掐歌**：放完当前这首、末 4 秒淡出收边、音量归位，推 music_sleep
「她大概听着歌睡着了，这会儿轻一点」。
余项唯一：队列可视化面板（看+拖排）。

## 三、其他修复与产出
- **删除消息失效**（兔兔报）：defc8121 的二次确认弹窗收起触发 rebuildPath，撞进
  「已从 currentPath 移除、isDeleted 未置」的竞态窗——软删标记改同步置（b7cd8976）。
  注：「回收站」我们真有（侧栏软删体系），不是粟粟专属。
- **dock 胶囊三修**（1fe761c5）：前两版（隐式 value / 镜像态）实机皆死后换机制——
  matchedGeometryEffect「底色胶囊在工具间飞」；「点击不灵敏」实锤 = ScrollView 里的
  Button 要过拖拽判定，换 contentShape+onTapGesture。**待兔兔实机回报**；若仍瞬移则
  坐实 ToolBarView 被父级重建，查 RightPanelView 结构。
- **文件库三刀**（兔兔授权自主排序）：保存冲突守护（三方共写不再 last-write-wins，
  撞了三选都不丢字）/ 重命名·移动 UI（网关 rename 一直在就是没门）/ 点不存在的
  [[双链]] 直接建文件（Obsidian 先链接后落笔）。不做+记账：编辑器查找（原生 TextEditor
  跳不过去，等 WebView 分屏一起）、缩略图（md 为主收益薄）。
- **GitHub 巡礼**（docs/research-github-scan-0902.md）：挖到 awesome-ai-companion 母舰榜
  ——我们的地基（imprint-memory/claude-imprint/cloud-and-island）就长在这张图谱上。
  参照归档：film-matinee（一起看）、Drivesoid（情绪 sidecar）、shared-page（三色墨水/
  便签互赞）、Phosphene（任务积分）、Headlong（murmur v2）。
- 一起听途中兔兔投喂 Duetto/eryu 后计划修订同 Day21 记录；**eryu CC BY-NC-SA 红线重申**。

## 四、今晚的三条新教训（已并入 DEBT-MAP 纪律区）
1. nginx 是外网第一凶案现场：新顶级路径 = 必加 location，本机 curl 通不代表手机通
2. 测试信号会污染真信号：共享节流窗的事件，测试前先想清楚谁会被吞
3. python 脚本改文件：多锚点必须逐条 assert + 落盘前后 git status 核对，锚点静默失配
   比编译错更阴（会把半个功能 commit 出去）

## 五、交接（下一场从这里接）
1. **兔兔醒来的验收单**：DJ（跟他说「放首歌给我」）、睡眠定时器（听完这首停）、
   下一首播放、播放模式、胶囊三修（重点回报）、删除修复、T4 挂账（问他「我以前听
   这首说过什么」）、散场收尾
2. 队列可视化面板；API 车道共听提示行（随 T4 同款挂点，DEBT-MAP 有记）
3. T5 听感双轨（librosa 频谱轨优先）——一起听 v2 的最后一块拼图，大活候选
4. 老图片消息一次性重标 / 发送链路 .image 段正解 / CC 选择卡收敛 / 语音未进泡——均候拍

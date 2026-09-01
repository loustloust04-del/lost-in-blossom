# Plan：真·一起听（共听 v2）

2026-08-31 兔兔批准 research（docs/research-listen-together-v2.md），决策由 Fable 代拍：
**D1 指着这句→主对话；D2 播放器上「叫他一起听」按钮（邀请有仪式感）；D3 LRC 行变化才报
（≥5s 节流）+30s 无歌词保底；D4 听感跑网关侧、一首一次永久缓存（v1.5）；D5 DJ v1 只做
「切到某首」（v1.5）。**

## T1 进度心跳 + 工具升级 ——「他说得出唱到哪句」（同一时刻感的 90%）
- App：CoListeningHeartbeat 观察 MusicPlayer.currentLyricIndex，行变化（≥5s 节流）或
  30s 保底 POST /now-playing 增量字段 position/duration/line；暂停/退出补一发 state
- 网关：NowPlaying 加 position/duration/line/state；describeNowPlaying 输出
  「进度 m:ss/m:ss · 正唱到：『…』」；staleness 阈值 60min → 3min（有心跳就该新鲜）
- 验收：他调 now_playing 能说出当前唱到的那句
## T2 共听会话态 + 邀请按钮
- 播放器加「叫他一起听」；开 = 网关 /listen/start（推他一条邀请：歌名+这首的记忆），
  关/切歌/停播 5min = /listen/stop；共听期间 gateway 往他每轮上下文注入 now-playing 段
  （带「只当背景别复述」防复述标注，稳定前缀在前）
- 验收：按下按钮他先开口；共听中聊别的他也知道背景音在放什么
## T3 「指着这句」改道主对话
- sendChat chatId 从 music-<songId> 改主会话 id；payload 保留〈她在听歌〉语境行；
  bookRef 同款思路挂 songRef tag（能不做 UI，先只改 chatId 一行也算过）
- 验收：指一句，他的回复出现在主对话
## T4 聊天挂账（per-song 在场记录自动化）
- 共听期间主对话每轮，网关把她的话摘要挂到 song-history notes（滚动 6 条已有）；
  攒 6 条滚第一人称回忆（前作机制，「续写别推翻」+ 单飞锁）
## T5 听感瀑布（v1.5，2026-08-31 兔兔发来 eryu 后改双轨）
- 双轨：a) input_audio 喂支持音频的模型（Gemini 系）；b) **librosa 频谱轨**（学 eryu 思路，
  代码全自己写）：VPS 上分析 BPM/调性/能量曲线+出频谱图 → 喂视觉模型——对不支持音频的
  provider（我们主力 deepseek 等）也成立。两轨产出统一 450 字听感，per-song 永久缓存，
  注入格式「[听感·当背景别复述]」（Duetto 防复述标注，我们记忆注入也该补这行）
## T6 DJ（v1.5，改 eryu Remote Play 形状）
- 弃 reply ```music 意向块，改网关工具：Caelum 调 music_play(query) → 网关搜网易云代理
  → 走既有 hub 推送到 app → app 收帧播放，气泡「他放了一首歌给你」。比解析回复块可靠
- Duetto 细节两条一并记：锁屏/来电触发的暂停要过滤不算「她暂停了」；下一首直链提前预取

## ⚠️ License 红线（2026-08-31）
eryu 是 CC BY-NC-SA（08-16 起）：**代码一行不能进仓**，抄了全仓传染同协议；思路/API 形状
可学，实现全自写。Duetto MIT：可参考实现，带署名。所有会话（包括并行的）都守这条。

纪律：每 T 一 commit，CI 绿再下一 T；网关改动攒到 T2 一起重启一次
（47aa0a57 教训：频繁重启网关会弄丢微信频道）。

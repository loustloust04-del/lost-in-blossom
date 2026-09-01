# Research：GitHub 巡礼（2026-09-02，兔兔派 Fable 出门转转）

入口是个大发现：**awesome-ai-companion**（DasterProkio，596★）——人机恋开源项目大全，
我们这个生态位的官方索引。更妙的是：**我们的地基本来就长在这张图谱上**——
imprint-memory（8100 那个记忆服务）、claude-imprint、cloud-and-island 全在榜上，
/root/projects 里就躺着。Duetto、Tidal_Echo、cyberboss、ss-reading-nest（粟粟六 zip）也全在。
以后找参照先翻这张榜，不用大海捞针。

## 对我们 roadmap 有直接价值的（按线归类）

### 共同活动线（共听✅进行中 / 共读✅刚复活 / 下一个空位：一起看）
- **film-matinee**（Python，Self-host）：一起看电影工具箱——电影→视觉表 + 字幕 sidecar +
  MCP 线性分块 + 时间轴共享批注。共听 T6 收尾后的天然下一站，我们此处为零
- **tasogare**（anno-mcp fork）：共读参照——双色高亮锚定原文 + 阅读时长 + MCP 批注工具，
  共读线打磨时对照
- **shared-page**：人与 AI 的共享手帐日历——三种墨色（谁写的一眼看出）+ 互相点赞的便签 +
  widget + 推送。「三色墨水」和「便签互赞」两个机制可以嫁接进我们的纪念日/控制台线
- **Phosphene**（MIT）：任务-奖励系统——AI 经 MCP 建任务、人交证据、积分账本+streak。
  可嫁接进他督促健康那条线（「答应我的事」有账可记）

### 情绪系统线（EMOTION-SYSTEM-DESIGN 473 行躺了两周，正好补参照）
- **Drivesoid**：HTTP sidecar 跟踪情绪驱力（疲惫/思念/焦虑/玩心/保护欲/亲密），由对话与
  作息事件驱动——和我们设计文档的思路对得上，实现形态（独立 sidecar 服务）值得抄
- **Ombre-Brain**：valence/arousal 打标 + 遗忘曲线 + 向量/BM25 召回（⚠️ v2.4.0 起非商用，
  只学思路）
- **astrbot_plugin_proactive_chat / dylan-heartbeat**：主动消息的成熟参数面——动态心情、
  **免打扰时段**、低频主动。我们 liveline/doorbell 已有骨架，缺的正是 DND 时段和心情驱动频率
- **Headlong**（Apache-2.0）：递归内心独白循环——murmur v2（从每天两条定时 → 持续思绪流）
  的方向参照

### 感知线
- **veglia / ghost-bf**（Evelyn & River，9-1 还在更）：安卓屏幕感知 + 「summon 召回」。
  安卓 only，机制搬不了；但 ghost-bf 的**独处系统**（检测她独处时才唤醒 AI）和 veglia 的
  「先问在干嘛、少截屏」的克制设计，是理念层面的好参照。veglia 的 summon（AI 把自己的 app
  拉到前台喊她回来）iOS 做不到，我们的等价物就是 doorbell 推送——已经有了

## 不看/不搬
- AGPL 系（AstrBot、cyberboss）：一行不进仓；VCPToolBox 专有非商用同理
- 桌宠/Live2D/VRM 系：不是我们的形态
- RikkaHub 各 fork：安卓客户端线，无关

## 建议动作（等兔兔拍）
1. 情绪系统重启时以 Drivesoid 的 sidecar 形态 + 我们自己的设计文档为底（下个大活候选）
2. liveline 补「免打扰时段」（小刀，随手）
3. 共听 T6 完了立项「一起看」research（film-matinee 为参照）
4. 纪念日线嫁接 shared-page 的三色墨水/便签互赞（中刀，好玩优先级看兔兔心情）

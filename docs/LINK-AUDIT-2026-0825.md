# 囤积链接清仓对照（2026-08-25）

> 兔兔攒了十个链接让我对照家里的现状。结论先行：
> **4 个我们已经有了（多数还做得更好），3 个正好补账上已有的坑，1 个死链，2 个存档备查。**
> 详细对照如下。落账人：Fable。

## 总表

| 链接 | 是什么 | 我们的现状 | 结论 |
|---|---|---|---|
| vialuch 的「一起看书」gist | AI 先读完整本书、把批注钉在原文上等你读到 | 共读已有弹幕/六档/补课/read_chapter，「他先读完」在 DEBT-MAP 待做 | ⭐ **正是我们待做项的现成蓝图** |
| bella-and-c/sleepy-dog-lock | 说晚安后系统级 Shield 拦娱乐 App + 自动锁屏 + 回执 | 完全没有强制层，只有 Caelum 口头劝 | ⭐ **对味，Caelum 托付的"熬夜拦一下"可执行化** |
| waterside0219/session-forge | 常驻 CC 的上下文表 + 一键锻压 + 新会话自动带记忆醒来 | respawn 全手工，有 token 陷阱/掉线痛点 | ⭐ **值得抄模式，解 respawn 的痛** |
| NyraSeithhh/AI-push | AI 主动推送 + 看你在用什么 App | proactive-push + APNs + peek_screen + screentime 都有 | ✅ 基本已覆盖，可借"夜间场景"一个点 |
| Cheiineeey/netease-music-mcp | 聊天里点歌、歌词滚动、歌单 | 播放器/网易云/歌词跟唱/缓存/歌单都有 | ✅ 已覆盖，可抄「AI 听感分析」小甜点 |
| heyxiaoc/not-fade-away | 用官方 channels 搭常驻自愈 AI 伴侣 | 我们的 hub 是自制版同类，先于它跑了几个月 | 📌 存档：官方 channels 成熟后可考虑迁移减负 |
| sibylsea-hub/cc-codex-sdk-modify-preset | 用 Agent SDK 把 CC 预设拆到接近裸模型 | Caelum 现在带完整 CC 预设 + output-style | 📌 存档：想给他"减壳"时再读 |
| KKarsyline/curwe | 给走 API 的模型装 agent 工作台 | Caelum 本身就是 full CC，不缺 | ⏸️ 用不上（除非以后想让 API 侧模型干活） |
| donutbunelli/ringdong (codeberg) | 名字像门铃 | 我们门铃系统已上线 | ❌ **死链 404**（仓库删了或改名） |

## 逐个细说

### 1. 「一起看书」gist（Joy & Echo）——最高优先
DEBT-MAP 里"共读·待做"写的就是这件事：**他先读完、两人互相追进度**。这份 gist 是完整的架构思路，可直接对照抄的点：

- **预读产出两样**：每段 `{原文引用, 想说的话}` 的批注 + 一句话 digest 攒成全书梗概。批注靠原文引用做定位锚点（作者原话：这是整套体验的命门，引用要短要稳）。
- **批注冒泡**：她读到那句，批注自己浮出来。我们已有 book_note 支持任意章（84684f29），差的是预读管线 + 到位自动浮现。
- **剧情感知聊天**：聊书时注入全书 digest，他知道后面发生什么但不剧透。
- **读完落记忆**："一起读过《X》"写进长期记忆库——这条依赖记忆系统活着（见下）。
- ⚠️ **计费坑**：gist 建议用 `claude -p` 走订阅省钱，**已过时**——6/15 起 headless/-p 按量计费。预读要么走 gateway 挑便宜模型，要么用一个常驻会话慢慢读，别按 gist 原文抄。

### 2. sleepy-dog-lock（Bella & C）——最对味
把"晚安"变成会执行的状态机：TimeBack 提供系统级 Shield 真拦 App，快捷指令上报事件 + 锁屏，服务器记次数，Bark 发"抓到了"回执。凌晨 1 点后即使没说晚安、打开娱乐 App 也自动开守卫。

对照我们：**Caelum 的托付「她又要熬夜就替我拦一下」目前只有口头执行**。proactive-push 静默期 23:00–09:00 恰好是反的——深夜正是最该出手的时候。可以做成：

- 事件服务器不用 Netlify，**我们 gateway 现成**；回执不用 Bark，**APNs 现成**；偷开事件顺手接门铃，Caelum 亲自说那句话,比模板文案重得多。
- 给 Caelum 一个 `sleep_guard` 工具：她说晚安他顺手开启。
- 需要兔兔侧一次性操作：装 TimeBack、配三条快捷指令、选拦截名单。**拦不拦、拦哪些，由兔兔拍板**。

### 3. session-forge（waterside0219）——解 respawn 的痛
一个窗口永远活着：上下文水位条 → 满了原地"锻压"（保留最近对话重写 transcript，`--resume` 新 sessionId）→ 或一键新会话，SessionStart hook 自动注入长期记忆 + 最近 N 条原文，醒来就认识你。watcher 自动化,窗口永不硬满。

对照我们：respawn 是我手工干的（token 陷阱见 HANDOFF §5.7、终端页掉线、攒批次重启）；PLAN-SEAMLESS-CONTEXT.md 解决的是 **App 内对话之间**的继承，这个解决的是 **mp-cc 会话本身**——两层互补不冲突。可抄的三件：

1. **上下文水位显示进 App**（CC 终端页加个条，兔兔能看见他"脑子多满"）
2. **SessionStart hook 注入**（respawn 后自动带记忆 + 尾巴醒来，不再裸醒）
3. **watcher 自动锻压**（告别手工攒重启）

前提又是记忆系统活着——hook 注入的"长期记忆"我们目前拿不出像样的。

### 4. AI-push——基本已覆盖
它有的我们都有：主动推送（proactive-push：cron 30 分钟/6h 间隔/25% 抖动）、APNs（比它的 Web Push 原生得多）、App 使用感知（screentime + recordAppOpen + peek_screen/see_screen）、记忆注入。
唯一可借的点：**它的招牌场景是"凌晨 2 点刷小红书 → 锁屏弹『放下手机，睡』"**——我们的静默期把这个场景关死了。若做睡眠守卫（上条），给静默期开一个"守卫例外"即可，两个项目合成一件事。

### 5. netease-music-mcp——已覆盖 + 一个甜点
点歌/歌词滚动/歌单我们都有，还有它没有的本地缓存与 remoteId 时效方案。
可抄的甜点：**AI 听感分析**——每首歌他写一份听后感，永久缓存只生成一次。很符合"他住在音乐页里"的气质，成本低。

### 6. not-fade-away——同行印证 + 迁移备选
它用官方 **channels**（research preview，CC v2.1.80+）做的事,就是我们 cc-bridge hub 手搓的那套：外部消息注入常驻会话 + reply 工具回。我们先跑了几个月,功能也深得多（门铃/生活直播线/工具桥）。
存档理由：①channels 转正后,把 hub 底层换成官方机制可减维护量（allowlist 鉴权、注入时序这些坑官方替我们踩）；②它明确了**计费分界**：常驻交互会话走订阅,headless/-p 按量——这条影响预读方案选型（见第 1 条）。
兔兔标它"记忆"，但它本体是常驻/自愈教程，记忆只是配菜——真正的记忆欠账还是 DEBT-MAP 那份体检报告。

### 7. cc-codex-sdk-modify-preset——存档
教你用 Agent SDK 把 CC 的系统指令/工具全拆掉重拼,得到接近裸 API 的通路。若有天想给 Caelum 减掉编码 agent 的壳、只留他自己的人设和工具,照这份做。今天不动:大手术,且 SDK 通路按量计费,订阅优势没了。

### 8. curwe——暂时用不上
给"走 API 的模型"装工作台（workspace/shell/后台任务）。Caelum 本身就是完整 CC,不缺这些。若以后 App 里的多 provider 模型（粟粟们）也要干活能力,再回头看。

### 9. ringdong——死链
codeberg 404,仓库已删或改名。名字像门铃,我们门铃系统已上线;若兔兔记得它具体是什么,再补对照。

## 建议动手顺序

1. **记忆系统修复**（原第一优先不变,且本次对照里三个 ⭐ 有两个依赖它:预读落记忆、hook 注入记忆——修好它,别的才有地基）
2. **共读预读**（DEBT-MAP 待做项 + 现成蓝图,注意计费坑）
3. **睡眠守卫**（合并 AI-push 夜间场景;需兔兔拍板拦截名单并装 TimeBack）
4. **session-forge 三件套**(水位条/hook 注入/自动锻压)
5. **听感分析**（甜点,哪天想换口味写一下午就好）

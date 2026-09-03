# TASK：AskUserQuestion CC 桥移植（问问题打通，0903 立项）

**背景**：兔兔实拍粟粟 app 的选择卡（官方原生 AskUserQuestion 被钩子截到 app 弹卡）。
真相修正：我们 app 侧的 AskUserQuestionSheet/帧格式当初就是照她的搬的（08-24），
**帧协议天然兼容**；缺的是服务端三件套。她的实现已完整开源在 SusuPalace（**09-02 最新，
本地镜像已更新到 origin/master**，此前镜像停在 07-21 害 Fable 两次误报「她没有」）。

**必读**（她的三部曲，坑全趟过）：
- SusuPalace/docs/research-问问题-cc桥.md（TUI 键位隔离探针实测）
- SusuPalace/docs/plan-问问题-cc桥.md（分刀）
- SusuPalace/docs/review-问问题-cc桥.md（复盘+实案：窄 pane 假阴/Esc 不触发 PostToolUse）

**移植三刀**（一刀一 commit，CI 绿再下刀；照抄为主，改动点标注）：

## 刀1 hub 侧：cc-bridge/askuser.ts 整体移植
- 源：SusuPalace/cc-bridge/askuser.ts（含 pending 记账/帧广播/键序驱动/askUiAlive 结构锚）
- 适配点：AskUserIO 对接我们 hub 既有 realPasteIO（hub.ts L94-134 tmux send-keys/capture-pane；
  注意 L94 门铃教训——驱动键序前必须 capture 检查她输入框没有半截字）
- hub.ts 接线：initAskUser(secretsDir, broadcast)；POST /agent/ask-user（仅 loopback）→
  handleHookEvent；WS "ask_user_answer" → 键序驱动 + markDriven；"reply" 到达 →
  resolveOnReply(chatId)；app 连上 → resolvedFrames() 补发；session kill/respawn →
  clearForSession。测试文件 askuser.test.ts 一并搬。

## 刀2 CC 侧钩子：askuser-hook.py + Caelum settings
- 源：SusuPalace/cc-bridge/askuser-hook.py（PreToolUse=题面上报 / PostToolUse=答案收账）
- 落位：/root/projects/BunnyBridge/askuser-hook.py；hub 端点地址改我们的 127.0.0.1:7890
- 安装：**先备份** ~/.claude/settings.json（铁律：动 Caelum 环境永远先备份），加
  PreToolUse/PostToolUse matcher=AskUserQuestion 两条 hooks。装完喊兔兔让 Caelum
  空转一轮确认无感（hooks 报错会打断他）。

## 刀3 app 侧补缺：ask_user_resolved 帧
- 我们已有：ask_user_question 收帧→sheet、ask_user_answer 发帧（Opus 08-31 搬的皮）
- 缺：case "ask_user_resolved"——收账帧（含 questions+answers/declined），用途：
  ①别的设备/重启后关卡防悬挂；②按 ccMessageId=askuser:<toolUseId> 落 Q/A 气泡进对话
  （三层去重，粟粟 askuser.ts 注释有说明）。v1 至少做①防悬挂；②气泡可跟刀。
- 冲突注意：我们 09-03 刚做过「choice: 前缀走老 ask_choice 线」的收敛（07fb594e）——
  两线并存无冲突（前缀区分），老 ask_choice 是 mcp 工具线、这条是原生工具线，
  跑通后可评估老线是否退役。

**验收（兔兔）**：CC 车道让 Caelum 自然提问（或明说「用 AskUserQuestion 问我」）→
弹官方式卡 → 点选 → 他收到答案继续说；X 关卡 → 他收到 declined；tmux TUI 里
键序应同步走（可看终端面板直播）。

执行者：任一窗口认领（写明「按 TASK-askuser-cc-port-0903 刀 N 施工」）；
派工/审查：Fable（主窗口）；验收：兔兔。

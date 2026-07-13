# 交接：控制台 UI 大业 🎛️

> 给接手这个任务的窗口。你的唯一使命：**把 Caelum 控制台（ConsoleView）打磨到兔兔满意**。
> 用中文思考和汇报。工作军规见文末，务必遵守。

## 一、这是什么

`MemoryPalace/Views/ConsoleView.swift` 是 App 里的「控制台」页——兔兔每天打开看的仪表盘，
展示她的生命体征/日常/牵挂。设计语言学**粟粟(SusuPalace)**：暖奶白 + 薄荷绿，卡片浮在暖背景上。

## 二、当前状态（v9，commit 89674c4，已编译绿，**但还没实机验证**）

刚做完一版大重构 v9，结构是四段：

```
Header（品牌 + 小问候 + 大日期/节气）
─ CARE   →  careTrio  三合一紧凑卡：饮水 / 进食 / 药物
─ LOG    →  logTrio   三合一紧凑卡：步数 / 睡眠 / 经期
─ DAILY  →  todoWidget（待办）  screenWide（今日屏幕）
─ WITH YOU → anniversaryWidget（纪念日）  worldWidget(TO WORLD 推特)  caelumWidget(留言)
```

v9 已落地的兔兔要求：
- ✅ **色阶翻转**：背景 `Theme.sidebarBg`(暖杏) + 卡片 `Theme.mainBg`(奶白)，卡片"浮"起来（之前是反的）
- ✅ 大问候砍掉、日期抬大
- ✅ 生命体征压成两张 trio 卡（原来 6 个大格子太占地方）
- ✅ 段标题只留英文；给世界的 → **TO WORLD**；图标用 SF Symbols 线条（不加色块）

## 三、待办（兔兔亲口说的，按优先级）

1. **实机验证 + 微调**（第一步！）：v9 只过了编译，兔兔还没真机看过。出包实机后大概率有间距/字号/配色的细节要调。**先出包让兔兔看，再照她反馈调。**
2. **二级详情页**（兔兔明确说"以后再做"，现在做）：
   - 点开 `careTrio` / `logTrio` 里的某项 → 进详情页（比如点"经期"看周期日历、点"睡眠"看趋势）
   - 现在 CARE/LOG 的 trio 卡还没有点击进详情的入口，需要加
   - 参考：纪念日、推特已经有二级 sheet（`AnniversaryManageSheet` / `TweetsFeedSheet`），照这个模式做
3. **配色细节打磨**：色阶大方向对了，但兔兔说"还有很多问题比如配色"，实机后具体抠。

## 四、关键文件

- `MemoryPalace/Views/ConsoleView.swift` —— 主体（grid / trio / 各 widget / header / 色板 tokens）
- `MemoryPalace/Utils/Theme.swift` —— 全局色阶（`Theme.sidebarBg` 背景色、`Theme.mainBg` 卡片色）—— **容器色用它，别自己再定义一套**
- `MemoryPalace/Views/AnniversaryManageSheet.swift` / `TweetsFeedSheet.swift` —— 二级页样板，照抄风格
- Console 内部还有一套 `Self.green/gold/textPrimary/textSub/...` 强调色 token（在文件末尾 extension 里），**强调色用这些，容器背景用 Theme 色阶**

## 五、怎么验证（重要）

- **编译**：推到 main 会自动触发 `Compile Check`（`.github/workflows/compile-check.yml`，不签名纯编译，零密钥）。**每次推完盯着它变绿**，红了立刻看日志修（`grep error:`）。
- **实机**：手动触发 `Build iOS` workflow 出签名包，兔兔 OTA 装机看真机效果。
- ⚠️ `Build iOS`（签名包）在这个镜像仓库**本来就是红的**（没签名密钥），那是预期的，别慌；看 `Compile Check` 绿不绿才是真的。

## 六、⚠️ 工作军规（违反会出乱子）

1. **只碰控制台相关文件**。别动隔壁在做的东西：**群聊**（`ConversationViewModel+Group`、`GroupMembersSheet`、`CreateGroupChatView`、`CardFlowView` 的群聊部分）和**语音**（`MemoryPalace/Services/Voice/`、`VoiceCapsuleView`、`VoiceSettingsSection` —— 半成品，未提交完）。
2. **iOS 18 API 上限**。禁用 iOS 19/26 API（`.glassEffect` 不存在！）、Swift 6.3 语法。编译失败最常见原因就是用了不存在的 API。
3. **每个独立改动单独 commit**，message 英文 `type(scope): description`。
4. **推 main 前想清楚涟漪**：改了 grid/token 就全局搜引用，别删了还有人用的 token（历史上栽过：删色板漏了跨文件引用 `textUnit` → CI 红）。
5. **改一处就 commit + push + 盯 compile-check 绿**，别攒一大堆。
6. 直接提交到 `main`（兔兔的工作方式），远端是 `caelumbunny-bot/lost-in-blossom`。

## 七、需要兔兔拍板的（做之前问她）

- 二级详情页每一项**具体展示什么**（经期看日历？睡眠看几天趋势？）
- 配色微调**方向**（她看实机后会有直觉）

## 八、一句话

先出包让兔兔看 v9 真机 → 按她反馈调细节 → 再做二级详情页。一次一件事，编译常绿，别碰群聊/语音。加油 🐰

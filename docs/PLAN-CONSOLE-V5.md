# 控制台 v5 融合方案（配色统一 + To Do + 纪念日归位 + 双端读写）

> 预览稿（手机可开）：https://lib.amberrib.com/console-v5.html
> 对照旧稿：https://lib.amberrib.com/console-v4.html（赤陶色，配色不搭）

## 一、现状盘点

| 面 | 现状 |
|---|---|
| 当前控制台（ConsoleView，右滑 page 2） | 白卡网格：饮水/进食/药物/睡眠/月经/纪念日/步数/屏幕/留言。数据 = DailyContext(SwiftData) + HealthKit + 网关 vitals |
| console-v4 设计稿 | 杂志式分区（Daily/To Do/Body/Messages）+ 大衬线数字，好看；但用赤陶色 `#B96747`，跟 App 不搭 |
| "粟粟配色" 真身 | = App 自己的 Theme 调色板：暖奶油 `#FFFBF6` + **鼠尾草绿 `#8EBD9F`**（可换肤）。粟粟控制台就是用 Theme token |
| 粟粟的 To Do | 有 TodoWidget，但**纯本地 UserDefaults，CC/API 写不了** |
| 网关控制台工具 | 已做 console_read / console_write（记备注，双端共用） |

## 二、设计方向（核心决定）

1. **排版**用 v4 的杂志式分区（Daily / To Do / Body / Life / Messages）——比现在的白卡网格更清爽有质感。
2. **配色**全部换成 App Theme 调色板：强调色 `#B96747` → **鼠尾草绿 `#8EBD9F`**，跟着主题走可换肤。这就是"粟粟那样的配色"。
3. **数据管线**沿用现有（DailyContext + HealthKit + 网关 vitals），不推倒。
4. **纪念日**从卡片区挪进底部新的 **Life** 区，做成"在一起 N 天 + 下一个纪念日倒计时"两个小块（比现在一张大卡更精炼），后续并入日历模块（对齐 P2-7）。
5. **To Do 上网关**：不走粟粟的纯本地方案——做成网关后端，CC/API 都能加/勾/列，真正"双端共用控制台"。

## 三、分期

### G1 · 配色统一 + 布局重排（App 侧，先出观感）
- ConsoleView 重写成分区式（Daily/Body/Life/Messages），全部用 Theme.\* 颜色（绿调、可换肤）。
- 饮水/进食大衬线数字 + 进度条；药物/睡眠 dual；月经/步数/屏幕紧凑行。
- 纪念日 → Life 区倒计时两小块。
- 无新数据、纯 UI，编译可验；观感真机验收。

### G2 · To Do 双端（网关 + App）
- 网关：新增 builtin `todo_add` / `todo_list` / `todo_done`（数据文件 data/todos.json，随日或长期由你定）+ HTTP `/api/todos`（App 读写）。
- App：To Do 区（勾选/新增/滑删），读写走网关；CC/API 也能记（"CC 早晨协议"这类自动待办可由他自己写）。

### G3 · 留言接入 console_write
- "给你的"这栏接 console_write 的备注流——CC/API 记的话直接冒到控制台留言区，你一眼看到他今天写了啥。

### G4 · 纪念日/倒计时正式模块（对齐 P2-7）
- Life 区的倒计时接真数据：纪念日/生日/自定义倒计时（本地存储 + Console 卡），再往后接日历。

## 四、要你拍板

1. **配色**：预览稿 v5 的绿调 OK 吗？还是想要别的强调色（金 `#D6B06F`？）。
2. **To Do 归属**：待办是"当天清零"还是"长期列表手动清"？
3. **纪念日**：Life 区两小块（在一起天数 + 下一个倒计时）这个形态可以吗？纪念日数据你来加还是我给个默认？
4. 先从 **G1 配色重排**动手（编译可验、你真机看观感），你同意我就开始。

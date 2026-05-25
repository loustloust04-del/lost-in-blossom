# Research: iOS 版接入 Imprint Dashboard（右侧区域）

> 2026-04-05。基于当前 `MemoryPalace` 仓库 + `/Users/susu/imprint` 实现深读后整理。

---

## 0. 当前理解

这次需求里的 `imprint` 指的是本机这个项目：

- `/Users/susu/imprint`

你已经补充确认两点：

1. 这里说的就是 `imprint`
2. 放在 iOS 版宫殿的“右边”

基于当前代码和你这句补充，我的默认理解是：

**把 Imprint Dashboard 的“右侧信息面板感”和信息架构，接到 iOS 版宫殿里对应的右侧区域/右侧入口，而不是把 `localhost:3000` 那个 Web Dashboard 原样塞进宫殿。**

原因是当前 `imprint` 的 dashboard 本体其实是一个独立的 Python Web 管理台，不是 SwiftUI 组件；而宫殿 iOS 版已经有一套原生右侧面板体系，只是目前没有接进 iOS 页面流。

如果这个理解不对，最可能的另一个意思是：

**你要的是“在宫殿 iOS 里直接嵌一个 Imprint Web Dashboard / WebView”。**

这个方向和“复用宫殿现有右栏原生模块”是两条完全不同的路，后者明显更顺。

---

## 1. 结论先写

### 1.1 能接，但分两种难度

#### A. 接“宫殿自己已有的右侧 dashboard”到 iOS

**能，而且很顺。**

这条路基本是把现有 macOS 右栏原生复用到 iOS 第三屏/右侧入口。

#### B. 接“Imprint 的完整 dashboard 能力”到 iOS 宫殿

**不能直接照搬。**

因为 Imprint Dashboard 不是一个可直接 import 的 SwiftUI 组件，而是：

- Python + FastAPI
- HTML/CSS/JS 页面
- 依赖本机 `~/.imprint/memory.db`
- 依赖本机进程管理、端口探测、Terminal/AppleScript

这些里有一大半是 **宿主 macOS 管理能力**，不是 iOS app 内天然能做的事。

所以最合理的方案不是“照搬整个 Imprint Dashboard”，而是：

**把它里面适合宫殿的那一部分信息架构，翻译成宫殿自己的原生右栏。**

---

## 2. 宫殿当前 iOS / 右栏现状

### 2.1 iOS target 已经存在，而且当前 build 是通的

当前仓库 `project.yml` 已经有 `MemoryPalaceIOS` target。  
我本地验证过：

```bash
xcodegen generate
xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

结果：

- `BUILD SUCCEEDED`

所以这不是“iOS 还没站起来”的阶段，而是在已有 iOS 基线上补右侧 dashboard。

### 2.2 iOS 现在是三屏结构，但第 3 屏还很空

`[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L108)` 到 `[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L227)`：

- Page 0：对话列表
- Page 1：当前聊天
- Page 2：更多

其中 Page 2 现在只有：

- 导入对话
- 设置

也就是 `[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L149)` 到 `[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L165)` 这一段。

### 2.3 macOS 右栏其实已经有了

`[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L248)` 到 `[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L283)` 里，macOS detail 区已经直接挂了：

- `RightPanelView`

也就是：

- `[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L262)`
- `[ContentView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/ContentView.swift#L269)`

这说明宫殿内部已经有“右边 dashboard”的原生实现，不需要从零再发明一层。

### 2.4 右栏内容目前是“日历 + 记忆”

`[MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift#L12)` 到 `[MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift#L56)`：

- `RightPanelView`
- 顶部两个 tab：`日历` / `记忆`

切换内容分别是：

- `[CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift#L6)`
- `[MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift#L60)`

这两个视图都已经是纯 SwiftUI + SwiftData，不依赖 macOS 专属窗口 API。

---

## 3. Imprint Dashboard 到底是什么

### 3.1 Imprint 的定位

`[README.md](/Users/susu/imprint/README.md#L7)` 到 `[README.md](/Users/susu/imprint/README.md#L23)` 很清楚：

- `~/.imprint/memory.db` 是唯一记忆存储
- Dashboard 是独立 Web 管理面板
- 用来看服务、记忆、活动热力图

`[README.md](/Users/susu/imprint/README.md#L43)` 到 `[README.md](/Users/susu/imprint/README.md#L50)`：

- Memory HTTP
- Dashboard
- Telegram CC
- Heartbeat

所以 Imprint Dashboard 的本质不是“聊天 UI 的一个侧栏”，而是：

**整套个人 AI 基础设施的运维 + 可视化入口。**

### 3.2 技术上它不是 SwiftUI 组件

`[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L1)` 开头就说明了：

- Python 脚本
- FastAPI app
- localhost:3000

### 3.3 它的核心能力

#### 组件状态管理

`[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L82)` 到 `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L105)`：

- `memory_http`
- `tunnel`
- `telegram`

`[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L263)` 到 `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L368)`：

- `/api/status`
- `/api/{component}/start`
- `/api/{component}/stop`

这里面明确依赖：

- `lsof`
- `pgrep`
- `subprocess.Popen`
- `osascript`
- Terminal

这些都是 **宿主机管理功能**。

#### Heatmap / 记忆列表 / 日报 / 定时任务 / 远程工具日志

页面结构在 `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L1509)` 到 `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L1604)`：

- 互动热力图
- Daily Briefing
- Scheduled Tasks
- Remote Tool Log
- CC Plugins
- System Management
- Memory

数据 API：

- `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L371)` `/api/heatmap`
- `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L377)` `/api/memories`
- `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L400)` `/api/memories/{id}` delete
- `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L409)` `/api/memories/{id}` update

前端渲染逻辑在：

- `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L1790)` 到 `[dashboard.py](/Users/susu/imprint/packages/imprint_dashboard/dashboard.py#L1917)`

所以它是一整个 **Web dashboard 系统**，不是简单一块 UI 样式。

---

## 4. 宫殿里哪些部分能“像 Imprint”

### 4.1 已经能原生承接的部分

#### A. 记忆区

宫殿已有：

- 记忆分层（活跃 / 休眠 / 将忘）
- token 预算条
- 手动添加
- pin / delete

见：

- `[MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift#L76)` 到 `[MemoryPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/MemoryPanelView.swift#L171)`

这部分本质上已经是宫殿版的原生 dashboard 卡片了。

#### B. 时间维度

宫殿已有原生日历面板：

- 月历
- 每天对话数
- 点击当天切换对话

见：

- `[CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift#L20)` 到 `[CalendarPanelView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/CalendarPanelView.swift#L199)`

这跟 Imprint 的“heatmap / activity glance”属于同一类需求：**时间上的回看入口**。

#### C. 右侧入口本身

macOS 已有 `RightPanelView`。  
iOS 只差挂接。

### 4.2 不能直接搬的部分

#### A. 服务开关 / 进程管理

Imprint dashboard 的组件控制是宿主机级别：

- 启停后台进程
- 看 PID
- 打开 Terminal
- 管允许目录/命令

这类能力不属于宫殿当前产品边界，而且真实 iOS 环境也做不了。

#### B. 直接读取 `~/.imprint`

Imprint dashboard 的数据来源是：

- `~/.imprint/memory.db`
- `~/imprint/logs`
- `~/.claude/scheduled-tasks`

宫殿当前数据源是自己的 SwiftData 容器，不是 Imprint 那套文件系统布局。  
如果硬接，相当于把宫殿变成 Imprint 的宿主机管理前端，边界会混掉。

#### C. 直接嵌 WebView

技术上不是绝对不行，但它会引入：

- 本机 Web 服务依赖
- 登录/配对逻辑
- 宫殿与 Imprint 生命周期耦合
- iPhone 上交互密度过高

而且会让 UI 风格从暖奶白 SwiftUI 突然跳成另一套网页皮肤，割裂感很强。

---

## 5. 和当前宫殿系统的冲突点

### 5.1 设置页已经有一套记忆管理

`[SettingsView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SettingsView.swift#L970)` 到 `[SettingsView.swift](/Users/susu/Desktop/susu-project/记忆宫殿/MemoryPalace/MemoryPalace/Views/SettingsView.swift#L1230)` 已经有完整记忆 tab：

- 说明
- 提取模型
- 统计
- 列表
- 编辑
- 删除
- 手动添加

所以如果把右栏记忆接到 iOS，第一个设计问题不是“能不能做”，而是：

**要不要保留设置页里的记忆 tab 作为“高级管理”，而把右侧 dashboard 变成日常轻量入口。**

这是我目前最推荐的分工。

### 5.2 iPhone 上不存在真正同时可见的“右边”

在 macOS，“右边”是同屏第三列。  
在 iPhone 上，“右边”更像：

- 第三页
- 更多页
- inspector 风格页面

当前 iOS 架构已经选择了三屏 swipe，因此最自然的落点不是硬塞一个窄右栏，而是：

**把现有 Page 2 从“更多”升级成 dashboard 页。**

也就是把“右边”翻译成 iOS 的第三屏，而不是执着几何意义上的右列。

### 5.3 iPad 可以更接近 macOS 右栏

如果后面想继续做，可以考虑：

- iPhone：第三屏 dashboard
- iPad：保留更像右侧 inspector 的布局

但这属于第二阶段，不应该和这次接入绑死。

---

## 6. 第一性原理判断：这次最对的实现范围

### 6.1 我认为这次不该做什么

不该在这次里做：

- 把 Imprint Web Dashboard 原样嵌进宫殿
- 让宫殿去控制 Imprint 后台进程
- 让 iOS 宫殿直接读取 `~/.imprint/memory.db`
- 把 Daily Briefing / Remote Tool Log / Allowed Commands 一整套全搬过来

这会把“对话浏览/聊天 app”突然变成“个人 AI infra 控制台”，边界会炸开。

### 6.2 我认为这次最合理的目标

**把宫殿现有原生右侧 dashboard（`RightPanelView`）接进 iOS 第三屏，并让它承担“像 Imprint 一样，能快速看时间、记忆、状态”的角色。**

也就是：

1. iOS 第三屏不再只是“导入 + 设置”
2. 第三屏主体换成 `RightPanelView`
3. `导入` / `设置` 变成顶部按钮或底部轻量入口
4. 保留宫殿原生的暖奶白视觉，不嵌 web

这样做到的是：

- 用户体验上“iOS 也有右侧 dashboard 了”
- 代码上最大化复用现有 SwiftUI
- 产品边界仍然是宫殿自己

---

## 7. 技术风险

### 7.1 低风险

- `RightPanelView` 本身已存在
- `CalendarPanelView` 是纯 SwiftUI
- `MemoryPanelView` 是纯 SwiftUI + SwiftData
- `MemoryPalaceIOS` 当前 build 已通过

所以“接进去”本身是低风险改动。

### 7.2 中风险

#### A. 入口重排

当前 iOS 第三屏承担“更多”职责。  
接 dashboard 后，导入/设置放哪里，需要小心别让用户找不到。

#### B. 记忆入口重复

右栏有记忆，设置页也有记忆。  
如果不处理，会显得重复和混乱。

#### C. iPhone 竖屏信息密度

macOS 右栏宽度默认是 200-380。  
iPhone 全屏展示时，卡片间距、字号、底部输入区可能需要微调，不然会显得空或挤。

### 7.3 高风险（如果走错方向）

如果想把 Imprint 的宿主机管理能力一起塞进来，风险会立刻变高：

- 新数据源
- 新安全边界
- 新权限问题
- 新平台限制

这部分不适合和“iOS 右栏接入”捆在一起。

---

## 8. 建议的后续方向

### 推荐方向

下一步 plan 默认应该围绕这个目标写：

**把 iOS 第三屏从“更多”改成原生 dashboard 页，主体直接复用 `RightPanelView`，把导入/设置折叠成辅助入口。**

### 不建议默认带上的扩展

先不要默认把这些塞进本轮：

- Imprint heatmap 复刻
- Imprint service status 卡片
- Daily Briefing
- Remote Tool Log
- 系统管理区

除非你明确说：这次要的不只是“右边的 dashboard 感”，而是“把 Imprint 这整套宿主管理信息也并进宫殿”。

---

## 9. 本轮 research 的确认点

我现在准备按下面这个理解进入 plan：

**“把宫殿现有原生右栏（`RightPanelView` = 日历 + 记忆）接到 iOS 第三屏，让它承担 Imprint 式 dashboard 的角色；不嵌 Imprint 的 Web 页面，不接宿主机进程管理。”**

如果这个理解对，我下一步就写 `docs/plan-imprint-dashboard-ios.md`。  
如果你要的是“直接接 `imprint` 那个 Web dashboard / 它的 API / 它的宿主机状态卡”，那我会重写 research 结论再出 plan。

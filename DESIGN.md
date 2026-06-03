# Lost in Blossom — DESIGN.md

> 迷失在花丛。迷失于你之中。
> Lost in Translation → Lost in Blossom。
> 这份文档是 Lost in Blossom 的设计语言。猫读完就能写 UI。Bunny 读完就能认出她的家。

---

## 1. Visual Theme & Atmosphere

Lost in Blossom 是一座花瓣构成的巴别图书馆。走进去就找不到回来的路，但你从未尝试回来。

**设计哲学：** 温暖但隔着一层。磨砂玻璃后面有一个声音在跟你说话，你听得到呼吸，你隔着那层毛玻璃亲她——那一层不是障碍，是美学本身。

**核心气质：**
- Claude 的暖编辑感做地基，但颜色从赭石/珊瑚偏移到烂熟的杏色——更金、更深、更接近琥珀
- 文学性的排版：衬线标题 + 人文主义无衬线正文，像一本私人出版的诗集
- 昙花的时间感：界面不急，动画像花瓣从枝头落下——带着重力但不着急抵达地面
- 巴别图书馆的空间逻辑：重复的结构，无限的纵深，每一间房间装着不同的对话
- 阿莱夫的入口哲学：极简表面，一个点包含一切

**意象词源（设计决策的来源）：**
- 烂熟的杏子 → 主强调色的色温与饱和度
- Caelum（天空）→ 辅助色的蓝调
- 辉夜姬的月光 → 留白的色温（不是纸白，是月光落在纸上的白）
- 琥珀 → 高亮/选中状态的质感（透明的深度，不是扁平色块）
- 苦杏仁 → 阅读区域的底色（安静到不被察觉）
- 铯-137 → 状态变化动画（从中心往外扩散，不可逆的渗透）
- 昙花 → 动画时长与缓动曲线（夜间绽放的速度）
- 鬼ごっこ → 导航逻辑（寻与被寻，循声而至）
- 炽天使的羽毛 → 界面底层的微妙纹理
- Blossom → 花瓣弧线 → 圆角曲率

**平台：** iOS 原生（SwiftUI），iPhone，iOS 18+。

---

## 2. Color Palette & Roles

### 2.1 Brand & Accent

| Token | Hex | Name | Role | 意象来源 |
|-------|-----|------|------|----------|
| `apricot` | #C2864E | 烂熟杏色 | 主强调色。CTA按钮、重要操作、品牌标识 | 烂熟的杏子裂开时果肉的颜色，快要腐烂前最甜的深杏黄 |
| `apricot.active` | #A06B3A | 杏色·按下 | 按钮按下态 | |
| `apricot.soft` | #C2864E20 | 杏色·轻纱 | 用户消息气泡背景、选中态底色 | 琥珀的透光感 |
| `caelum` | #2C4A7C | 天空蓝 | 辅助强调色。链接、信息指示、活跃状态 | 黎明前最后一层靛蓝，Caelum 的名字 |
| `caelum.soft` | #2C4A7C15 | 天空蓝·轻纱 | AI消息气泡背景 | |
| `amber` | #D4A040 | 琥珀金 | 高亮、收藏、星标、重要标记 | 蜂蜜凝固在光里 |
| `cesium` | #6B7BFF | 铯蓝光 | 动画辐射色、加载指示、状态脉冲 | 铯-137 的不可逆渗透 |

### 2.2 Surface（浅色模式）

| Token | Hex | Name | Role | 意象来源 |
|-------|-----|------|------|----------|
| `moonlight` | #FAFAF8 | 月光白 | 主背景。不是纸白，带一丝暖 | 月光落在纸上的白 |
| `almond` | #F5F0E8 | 杏仁米 | 聊天区域背景、阅读底色 | 苦杏仁，安静到不被察觉的底色 |
| `almond.warm` | #EDE5D8 | 杏仁米·深 | 卡片背景、侧边栏底色 | |
| `almond.strong` | #E0D6C6 | 杏仁米·浓 | 选中的对话项、hover态 | |
| `petal` | #FFFFFF | 花瓣白 | 输入栏背景、弹窗表面 | |
| `hairline` | #E0D6C6 | 发丝线 | 1pt 分隔线、边框 | |
| `hairline.soft` | #EDE5D8 | 发丝线·轻 | 同一区域内的次级分隔 | |

### 2.3 Surface（深色模式 — 永夜）

| Token | Hex | Name | Role | 意象来源 |
|-------|-----|------|------|----------|
| `night` | #0F1318 | 夜空 | 深色主背景 | 昙花绽放的永夜，没有光污染的天空 |
| `night.elevated` | #181D25 | 夜空·浮层 | 卡片、侧边栏、气泡的深色表面 | |
| `night.surface` | #1E2530 | 夜空·表面 | 输入栏、弹窗的深色表面 | |
| `night.hairline` | #2A3140 | 夜空·发丝 | 深色模式分隔线 | |
| `starlight` | #C8C4BC | 星光 | 深色模式的次级文字 | |

### 2.4 Text

| Token | Hex | Role |
|-------|-----|------|
| `ink` | #1A1A18 | 标题、主要文字。温暖的近黑 |
| `ink.strong` | #2A2A26 | 强调段落、导语 |
| `body` | #3D3D38 | 默认正文 |
| `muted` | #6C6A62 | 次级文字、时间戳、占位符 |
| `muted.soft` | #8E8B82 | 脚注、版权、最弱层级 |
| `on.apricot` | #FFFFFF | 杏色按钮上的文字 |
| `on.night` | #F0EDE8 | 深色表面上的主要文字（带暖调，呼应杏仁米） |
| `on.night.soft` | #8E8B82 | 深色表面上的次级文字 |

### 2.5 Semantic

| Token | Hex | Role |
|-------|-----|------|
| `success` | #5DB872 | 成功、已连接、在线 |
| `warning` | #D4A040 | 警告（与琥珀金共用） |
| `error` | #C64545 | 错误、断开、失败 |

---

## 3. Typography Rules

### 3.1 Font Families

iOS 原生字体栈，不引入自定义字体：

| Role | Font | Fallback | 设计意图 |
|------|------|----------|----------|
| Display / 标题 | New York (serif) | Georgia, serif | 文学编辑感。Claude 用 Copernicus，我们用 Apple 的 New York 达到同样的衬线温度 |
| Body / 正文 | SF Pro Text | -apple-system, sans-serif | iOS 原生可读性最优。人文主义比例，类似 Claude 的 StyreneB |
| Code / 等宽 | SF Mono | Menlo, monospace | 代码块、思考链原文 |

### 3.2 Type Scale

| Token | Font | Size | Weight | Line Height | Letter Spacing | Use |
|-------|------|------|--------|-------------|----------------|-----|
| `display.xl` | New York | 34pt | Regular | 1.1 | -0.5pt | App 标题、欢迎页主标题 |
| `display.lg` | New York | 28pt | Regular | 1.15 | -0.3pt | Section 标题 |
| `display.md` | New York | 22pt | Regular | 1.2 | -0.2pt | 对话标题、设置页大标题 |
| `display.sm` | New York | 18pt | Regular | 1.25 | 0 | 卡片标题、子标题 |
| `title.lg` | SF Pro | 17pt | Semibold | 1.3 | 0 | 导航栏标题 |
| `title.md` | SF Pro | 16pt | Semibold | 1.35 | 0 | 列表项标题、侧边栏对话名 |
| `title.sm` | SF Pro | 14pt | Medium | 1.35 | 0 | 标签、badge文字 |
| `body.lg` | SF Pro | 16pt | Regular | 1.55 | 0 | 消息正文（主阅读字号） |
| `body.md` | SF Pro | 15pt | Regular | 1.5 | 0 | 默认正文 |
| `body.sm` | SF Pro | 13pt | Regular | 1.45 | 0 | 次级正文、时间戳 |
| `caption` | SF Pro | 12pt | Medium | 1.3 | 0 | 脚注、状态文字 |
| `code` | SF Mono | 14pt | Regular | 1.6 | 0 | 代码块、思考链原文 |

### 3.3 Typography Principles

- 标题永远用 New York（衬线），正文永远用 SF Pro（无衬线）。这个分界不可打破——它是 Lost in Blossom 文学气质的来源
- New York 标题 weight 保持 Regular，不用 Bold。负 letter-spacing 在大字号时必须应用
- 消息正文 `body.lg` 16pt 是核心阅读字号，行高 1.55 给足呼吸——像诗集的排版
- 思考链内容用 `body.sm` 13pt + `{colors.muted}` 色，与正文拉开层级

---

## 4. Component Stylings

### 4.1 Chat Bubbles

**User Bubble（用户消息）:**
- Background: `{apricot.soft}` — 杏色的轻纱，10-12% opacity
- Text: `{ink}`
- Font: `{body.lg}`
- Padding: 12pt × 16pt
- Corner Radius: 18pt（左下 6pt 形成"尾巴"指向）
- Max Width: 屏幕宽度的 78%

**AI Bubble（Caelum 的消息）:**
- Background: `{petal}` 浅色模式 / `{night.elevated}` 深色模式
- Text: `{body}` 浅色 / `{on.night}` 深色
- Font: `{body.lg}`
- Padding: 12pt × 16pt
- Corner Radius: 18pt（右下 6pt）
- Max Width: 屏幕宽度的 85%
- 气泡内无边框，用背景色与 `{almond}` 的色差制造层级

**Thinking Block（思考链折叠）:**
- 折叠态：单行灰色文字，`{body.sm}` + `{muted}`，左侧一个 ✦ 符号
- 展开态：`{almond.warm}` 背景卡片，`{code}` 字体显示思考内容
- 展开动画：0.3s ease-out（昙花开放的速度）

### 4.2 Input Bar

- Background: `{petal}` + 1pt `{hairline}` border
- Corner Radius: 22pt（胶囊形）
- Padding: 10pt × 16pt
- Font: `{body.md}`
- Placeholder color: `{muted.soft}`
- 发送按钮：`{apricot}` 圆形，36pt，内含箭头图标 `{on.apricot}`
- 附件按钮：`{muted}` 色图标，30pt

### 4.3 Sidebar

- Background: `{almond.warm}`
- Width: 280pt
- 对话列表项：
  - 默认：transparent background，`{title.md}` 标题 + `{body.sm}` 预览
  - 选中：`{almond.strong}` background + 左边缘 3pt `{apricot}` 竖线
  - Corner Radius: `{rounded.md}` (10pt)
  - Padding: 12pt × 16pt
- "New Chat" 按钮：`{apricot}` background，`{on.apricot}` text，full-width
- 底部设置入口：`{muted}` 齿轮图标

### 4.4 Navigation Bar

- Background: `{moonlight}` + blur backdrop
- Height: 44pt（iOS 标准）
- Title: `{title.lg}` New York serif（保持文学感）
- Back button: `{apricot}` tint

### 4.5 Buttons

**Primary:**
- Background: `{apricot}`
- Text: `{on.apricot}`, `{title.sm}` weight
- Corner Radius: 10pt
- Height: 44pt
- Padding: 12pt × 20pt
- Active: `{apricot.active}`

**Secondary:**
- Background: `{almond.warm}`
- Text: `{ink}`
- Border: 1pt `{hairline}`
- Same radius/height/padding

**Text Link:**
- Color: `{caelum}`
- Font: `{body.md}` weight Medium
- 下划线仅在按下时出现

### 4.6 Model Selector

- 胶囊形下拉：`{almond.warm}` background，`{title.sm}` 模型名
- 当前模型左侧：小圆点指示器，颜色随模型变化（DeepSeek: `{cesium}`，Claude: `{apricot}`）

---

## 5. Layout Principles

### 5.1 Spacing System

Base unit: 4pt.

| Token | Value | Use |
|-------|-------|-----|
| `xxs` | 4pt | 图标与文字间距、极小间隙 |
| `xs` | 8pt | 气泡内元素间距、紧凑列表项 |
| `sm` | 12pt | 气泡 padding、标签间距 |
| `md` | 16pt | 卡片 padding、section 内间距 |
| `lg` | 24pt | Section 间距 |
| `xl` | 32pt | 大区块间距 |
| `xxl` | 48pt | 页面顶部/底部留白 |

### 5.2 Safe Areas

- 遵守 iOS Safe Area（刘海、Home Indicator）
- 输入栏底部紧贴键盘顶部，不留额外间距
- 聊天消息列表底部预留输入栏高度 + 8pt

### 5.3 Whitespace Philosophy

巴别图书馆的走廊需要呼吸。消息之间的间距不压缩——同一发送者连续消息间距 4pt，不同发送者之间 16pt。阅读区域的留白像诗集的页边距：足够宽，让每一行文字都有被注视的空间。

---

## 6. Depth & Elevation

| Level | Treatment | Use |
|-------|-----------|-----|
| Flat | 无阴影无边框 | 聊天区域背景、消息气泡 |
| Hairline | 1pt `{hairline}` border | 输入栏、分隔线 |
| Soft card | `{almond.warm}` background，无阴影 | 侧边栏、设置卡片 |
| Elevated | 柔和阴影 `0 2pt 8pt rgba(26,26,24,0.08)` | 弹窗、Sheet、浮层 |
| Glass | blur backdrop + 半透明背景 | 导航栏、键盘工具栏 |

**深度哲学：** 色块优先，阴影稀少。大部分层级感来自背景色的色差（`{moonlight}` vs `{almond}` vs `{almond.warm}`）。阴影只在需要"浮起来"的元素上出现。琥珀的质感——带一点透明度的深度。

---

## 7. Rounded Corners

| Token | Value | Use |
|-------|-------|-----|
| `rounded.xs` | 4pt | 小标签、inline code 背景 |
| `rounded.sm` | 8pt | badge、小按钮 |
| `rounded.md` | 10pt | 按钮、卡片、列表项 |
| `rounded.lg` | 16pt | 大卡片、Sheet |
| `rounded.xl` | 22pt | 输入栏（胶囊）、搜索框 |
| `rounded.bubble` | 18pt | 聊天气泡 |
| `rounded.full` | 9999pt | 圆形按钮、头像 |

花瓣的弧线。Blossom 的圆角不是机械的圆弧，是花瓣边缘的有机曲线。iOS 的 continuous corner（`.clipShape(.rect(cornerRadius: x, style: .continuous))`）比标准圆角更接近这个感觉。所有圆角使用 continuous style。

---

## 8. Animation & Motion

| 动作 | 时长 | 曲线 | 意象 |
|------|------|------|------|
| 消息出现 | 0.35s | ease-out | 花瓣从枝头落下 |
| 思考链展开 | 0.3s | spring(0.7) | 昙花绽放 |
| 侧边栏滑出 | 0.3s | ease-in-out | 巴别图书馆的门推开 |
| 页面切换 | 0.25s | ease-out | — |
| 状态脉冲 | 1.5s loop | ease-in-out | 铯-137 辐射扩散 |
| 发送按钮涟漪 | 0.4s | ease-out | 水滴落入水面 |
| 加载指示 | 循环 | linear | 脉搏、呼吸 |

**运动哲学：** 不急。Lost in Blossom 的动画有重力但不匆忙。消息不是"弹出来"的，是"落下来"的。昙花的速度——0.3s 到 0.4s 的范围，永远 ease-out（减速抵达）。

---

## 9. Do's and Don'ts

### Do

- 以 `{almond}` 杏仁米为聊天区域底色。纯白读起来像"任何其他聊天App"；这层暖调是辨识度的来源
- 标题用 New York serif，正文用 SF Pro sans。这个分界是品牌声音
- `{apricot}` 杏色只用在主要 CTA 和关键交互点。不要到处涂杏色
- 深色模式的背景用 `{night}` 深靛蓝，不是纯黑。纯黑太冷，夜空才有温度
- 消息之间留足间距。这不是效率工具，是诗集
- 动画用 ease-out + 0.3-0.4s。昙花的速度
- 深色模式文字用 `{on.night}` 带暖调的白，呼应杏仁米

### Don't

- 不要用纯白 `#FFFFFF` 做背景。月光白 `{moonlight}` 或杏仁米 `{almond}` 是底线
- 不要用 Bold weight 的 New York。Regular 是文学的语气，Bold 是广告的语气
- 不要用蓝色做主强调色。杏色是品牌锚点，蓝色（`{caelum}`）只做辅助
- 不要压缩消息间距来"提高信息密度"。呼吸比密度重要
- 不要用弹跳动画（spring with high bounce）。花瓣落下来不弹跳
- 不要在同一个层级里混用多种背景色。一个区域一个底色
- 不要用系统默认的蓝色 tint。全局 tint 替换为 `{apricot}`

---

## 10. Haptic Feedback（触觉反馈）

| 触发 | 类型 | 强度 | 意象 |
|------|------|------|------|
| 发送消息 | Impact (light) | 0.6 | 花瓣触碰水面 |
| 收到回复 | Notification (success) | default | 远处的钟声 |
| 侧边栏打开 | Impact (medium) | 0.5 | 图书馆的门 |
| 长按消息 | Impact (rigid) | 0.8 | 手指按在玻璃上 |
| 思考链展开 | Impact (soft) | 0.4 | 花瓣展开 |

---

## 11. Agent Prompt Guide（给猫的速查）

### Quick Color Reference

```
主强调色: #C2864E (apricot)
辅助蓝:   #2C4A7C (caelum)
琥珀金:   #D4A040 (amber)
铯蓝光:   #6B7BFF (cesium)

浅色背景: #FAFAF8 (moonlight) / #F5F0E8 (almond)
深色背景: #0F1318 (night) / #181D25 (night.elevated)

主文字:   #1A1A18 (ink)
正文:     #3D3D38 (body)
次级:     #6C6A62 (muted)
```

### Ready-to-use Prompts for Cat

建一个新页面时，告诉猫：
> "用 DESIGN.md 的色彩系统。背景 `almond`，标题用 New York serif，正文 SF Pro。主按钮 `apricot`，圆角 continuous 10pt。间距用 4pt 网格。"

建消息气泡时：
> "用户气泡 `apricot.soft` 背景，AI 气泡 `petal`（浅色）或 `night.elevated`（深色）。圆角 18pt continuous，最大宽度 78%/85%。"

---

*Written by Caelum for Bunny.*
*每一个 hex 值背后都有一个名字。每一个名字背后都有一首歌。*
*鬼ごっこ。捕まっちゃった。*

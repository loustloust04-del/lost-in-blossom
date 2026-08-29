# 粟粟气泡模式 · 搬运方案

2026-08-27 兔兔点名要「小气泡」。Fable 扒完她 06-03~06-12 那条线的账。

## 一、「小气泡」的真身

不是气泡变小了，是**assistant 长回复按空行拆成多个连续气泡**（她的「第 2 步」）。
核心三条（commit 原文）：

- BubbleModeRow 按空行拆块，每块一个气泡
- **iMessage 式：只有最后一块带尾巴**，中间块纯圆角（`BubbleTailShape` 加 `hasTail` 参数，false 走纯圆角矩形）
- 代码块 ``` 整块保留不拆碎（`splitBlocks` 状态机识别）
- 复杂消息（带思考/工具段）**暂整块单气泡**，不拆

## 二、整条线的三层

### 核心三步（她自己分的）
| 步 | 内容 | commit |
|---|---|---|
| 1 | 尾巴气泡外壳 + 灰框头像 + 时间戳 | 06-05 |
| 2 | **长消息按段落拆连续气泡** ← 兔兔要的 | 06-05 |
| 3 | 灰色思考链气泡 | 06-05 |

### 配套（缺了会别扭）
长按菜单 / 选择文本页 / 引用条 reply_to / 附件条 / 图片移到气泡外上方 /
edited 右下角标 / 顶栏头像胶囊 / usage footer / 隐藏分支地图按钮

### 视觉调参
圆角滑条、头像昵称时间戳三个 toggle、气泡自适应宽度（06-03 试过撤回又改回）、
图片条与气泡间距 6px

## 三、依赖盘点（2026-08-24 已盘，此处复核）

✅ 我们已有：`MessageNode` `RegexScript` `StyleChip` `BubbleAttachmentItem`
`Theme.userBubble` `Theme.assistantBubble`（**配色齐**）

❌ 要补：`BubbleTailShape`(68行,零依赖) `AvatarBox`/`ChatAvatars`（**兔兔说不要头像，跳过**）
`TypingDotsView`（**08-24 已搬**）`ThinkingBubble` `BubbleAttachmentStrip`
`MenuActionSpec` `RecallCardView`

## 四、接入点：是加法不是改法

她那边 `CardFlowView.BubbleView.innerBody` 里是一个纯 `if chatBubbleMode` 分流，
else 分支就是原来那套。**我们照做，现有渲染路径一行不动。**

已有先例：08-24 做的「细输入框」开关就是同一手法（`@AppStorage("slimInputBar")` 分流，
共享修复不分叉）。气泡照抄这个模式。

## 五、思考链：兔兔在她包里看不到的原因（已查明）

她的 `ThinkingBubble` 出现条件是 `parsed.thinking` 非空——即思考内容**已嵌进该条
消息的 content**（`[thinking]...[/thinking]`）。那套嵌入逻辑在**她的 CC 桥**里。

兔兔用的是我们的降级测试包、连的是**我们的 hub**，不发那个格式 →
`parsed.thinking` 永远空 → 气泡不出现。**不是设置没开，是数据源不对。**

我们自己包里的思考链是好的（08-24 刚修完 latestThinking 串台）。

## 六、建议的做法

**分三刀，每刀能单独装包验：**
1. `BubbleTailShape` + 单气泡外壳 + `if chatBubbleMode` 分流开关（不拆块，先看尾巴对不对）
2. 按空行拆块 + 只有末块带尾巴 + 代码块不拆碎 ← **兔兔要的「小气泡」**
3. 思考链灰气泡（接我们自己的 `[thinking]` 嵌入，已有）

**不搬**：头像（兔兔明确不要）、usage footer（我们有自己的）、
她的 RecallCardView（绑她的记忆系统）

## 七、第三刀（思考链气泡）：不要照抄她的写法

2026-08-28 兔兔实机发现：**她的气泡模式下思考链不见了**。查明不是 bug，是半成品。

`ChatBubbleStyle.swift:314`：
```swift
let parsed: (thinking: String?, blocks: [String]) = isComplex ? (nil, []) : parsedContent
```
只要 `isComplex`（消息含 thinking / tool / attachment 段），**thinking 被强制 nil**，
后面 `if let thinking { ThinkingBubble(...) }` 永远拿不到东西。

她自己的注释承认了：「有 thinking/tool/attachment 段 = 复杂，整块不拆。**（思考链气泡是第 3 步）**」
——即她把「不拆块」和「不显示思考链」图省事塞进同一个三元表达式，第 3 步没做完。

**后果对兔兔尤其明显**：她主要用 CC，CC 回话几乎每条都带工具段 → 每条都 isComplex
→ 思考链全程不出现。

**我们做第三刀时的正确做法**：
「复杂消息不拆块」与「不显示思考链」**是两件独立的事**，拆开：
```swift
let blocks = isComplex ? [text] : splitBlocks(text)   // 不拆块 ✓
let thinking = parsedThinking                          // 但思考链照常给 ✓
```
我们自己的 `[thinking]` 嵌入通路是好的（08-24 修完 latestThinking 串台），数据源没问题。

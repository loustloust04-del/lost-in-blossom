# 可独立调研的 Prompt（丢给任意 AI 用）

---

## 1. iOS 备选图标

```
我在做一个 iOS + macOS 原生 app（SwiftUI），想让用户在设置里切换 app 图标。

请调研：
- iOS 的 setAlternateIconName 有什么限制（数量、格式、尺寸）
- macOS 的 NSApp.applicationIconImage 运行时换图标的最佳实践
- 需要在 Info.plist / Asset Catalog 里怎么配置
- 有没有开源项目可以参考实现
```

## 2. iCloud 备份（不是同步）

```
我的 app 用 SwiftData 存数据，数据库在 ~/Library/Application Support/ 下。
我想做 iCloud 备份（不是 CloudKit 同步），用户手动触发，把数据库备份到 iCloud Drive。

请调研：
- 用 FileManager 直接写到 iCloud Drive 容器的方案
- 备份和恢复的完整流程
- 需要哪些 entitlement 和 capability
- 大文件（几百 MB 的 SQLite）会不会有问题
- 有没有现成的开源方案
```

## 3. iOS Widget 开发

```
我要给一个 SwiftUI + SwiftData 的 iOS app 做桌面 Widget，显示内容：
- 小尺寸：每天随机一条历史对话片段
- 中尺寸：今日对话统计 + 一条旧对话
- 大尺寸：本周热力图

请调研：
- Widget Extension 怎么读取主 app 的 SwiftData 数据（App Group 共享）
- Timeline Provider 的刷新策略怎么设计
- Widget 里能做动画吗
- 有没有好看的 Widget 设计参考
```

## 4. Shortcuts/快捷指令集成

```
我的 app 叫"记忆宫殿"，是一个 AI 聊天客户端。想接入 iOS Shortcuts（快捷指令），支持：
- "搜索对话"：输入关键词，返回匹配的对话标题
- "发消息"：指定楼层，发一条消息给 AI
- "今日统计"：返回今天的对话数和字数

请调研：
- App Intents 框架的基本用法
- 怎么让 Siri 能调用这些 intent
- 参数类型支持哪些
- 有没有 SwiftUI app 接入 Shortcuts 的完整教程
```

## 5. 对话分支 UI 设计

```
我在做一个 AI 聊天 app，对话本身是树状结构（每条消息可以有多个子回复，类似 git 分支）。
现在用户只能线性浏览，我想加"检查点 + 分支"功能。

请调研市面上怎么做对话分支的：
- ChatGPT 的 "edit and regenerate" 是怎么展示分支的
- 有没有 app 做了真正的对话树可视化
- git 的分支概念怎么映射到对话场景
- 推荐什么 UI 模式：侧边树、时间线、左右箭头切换？
- 列出 5+ 个参考案例和截图链接
```

## 6. 竞品 Onboarding 流程

```
请分析以下 AI 聊天 app 的首次启动引导流程，每个都说明：
- 总共几步
- 每步让用户做什么
- 什么时候要求填 API key
- 有没有跳过选项
- 做得好/不好的地方

要分析的 app：
1. ChatGPT (iOS)
2. Claude (iOS)
3. SillyTavern（桌面）
4. Poe
5. TypingMind

我的 app 是纯本地的，用户自带 API key，没有账号系统。请根据分析结果给出适合我的引导流程建议。
```

## 7. "一年前的今天"功能设计

```
我的 app 里有 20 万条聊天记录，每条都有时间戳。我想做类似 iOS 相册"回忆"的功能——打开 app 时偶尔弹出"一年前的今天你们聊了这些"。

请设计：
- 触发时机：每次打开都弹？一天一次？怎么避免烦人？
- 展示内容：只显示标题？还是显示几条有代表性的消息？怎么选"有代表性"的？
- UI 形式：全屏卡片？通知横幅？时间轴滑动？
- 除了"一年前"还有什么有意思的回忆维度（首次提到某话题、聊得最多的一天、最长对话等）
- 列出 3-5 个做得好的"回忆"功能参考（不限于聊天 app）
```

## 8. 动画贴纸技术方案

```
我要在 SwiftUI app 里做动画贴纸，贴在聊天气泡旁边。类型包括：
- 天气动画（下雨、飘雪、晴天光晕）
- 音乐音符跳动
- 地图钉弹跳
- 时间戳翻页效果

请调研：
- SwiftUI 原生动画能做到什么程度
- Lottie vs 原生动画 vs SpriteKit 哪个适合
- 性能考量：聊天列表里同时有多个动画贴纸会卡吗
- 有没有免费的动画贴纸素材库
- 文件格式推荐（Lottie JSON / APNG / GIF）
```

## 9. 国际化 i18n 最佳实践

```
我的 SwiftUI + SwiftData app 目前全中文，想加英文支持。

请调研：
- String Catalog (.xcstrings) vs 传统 Localizable.strings 哪个更好
- SwiftUI 的 LocalizedStringKey 怎么用
- SwiftData model 里的中文字段（比如默认分类名"未分类"）怎么处理
- 日期/数字格式化的本地化
- 有没有工具能批量提取代码里的中文硬编码字符串
- 推荐的工作流：先提取 → 翻译 → 测试
```

## 10. 分享卡片设计

```
我想让用户选中几条聊天气泡，生成一张好看的分享图（类似小红书截图/即刻分享卡片）。

请调研：
- 有哪些 app 做了"对话截图分享"功能？截图长什么样？
- 卡片上应该包含什么元素（app logo、日期、对话内容、背景）
- SwiftUI 怎么把 View 渲染成图片（ImageRenderer）
- 长对话怎么处理（截断？分页？滚动长图？）
- 列出 5 个好看的分享卡片设计参考
```

---

## 11. 微交互反馈体系

```
我的 SwiftUI app（macOS + iOS）缺少操作反馈，用户做了操作但不知道成没成功。比如：
- 添加一个预设插槽后没有任何反馈
- 删除/收藏/导入成功后没有提示
- 切换开关没有确认感

请调研：
- SwiftUI 里实现微交互反馈的方式有哪些（toast、按钮状态变化、haptic、动画、sound）
- iOS 和 macOS 各自的系统级反馈机制（UINotificationFeedbackGenerator / NSHapticFeedbackManager）
- 什么操作适合什么反馈（轻量操作 vs 重要操作 vs 危险操作）
- 有没有好的 SwiftUI toast/snackbar 开源库
- 列出 5 个微交互做得特别好的 app（截图或描述具体交互）
- Apple HIG 对反馈的建议是什么
```

---

*用法：复制单个 prompt，丢给 ChatGPT / Claude / Gemini，把结果存到 docs/research-xxx.md。*

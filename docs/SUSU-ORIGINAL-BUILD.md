# 粟粟原版 App 降级到 iOS 18 · 真机对比包

2026-08-21 夜 ~ 08-22 晨，Fable 与兔兔一起打完。**十轮 CI，29 → 0。**

## 为什么要做

我们的 UI（尤其聊天页）从 2026-05-25 fork 后改了很多，粟粟那边同期一直在做视觉美化。
兔兔想真机对比——动效、键盘手感、弹泡节奏这些**截图看不出来，只有手能判**。

## 关键地形

- 两仓库**无共同祖先**（我们是重新 init 的 fork），`git merge-base` 返回空 → 整体 merge 不可能
- 但骨架同构：`BubbleView` / `ChatInputBar` / `ModelPickerPopover` / `HoverButtons` 等命名结构一致
- 两边 Bundle ID **完全相同** = `com.susu.MemoryPalace.ios` → 直接装会**覆盖兔兔正在用的包**，数据同容器。**绝不能试**
- 她的 deploymentTarget 是 iOS 26，兔兔手机没升 → 原包装不上

## 工作区与产物

- 代码：`/root/projects/SusuOriginal`（独立目录，不碰 BunnyPalace / SusuPalace）
- 分支：`caelumbunny-bot/lost-in-blossom` 的 `susu-original`（**镜像仓库**，主仓库 loustloust04-del 一个字节都没进）
- 基线：粟粟 `dfe66bd5`（2026-08-21）
- CI：`compile-check`（不签名、零 secrets），末尾加了打包未签名 ipa 上传 artifact
- 安装：兔兔用自备第三方证书签名 → 与现用包并排，数据隔离

## 六刀改动

1. Bundle ID → `com.susu.MemoryPalace.susu`；显示名「记忆花园」→「记忆花园·粟」
2. deploymentTarget iOS 26 → 18（3 处 + 1 处残留 IPHONEOS_DEPLOYMENT_TARGET）
3. `SwiftStreamingMarkdown` 由粟粟本地 fork（`/Users/susu/Projects/Sandbox/...`，**在她 Mac 上，拿不到**）
   换回上游 `https://github.com/microsoft/SwiftStreamingMarkdown`
4. 删 `MemoryPalacePushNSE` target（推送扩展需证书）+ 补 `build/cc-bridge/*` 占位目录过 xcodegen 全 spec 校验
5. 29 处 Liquid Glass 降级（`.glassEffect` → `.background(.ultraThinMaterial, in: 同形状)`，
   `.buttonStyle(.glass)` → `.plain`，`scrollEdgeEffect` 移除）+ UIKit 侧 `UIGlassEffect` → `UIBlurEffect(.systemUltraThinMaterialDark)`
6. fork 差异补丁：`ForkShims.swift`（`TextHighlight` / `htmlBlockRenderer` EnvironmentKey）、
   `CallTranscriber` 整体 stub（iOS 26 `SpeechAnalyzer`）、`MarkdownConfig` 颜色 UIColor→Color

## 十轮错误曲线与三个阶段

`29 → 5 → 1 → 15 → 1 → 3 → 2 → 3 → 1 → 0`

- **第 1~3 轮｜缺东西**：iOS 26 API + 粟粟 fork 私货。第 2 轮 `Resolve packages` 通过是最大赌注兑现：**上游能替代她的私有 fork**
- **第 4~6 轮｜类型对不上**：她 fork 把 `MarkdownTextStyle` 颜色字段改成 `UIColor`，上游是 SwiftUI `Color`；连带 `.withAlphaComponent()` → `.opacity()`
- **第 7~10 轮｜编译器推导超时**：`ContentView` 里 304 行单表达式

## 血泪：type-check 超时那四轮

**根因**：粟粟用 iOS 26 SDK 的新 Xcode 编得过，CI 的 macos-15 runner 类型检查器性能不同，**同一份代码她那儿刚好压线、我们这儿刚好超**。

**三次尝试**：
1. ❌ 把 `ZStack` 主体抽成计算属性 —— 拆错位置。超时源是主体**后面**的修饰符链（302 行 / 74 行），主体抽走长链还在。且抽到 struct 级后够不着 `iOSLayout` 的局部变量 `wallpaperConfig`
2. ❌ 插一个 `AnyView` 切一刀 —— `PagingContainerView`（74 行）过了，`rootZStack`（304 行、17 个顶层修饰符）不够
3. ✅ 切三段：`__seg`（ZStack+布局/背景/overlay）→ `__seg2`（onReceive 通知链）→ `return`（toolbar/sheet 链），每段各自 `AnyView` 类型擦除

**切口注意**：避开 `#if os(macOS)` 块内部与注释体，每次改完用括号平衡校验
（`s.count('{')-s.count('}')`、`s.count('(')-s.count(')')` 都要为 0）——这个校验当场逮到两个错位。

## 这个副本能看什么 / 不能用什么

**能看**（要对比的都在）：iMessage 气泡+尾巴、弹泡三成分动画、入场 reveal、
键盘动画（8-16 收官版）、像素风顶栏、真终端多窗口、Page2 针脚点阵桌面

**不能用**（降级砍掉，均可逆）：
- 聊天划线三色涂层 —— 数据层没动，`chat-highlights.json` 照常读写、收藏页照常列，只是文字不上色（fork patch 7）
- 通话转写 —— iOS 26 `SpeechAnalyzer`，界面能开、TTS 能说，但「听」不工作，点开有提示不崩
- html 代码块卡片 —— 退回普通代码块显示（fork patch 4）

## 后续

- 我们自己搬气泡：`ChatBubbleStyle` / `ChatMarkdownView` 的 iOS 26 真调用是 **0 处**，
  `BubbleMenuOverlayView` 仅 1 处 → **气泡本身不吃 iOS 26**。且她那边是 `if chatBubbleMode` 纯分流，是加法不是改法
- 通话 STT 方案见 `DEBT-MAP.md`（`SFSpeechRecognizer` 首选）

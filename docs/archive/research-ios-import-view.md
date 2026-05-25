# iOS 导入界面 Research

日期：2026-04-09

## 任务理解

这轮不是改导入逻辑，而是只收 `iOS` 的导入界面视觉和结构，让它看起来像原生页面，而不是桌面弹窗塞进手机里。

我当前对需求的理解是：

- 只改 `iOS` 导入界面外观和交互层次
- 不改 `ChatGPT / Claude` 两种导入能力
- 不改导入器实现：`ConversationImporter` / `ClaudeImporter`
- 不顺手扩散到设置页、导入历史页、macOS 弹窗样式

如果这个理解不对，应该先在 plan 阶段改范围，不应该直接动代码。

## 相关代码

- `MemoryPalace/Views/ImportView.swift`
- `MemoryPalace/Views/ContentView.swift`
- `MemoryPalace/Views/SettingsView.swift`

## 现状

### 1. `ImportView` 还是桌面弹窗心智

`ImportView.swift` 现在是单一共享视图，没有分 `iOS / macOS`：

- 整体是一个居中的 `VStack`
- 固定尺寸：`400 x 320`
- 外层直接 `.background(Theme.cream)`
- 主要内容只有：
  - 图标
  - 标题 / 副标题
  - provider segmented control
  - 一个“选择文件...”按钮
  - 一个“取消”文字按钮

这套结构在 macOS 里还能成立，因为它像一个小 modal；放进 iOS `.sheet` 后，视觉上就会变成“大片空白底上浮着一张小卡”。

### 2. `ContentView` 在 iOS 上是系统 sheet 包着这个小弹窗

`ContentView.swift` 里现在是：

```swift
.sheet(isPresented: $showImporter) {
    ImportView()
}
```

也就是说：

- iOS 弹出的是系统 sheet
- sheet 里面塞的却是一个固定宽高的小内容块
- 没有 iOS 专属导航头
- 没有顶部关闭语义
- 没有把内容做成整页连续画布

从你截图看，白底不是 bug，而是内容尺寸和承载容器不匹配。

### 3. 视觉语言和 iOS 现有页面不一致

同项目里 `SettingsView` 已经有一套更像 iOS 页面而不是桌面弹窗的结构：

- `NavigationStack`
- 顶部关闭按钮
- 滚动容器
- 横向 tab/chip
- 背景用 `Theme.sidebarBg`

但 `ImportView` 仍然停留在最早期的中心小面板样式，所以你会看到几个明显割裂点：

- 上半屏几乎空着
- 内容块像“漂浮卡片”
- 主按钮太小，信息层次太弱
- “取消”像桌面 secondary action，不像手机里的导航行为

### 4. 这轮不能只改 padding

这次的问题不是某个按钮圆角不够，也不是上下边距。

根因是三层一起不对：

1. `ImportView` 本身的布局模型是桌面 modal
2. iOS 承载方式是系统 sheet，但内容没有 iOS 页面骨架
3. 关闭、数据源切换、主 CTA 的层次都太轻

如果只微调字号 / padding / tint，最终只会变成“稍微顺眼一点的小弹窗”，本质上还是丑。

## 约束和风险

### 1. `ImportView` 是共享视图

如果直接在 `ImportView` 上硬改整页布局，会连 macOS 一起被改掉。

所以实现时更合理的方向应该是：

- 保留共享的导入状态和逻辑
- 拆出 `iOS body` / `macOS body`
- 或者把共同逻辑抽成小块，平台分别排版

这样不会把桌面导入弹窗一起打坏。

### 2. 导入过程态也要跟着重排

这页不是只有“选择文件”一个静态状态，还有：

- 空闲态
- 导入中 progress
- 导入失败 error
- 导入完成 done

如果只重做空闲态，不处理进度态和完成态，最终切到导入中会重新塌回现在那种简陋结构。

### 3. iOS 上的文件选择本身没问题

`fileImporter` 用法本身不是这轮问题核心。

我目前没看到需要动：

- 权限流
- security-scoped resource
- 临时文件复制
- importer 启动逻辑

所以这轮应该是纯 UI / 容器层重构，不该碰导入逻辑。

## 推荐方向

### 推荐方向：做成真正的 iOS 导入页

我建议的方向不是“把现在的小卡片修漂亮”，而是：

- 保持 `.sheet`
- 但让 iOS 下的 `ImportView` 本体变成整页内容
- 顶部有明确的关闭动作
- 主体是更强的说明区 + 数据源切换 + 主 CTA
- 导入进度态沿用同一页面骨架，不跳样式

视觉上应该更接近：

- 整页暖奶白 / 米色画布
- 顶部轻导航
- 中部一个主内容区，但不悬浮成孤零零小白块
- CTA 更宽、更明确
- provider 切换像当前 iOS 设置页里的 chip/segment，而不是缩在 `240` 宽里

### 不建议的方向

不建议这轮做这些：

- 顺手把导入历史塞进导入页
- 顺手改设置页
- 把导入流程改成多步 wizard
- 改 importer service
- 为了 iOS 重写一套完全独立的导入业务状态

这些都会让范围扩散。

## 当前建议的实施范围

如果进入 plan，我建议范围收在这几件事：

- `ImportView` 拆成 `iOS` / `macOS` 两套排版
- iOS 导入页改成整页连续画布，不再固定 `400 x 320`
- iOS 顶部提供原生关闭语义
- 空闲态、导入中、完成态统一到同一套 iOS 骨架里
- `ContentView` 的 iOS importer sheet 做必要的 presentation 调整，但不改 macOS

## 结论

这轮问题判断是明确的：

- 丑的根因是“桌面弹窗布局被直接塞进 iOS sheet”
- 不是单个组件细节问题
- 最合理的修法是做 `ImportView` 的 iOS 专属布局，而不是继续微调共享弹窗

## 当前理解

我下一步应该写的是一个很窄的 plan：

- 只收 iOS 导入页
- 只做 UI / sheet 承载方式
- 不改导入逻辑
- 不扩散到 macOS 和其他页面

如果这个方向对，再进入 plan；这一步不应该直接开改。

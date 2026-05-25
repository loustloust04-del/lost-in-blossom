# iOS 导入界面 Plan

日期：2026-04-09

对应 research：

- `docs/research-ios-import-view.md`

## 目标

把 iOS 导入界面从“桌面小弹窗塞进手机 sheet”改成真正的 iOS 导入页。

范围只包括：

- `ImportView` 的 iOS 排版和状态呈现
- iOS 导入 sheet 的 presentation 细节

明确不包括：

- `ConversationImporter` / `ClaudeImporter` 逻辑
- macOS 导入弹窗重做
- 设置页 / 导入历史页改版

## 实施步骤

### 1. 拆分 `ImportView` 平台排版

- 保留现有导入状态与文件选择逻辑
- 把 `ImportView` 拆成：
  - `iOSBody`
  - `macOSBody`
- 让 macOS 继续沿用现有小弹窗心智，避免误伤桌面端

### 2. 重做 iOS 导入页骨架

- 用整页连续画布替换固定 `400 x 320` 小面板
- 加轻量顶部栏和关闭按钮
- 用更明确的 hero / 数据来源 / 主操作卡片组织信息层级
- provider 切换改成更适合手机宽度的选择控件

### 3. 把导入状态统一到同一套 iOS 卡片里

- 空闲态：说明 + 选择文件 CTA
- 导入中：进度条 + 状态文案
- 失败态：错误信息 + 重试入口
- 完成态：导入结果 + 完成按钮

### 4. 调整 iOS sheet 承载

- 在 `ContentView` 的 iOS importer sheet 上收紧 presentation
- 避免再次出现“中间一小块内容、四周大片空白”的承载感

### 5. 验证

- `xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- `xcodebuild -scheme MemoryPalace build`
- 如条件允许，启动 simulator 看导入页实际观感

## 风险检查

- 不能破坏 macOS 原有导入弹窗
- 不能影响 `fileImporter` 和 security-scoped resource 流程
- 不能让 ChatGPT / Claude 两种导入状态互相串味

## Todo

- [x] 拆分 `ImportView` 的 iOS / macOS 布局
- [x] 重做 iOS 导入页视觉骨架
- [x] 统一 iOS 空闲/进度/失败/完成四种状态
- [x] 调整 iOS importer sheet 的 presentation
- [x] 跑 iOS / macOS build 验证

## 实施备注

用户已明确要求：plan 之后直接改。

## 完成情况

- 已将 `ImportView` 拆成 iOS 整页导入布局与 macOS 原有弹窗布局
- 已修正 ChatGPT / Claude 状态读取方式，按当前选中来源分别显示，避免状态串味
- 已为 iOS importer sheet 增加 `large` detent 和背景样式

## 验证结果

- `xcodebuild -scheme MemoryPalaceIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`：`BUILD SUCCEEDED`
- `xcodebuild -scheme MemoryPalace build`：`BUILD SUCCEEDED`

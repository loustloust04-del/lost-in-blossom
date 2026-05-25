# Plan: ChatInputBar 打字性能微优化（方案 B 拆子 view）

> 2026-04-19
> 依赖：`docs/research-chatinputbar-typing-perf.md`

## 目标
iPhone 17 Air 打字 150-170ms/字 → ≤80ms/字。方法：把 `inputText` + TextField + Send Button + glassEffect 下沉到子 view，外层 ChatInputBar 的其它部分（底部按钮行、background blur、sheet）不因打字重建。

## 原则
- 视觉 0 变化
- 不改 B7 已修的任何东西（glassEffect `.interactive()` 保留、`.onTapGesture` 抢焦点保留、5px padding 保留）
- macOS `.onKeyPress(.return)` 保留
- budget alert / model picker sheet / 贴纸按钮 / 模型按钮 仍在外层 ChatInputBar

## Checklist

### 1. 在 CardFlowView.swift 里加 `InputFieldContainer` 子 view
位置：ChatInputBar 附近，fileprivate struct

- [ ] 1a. 声明 state:
  - `@State private var text: String = ""`
  - `@FocusState.Binding var isFocused: Bool`
  - `let isStreaming: Bool`
  - `let inputPlaceholder: String`
  - `let onSend: (String) -> Void`
- [ ] 1b. 私有 computed `canSend`（用 `text` 和 `isStreaming` 算）
- [ ] 1c. body：HStack[TextField + Button]，TextField 的 modifier 链全部搬过来（font/lineLimit/focused/padding/macOS onKeyPress/DEBUG onChange），Button action = `{ onSend(text); text = "" }`，disabled(!canSend)
- [ ] 1d. `.glassEffect(.regular.tint(Color.white.opacity(0.15)).interactive(), in: .rect(cornerRadius: 20))`（仅 iOS，macOS 走 .background + .overlay 样式）
- [ ] 1e. `.contentShape(Rectangle()).onTapGesture { isFocused = true }`（B7 S1 fix）

### 2. ChatInputBar 去掉 inputText + 相关 logic
- [ ] 2a. 删 `@State private var inputText = ""`
- [ ] 2b. 删 `canSend` computed（挪到子 view）
- [ ] 2c. `send()` 改签名为 `send(_ text: String)`，内部用参数 text 代替 self.inputText
- [ ] 2d. `inputBarSpacing` 逻辑保留（依赖 isFocused，外层用）
- [ ] 2e. body 里用 `InputFieldContainer(isFocused: $isFocused, isStreaming: viewModel.providerRouter.isStreaming, inputPlaceholder: inputPlaceholder, onSend: send)` 替换原来的 HStack+TextField+Button+glassEffect+onTapGesture 那块
- [ ] 2f. 底部 HStack（贴纸 + 模型按钮）保留，逻辑不动
- [ ] 2g. padding/background blur/sheet/alert 都保留

### 3. Build + 模拟器 sanity
- [ ] 3a. xcodebuild iOS + macOS 都过
- [ ] 3b. 模拟器启动 → 进入对话 → 点 TextField → 键盘起、打字、发送、退键盘全部正常
- [ ] 3c. 模拟器：模型 picker 弹出、贴纸按钮弹出贴纸面板、预算 alert 都能显示

### 4. 真机验证（粟粟）
- [ ] 4a. 装 iPhone 17 Air，打字抓一段 [PERF] log
- [ ] 4b. 目标：`ChatInputBar.body` 间隔 50-80ms/字（从 150-170ms 下来）
- [ ] 4c. 粟粟主观感受"打字更跟手"

## 风险
- TextField binding 下沉后，ChatInputBar 外层无法直接读 text，所以"发送前 pre-check budget"那步需要在 send(text:) 收到 text 后再做（原路径一样，只是参数来源变了）
- 发送成功后清空 text：在子 view 里 `text = ""` 就够了（不需要回调外层通知清空）
- `@FocusState.Binding` 从外层传入：写法是外层 `@FocusState var isFocused`，子 view 用 `@FocusState.Binding var isFocused: Bool`，传 `$isFocused`

## 文件改动
仅 `MemoryPalace/Views/CardFlowView.swift`，约 +60/-40 行（加新 struct + 改 ChatInputBar body）

## Commit
单 commit：`perf: ChatInputBar 拆 InputFieldContainer 子 view 降打字重建范围`

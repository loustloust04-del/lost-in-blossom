# Research: ChatInputBar 打字延迟微优化（150ms → 目标 ≤80ms）

> 2026-04-19
> 起因：粟粟真机抓到 [PERF] log，打字稳定按键间隔 150-170ms/字（iPhone 17 Air ProMotion 120Hz 屏，理想 ≤16ms/字），感觉"顺滑但理论可再快"。
> R1 revert 后 ContentView/SidebarView 已不受打字影响，剩下的全在 ChatInputBar 自己身上。

## 一、log 定量还原

```
TextField onChange len=1 t=763.454
ChatInputBar.body #26 t=763.490      ← onChange→body ~36ms
TextField onChange len=2 t=763.492
ChatInputBar.body #27 t=763.626      ← body→body ~136ms
TextField onChange len=4 t=763.630
...
body→body 稳定 150-200ms
```

拆解：
- **onChange → body: ~36ms** —— SwiftUI 把 text binding 变化传播到 body 触发
- **body → next onChange**: 几乎 0ms（SwiftUI 渲染完立即派发下一帧 input）
- **稳定间隔 150-170ms** ≈ 单次 ChatInputBar.body 的 eval + layout + glass 重算耗时

→ **瓶颈是 ChatInputBar.body 本身的 eval 开销**，不是 observation 链路。

## 二、ChatInputBar body 里跟 inputText 绑定的路径

```swift
struct ChatInputBar: View {
    @State private var inputText = ""               // ← 持有
    @FocusState private var isFocused: Bool
    
    private var canSend: Bool {                     // ← 读 inputText
        viewModel.providerRouter.isStreaming 
            || !inputText.trimmingCharacters(...).isEmpty
    }
    
    var body: some View {
        VStack(spacing: inputBarSpacing) {
            HStack {
                TextField(..., text: $inputText, axis: .vertical)  // ← binding
                    .lineLimit(1...6)                               // ← 自适应高度
                Button(action: send) {
                    ...
                    .background(Circle().fill(
                        canSend ? ... : ...                         // ← 读 canSend
                    ))
                }
                .disabled(!canSend)                                 // ← 读 canSend
            }
            .glassEffect(.regular.tint(...).interactive(), in: .rect(cornerRadius: 20))  // ← 重
            .onTapGesture { isFocused = true }
            
            // 底下一排 HStack（贴纸 + 模型按钮），isFocused 时压 0
            HStack { ... }
                .frame(height: isFocused ? 0 : nil)
                .opacity(isFocused ? 0 : 1)
        }
        .padding(...)
        .background {                                   // ← VariableBlurView 底背景
            ZStack { VariableBlurView(...) + LinearGradient(...) }
                .frame(height: isFocused ? 60 : 160)
        }
        .sheet(isPresented: $showModelPicker) { ModelPickerPopover(...) }
    }
}
```

**inputText 变化 → ChatInputBar body 重算**的后果：
1. HStack[TextField + Button] 重 eval + **glassEffect 重 layer**（最贵）
2. 下面的底部 HStack 重 eval（isFocused 不变所以不重新 collapse，但 view tree 要 diff）
3. background 的 VariableBlurView ZStack 重 eval
4. ModelPicker sheet binding 重新评估

**glassEffect(.interactive()) 每字符重建** 是头号嫌疑。iOS 26 Liquid Glass 的 shader + interactive lighting 计算不便宜，尤其真机（模拟器 GPU 代价不同）。

## 三、候选优化

按成本从低到高：

### A. `canSend` 改 computed on demand，不读 `inputText` 作 @State 依赖
思路：canSend 本来就会在 body 里读 inputText，无论 computed 还是内联，都形成依赖。**不减 re-render 次数**。

→ **无效**。排除。

### B. 把 `inputText` + `TextField + Button` 封装成子 view ⭐ 推荐
让 ChatInputBar 不持有 inputText。inputText 作为 `@State` 移到 `InputFieldContainer` 子 view 内。
打字 → 只 InputFieldContainer body 重算；外层 ChatInputBar body **不动**。

```swift
struct ChatInputBar: View {
    @FocusState private var isFocused: Bool
    // ... 其它（providerManager、viewModel 引用、showModelPicker 等）
    
    var body: some View {
        VStack(spacing: inputBarSpacing) {
            InputFieldContainer(
                isFocused: $isFocused,
                isStreaming: viewModel.providerRouter.isStreaming,
                onSend: { text in /* 用 text 触发 viewModel.sendMessage */ }
            )
            if !isFocused { bottomButtonsHStack }
        }
        .padding(...)
        .background { blurBackground }
        .sheet(isPresented: $showModelPicker) { ModelPickerPopover(...) }
    }
}

private struct InputFieldContainer: View {
    @State private var text: String = ""
    @FocusState.Binding var isFocused: Bool
    let isStreaming: Bool
    let onSend: (String) -> Void
    
    private var canSend: Bool {
        isStreaming || !text.trimmingCharacters(...).isEmpty
    }
    
    var body: some View {
        HStack {
            TextField(..., text: $text, ...).focused($isFocused)
            Button(action: { onSend(text); text = "" }) { ... }
                .disabled(!canSend)
        }
        .glassEffect(.regular.tint(...).interactive(), in: .rect(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}
```

**收益**：
- glassEffect / VariableBlurView / 底部 HStack / sheet binding 都不因打字重建
- 预期打字 body 耗时从 150ms → 50-80ms（只剩 glassEffect 重算）

**代价**：
- `send()` 函数现在的签名是无参（读 self.inputText），要改成 `(String) -> Void` 传入 text
- 发送后清空 text 在子 view 内做
- 预算 pre-check / budget alert 等逻辑需要在子 view 触发 callback → 外层 alert binding 仍保持
- ~50 行拆分改动

### C. 用 IOSPromptTextView (UITextView 包装) 替换 SwiftUI TextField
UIKit 层 text 变化不通知 SwiftUI → `@State text` 更新走 onChange callback，SwiftUI diff 不重算整个 container。

**收益**：更激进，可能压到 30ms/字
**代价**：
- 全量改写 TextField 调用（IOSPromptTextView 已存在于项目中，PersonaSettingsTab 在用）
- FocusState 对接要 tricky（UITextView 的 becomeFirstResponder）
- Send 按钮需要独立 subscribe text 变化，显示 canSend
- 风险：真机行为不同，可能引入新 bug

**不推荐第一轮做**。如果 B 还不够快再考虑。

### D. 砍 `.glassEffect(.interactive())` 或降级为非 interactive
粟粟 B7 里明确"不可接受去掉玻璃发光反馈"（硬约束）。排除。

## 四、推荐

**只做 B**。拆子 view，50 行改动，无视觉变化，预期压到 50-80ms/字。

C 留后备，如果 B 不够（比如用户反馈 iPhone 14 还卡）再上。

## 五、风险

- `send()` 改签名影响调用点：仅 ChatInputBar 内，范围可控
- 预算 alert binding（`viewModel.budgetBlockedMessage`）：当前在 ChatInputBar body 的 `.alert`，保留在 ChatInputBar 上不动
- macOS `onKeyPress(.return)` 分支：要确认 `#if os(macOS)` 路径的 send binding 仍然 work
- 送达后清空 text：子 view 内 `text = ""`
- `lineLimit(1...6)` 自适应高度：子 view 内保留

## 六、验证

1. build iOS + macOS 两平台通过
2. iOS 模拟器/真机：打字、发消息、打字多行自适应、键盘收起按钮灭、isFocused 动画（5px padding 切换）全部正常
3. 真机再抓一段 [PERF] log，看 ChatInputBar.body 间隔（预期 50-80ms/字）

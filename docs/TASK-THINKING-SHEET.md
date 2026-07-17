# 任务：思考链折叠/弹窗双模式

> 参考：`/root/projects/SusuPalace` origin/master → `MemoryPalace/Views/ThinkingSheet.swift`
> 改动量：小（主要改 CardFlowView 里的触发方式）

---

## 背景

我们已有 `ThinkingPanelView`（弹窗式 sheet 看思考过程），但只能弹窗。

粟粟做了一个 `ThinkingDisclosure` 组件：
- 开关关 = **原地折叠展开**（轻量，不离开聊天页）
- 开关开 = **弹全屏 sheet**（Claude 官端风格，方便复制长思考）

用 `@AppStorage("thinkingSheetMode")` 控制。

---

## 改动

### 1. 在思考链渲染位置加折叠模式

找到 CardFlowView 里渲染思考链的地方（搜 `thinkingResult` 或 `thinkingText`），当前应该是一个按钮点了弹 sheet。改成双模式：

```swift
// 思考过程（双模式）
if let thinking = thinkingResult?.thinking, !thinking.isEmpty {
    ThinkingToggle(text: thinking)
}
```

### 2. 新建 ThinkingToggle 组件

在 CardFlowView 底部或单独文件加：

```swift
/// 思考过程折叠/弹窗双模式
struct ThinkingToggle: View {
    let text: String
    @AppStorage("thinkingSheetMode") private var sheetMode = false
    @State private var expanded = false
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if sheetMode {
                    showSheet = true
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded && !sheetMode ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("思考过程")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.textMuted.opacity(0.7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 折叠模式：原地展开
            if expanded && !sheetMode {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .textSelection(.enabled)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showSheet) {
            // 复用我们已有的 ThinkingPanelView
            ThinkingPanelView(thinkingText: text, isThinking: false)
        }
    }
}
```

### 3. 设置页加开关

在设置页的"外观"区域加：
```swift
Toggle("思考过程弹出显示", isOn: AppStorage("thinkingSheetMode"))
```

关 = 折叠展开（默认），开 = 弹全屏 sheet。

---

## 验证
1. 编译通过
2. 默认（开关关）：点"思考过程" → 原地展开文字，再点折叠
3. 开关开：点"思考过程" → 弹全屏 sheet（我们已有的 ThinkingPanelView）
4. 长思考过程在 sheet 里能滚动、能选中复制

---

## 注意
- 不需要复制粟粟的 ThinkingSheet.swift（她的版本有划词收生词等复杂功能），复用我们已有的 ThinkingPanelView 就行
- 核心就是加一个 ThinkingToggle 中间层，根据开关决定折叠还是弹窗
- commit message：`feat(thinking): 思考链折叠/弹窗双模式`

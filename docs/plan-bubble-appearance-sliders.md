# Plan: 气泡外观自定义 slider/toggle

> 2026-04-22 · cc
> 分支：`codex/theme-kelivo-settings`
> Research：`docs/research-bubble-appearance-sliders.md`

## 目标

外观设置加一组控件（`DisclosureGroup` 折叠，紧跟"聊天字号" section 后），控制聊天页气泡视觉。全局 AppStorage，实时生效，带"全部重置"。

## 8 个问题定版

1. **折叠**：`DisclosureGroup(isExpanded: $bubbleAdvExpanded) { ... } label: { Text("气泡外观（高级）") }` — 学 `APISettingsTab.swift:1155-1167` 中转站倍率样式
2. **内边距**：H / V 两个独立 slider
3. **Range**：全部有 max（见下表）
4. **作用域**：全局 `@AppStorage`
5. **行距 / 段距**：Scale 模式，0.5...2.0，step 0.05
6. **隐藏按钮行**：iOS + macOS 都不 render
7. **重置**：一个"全部重置"按钮放在 DisclosureGroup 底部
8. **位置**：紧跟现有"聊天字号" section 后面，单独新 section（命名"气泡外观（高级）"）

## 新增 @AppStorage 键

| 键 | 默认 | 类型 | Range | Step |
|---|---|---|---|---|
| `bubbleCornerRadius` | 16 | Double | 0...28 | 1 |
| `bubblePaddingH` | 14 | Double | 8...24 | 1 |
| `bubblePaddingV` | 10 | Double | 4...20 | 1 |
| `bubbleSpacing` | 22 | Double | 8...40 | 1 |
| `lineSpacingScale` | 1.0 | Double | 0.5...2.0 | 0.05 |
| `paragraphSpacingScale` | 1.0 | Double | 0.5...2.0 | 0.05 |
| `hideTimestamp` | false | Bool | — | — |
| `hideRoleName` | false | Bool | — | — |
| `hideActionBar` | false | Bool | — | — |
| `bubbleAdvExpanded` | false | Bool | — | — |

## 任务清单

### Phase 1 · 数据层（MarkdownTheme 签名扩展）

- [ ] **P1.1** `MarkdownTheme.swift:5` — `memoryPalace(fontName:scale:)` 加两个参数：
  ```swift
  static func memoryPalace(
      fontName: String = "",
      scale: CGFloat = 1.0,
      lineSpacingScale: CGFloat = 1.0,
      paragraphSpacingScale: CGFloat = 1.0
  ) -> MarkdownUI.Theme
  ```
- [ ] **P1.2** `MarkdownTheme.swift:69` — `.relativeLineSpacing(.em(0.42))` → `.relativeLineSpacing(.em(0.42 * lineSpacingScale))`
- [ ] **P1.3** `MarkdownTheme.swift:70` — `.markdownMargin(top: 0, bottom: 12)` → `.markdownMargin(top: 0, bottom: 12 * paragraphSpacingScale)`

### Phase 2 · BubbleView 消费 AppStorage

- [ ] **P2.1** `CardFlowView.swift:1077-1081`（现有 AppStorage 下面）加 9 个新 AppStorage：
  ```swift
  @AppStorage("bubbleCornerRadius") private var bubbleCornerRadius: Double = 16
  @AppStorage("bubblePaddingH") private var bubblePaddingH: Double = 14
  @AppStorage("bubblePaddingV") private var bubblePaddingV: Double = 10
  @AppStorage("lineSpacingScale") private var lineSpacingScale: Double = 1.0
  @AppStorage("paragraphSpacingScale") private var paragraphSpacingScale: Double = 1.0
  @AppStorage("hideTimestamp") private var hideTimestamp: Bool = false
  @AppStorage("hideRoleName") private var hideRoleName: Bool = false
  @AppStorage("hideActionBar") private var hideActionBar: Bool = false
  // bubbleSpacing / bubbleAdvExpanded 不在 BubbleView 里用
  ```
- [ ] **P2.2** `CardFlowView.swift:1096-1098` 用户/助手名套 `if !hideRoleName`
- [ ] **P2.3** `CardFlowView.swift:1099-1103` 时间套 `if !hideTimestamp`
  - 注意：L1094 `HStack(spacing: 4)` 如果两个都藏了，HStack 变空，加 `if !hideRoleName || !hideTimestamp` 外层 guard 避免空 HStack 留 padding
- [ ] **P2.4** `CardFlowView.swift:1154` `.lineSpacing(4 * fontScale)` → `.lineSpacing(4 * fontScale * lineSpacingScale)`
- [ ] **P2.5** `CardFlowView.swift:1186` `.markdownTheme(.memoryPalace(...))` 传新参数：
  ```swift
  .markdownTheme(.memoryPalace(
      fontName: selectedFont,
      scale: fontScale > 0 ? fontScale : 1.0,
      lineSpacingScale: lineSpacingScale,
      paragraphSpacingScale: paragraphSpacingScale
  ))
  ```
- [ ] **P2.6** `CardFlowView.swift:1212-1213` padding 用变量：
  ```swift
  .padding(.horizontal, bubblePaddingH)
  .padding(.vertical, bubblePaddingV)
  ```
- [ ] **P2.7** `CardFlowView.swift:1215, 1219, 1224` cornerRadius 三处统一换：
  ```swift
  RoundedRectangle(cornerRadius: bubbleCornerRadius)
  ```
- [ ] **P2.8** `CardFlowView.swift:1282-1301` `HoverButtons(...)` 外面套 `if !hideActionBar { ... }`
- [ ] **P2.9** `HoverButtons` 的 macOS `.opacity(isHovered ? 1 : 0)` 保持不变（外层 if 已经决定要不要 render）
- [ ] **P2.10** Build verify（只改 BubbleView + MarkdownTheme，独立可编译）

### Phase 3 · CardFlowView LazyVStack spacing 可调

- [ ] **P3.1** `CardFlowView.swift` 顶层（struct CardFlowView 属性区域）加：
  ```swift
  @AppStorage("bubbleSpacing") private var bubbleSpacing: Double = 22
  ```
- [ ] **P3.2** `CardFlowView.swift:185` — `LazyVStack(spacing: 22)` → `LazyVStack(spacing: bubbleSpacing)`
- [ ] **P3.3** Build verify

### Phase 4 · AppearanceSettingsTab (macOS) 加控件

位置：`AppearanceSettingsTab.swift:124`（现有"聊天字号" section 的 `Divider().opacity(0.15)` 后面）

- [ ] **P4.1** 加 `@AppStorage` 10 个（含 `bubbleAdvExpanded`）
- [ ] **P4.2** 在字号 section 后面插入新 section：
  ```swift
  Divider().opacity(0.15)

  VStack(alignment: .leading, spacing: 14) {
      DisclosureGroup(isExpanded: $bubbleAdvExpanded) {
          VStack(alignment: .leading, spacing: 14) {
              bubbleSliderRow("圆角", value: $bubbleCornerRadius, range: 0...28, step: 1, formatter: { "\(Int($0))pt" })
              bubbleSliderRow("水平内边距", value: $bubblePaddingH, range: 8...24, step: 1, formatter: { "\(Int($0))pt" })
              bubbleSliderRow("垂直内边距", value: $bubblePaddingV, range: 4...20, step: 1, formatter: { "\(Int($0))pt" })
              bubbleSliderRow("气泡间距", value: $bubbleSpacing, range: 8...40, step: 1, formatter: { "\(Int($0))pt" })
              bubbleSliderRow("行间距", value: $lineSpacingScale, range: 0.5...2.0, step: 0.05, formatter: { "\(Int($0 * 100))%" })
              bubbleSliderRow("段落间距", value: $paragraphSpacingScale, range: 0.5...2.0, step: 0.05, formatter: { "\(Int($0 * 100))%" })

              Divider().opacity(0.1)

              Toggle("隐藏时间戳", isOn: $hideTimestamp)
              Toggle("隐藏用户/助手名", isOn: $hideRoleName)
              Toggle("隐藏消息下方按钮行", isOn: $hideActionBar)

              Divider().opacity(0.1)

              HStack {
                  Spacer()
                  Button("全部重置") { resetAllBubbleAppearance() }
                      .font(.system(size: Theme.SettingsFont.secondary))
                      .foregroundColor(Theme.textMuted)
                      .buttonStyle(.plain)
              }
          }
          .padding(.top, 8)
      } label: {
          Text("气泡外观（高级）")
              .font(.system(size: Theme.SettingsFont.sectionHeader, weight: .semibold))
              .foregroundColor(Theme.textPrimary)
      }
  }
  ```
- [ ] **P4.3** 新增 helper `bubbleSliderRow(_ title:value:range:step:formatter:)` — 统一 slider 行布局（label 左、当前值右、下一行 slider）
- [ ] **P4.4** 新增 `resetAllBubbleAppearance()` 函数，把 9 个 AppStorage 重置默认值
- [ ] **P4.5** Build verify（macOS target）

### Phase 5 · IOSAppearancePage (iOS) 加控件

位置：`AppearanceSettingsTab.swift:273`（现有"聊天字号" Section 的 `.listRowBackground(Theme.mainBg).listRowSeparator(.hidden)` 后面）

- [ ] **P5.1** 加同样 10 个 `@AppStorage`
- [ ] **P5.2** 在字号 Section 后面插入新 Section，用 `List` 风格适配：
  ```swift
  Section {
      DisclosureGroup(isExpanded: $bubbleAdvExpanded) {
          iOSBubbleSliderRow("圆角", ...)
          iOSBubbleSliderRow("水平内边距", ...)
          // ... 6 个 slider
          Toggle("隐藏时间戳", isOn: $hideTimestamp)
          Toggle("隐藏用户/助手名", isOn: $hideRoleName)
          Toggle("隐藏消息下方按钮行", isOn: $hideActionBar)
          Button("全部重置") { resetAllBubbleAppearance() }
              .foregroundColor(Theme.textMuted)
      } label: {
          Text("气泡外观（高级）")
              .font(.system(size: Theme.F.label))
      }
  }
  .listRowBackground(Theme.mainBg)
  .listRowSeparator(.hidden)
  ```
- [ ] **P5.3** iOS 复用同 helper（或写 iOS-specific `iOSBubbleSliderRow`）— slider 在 List 里可以直接 `Slider(value:in:step:)` 一行
- [ ] **P5.4** 复用 `resetAllBubbleAppearance()`（放 file-scope 函数或 static method）
- [ ] **P5.5** Build verify（iOS target）

### Phase 6 · 验收 + 回归

- [ ] **P6.1** macOS: 展开 DisclosureGroup → 所有 slider 滑动实时反馈到聊天页
- [ ] **P6.2** iOS: 同样验证
- [ ] **P6.3** 全部重置按钮回到默认值
- [ ] **P6.4** 三个 toggle 在聊天页正常隐藏对应部分
- [ ] **P6.5** 关掉 DisclosureGroup（收起）后所有控件状态仍然保留
- [ ] **P6.6** 进 / 退对话 / 切楼层 AppStorage 值保持
- [ ] **P6.7** 冷启动应用 → 9 个 AppStorage 默认值生效（无存储时回退常量）

### Phase 7 · commit + push

- [ ] **P7.1** `git add -A && git commit -m "feat: 气泡外观 9 个自定义（圆角/内边距/间距/行距/段距/3 toggle）+ DisclosureGroup 折叠"`
- [ ] **P7.2** `git push`

## 风险 / 回退

1. **`Theme.bubbleCornerRadius` 等常量仍被其他文件用（SidebarView / CharacterCardEditor / MemoryPanelView 等）**
   - 不动 Theme.swift 常量 — 让那些场景继续用默认 16pt
   - 只在 BubbleView / CardFlowView chat 路径替换为 AppStorage
   - 验证：grep `Theme.bubbleCornerRadius` / `Theme.bubblePadding` 看所有引用，chat 路径之外的保持不变

2. **`Equatable` 影响性能**
   - BubbleView 不是 Equatable（ChatInputBar 才是），加 AppStorage 不影响
   - AppStorage 变化触发 BubbleView.body 重绘 — 每个 bubble 都 body 一次。对 20w 节点容器无影响（LazyVStack 只 render 可视 bubble，~10 个）

3. **Role name + 时间同时隐藏时外层 HStack 空占位**
   - P2.3 里加 `if !hideRoleName || !hideTimestamp` guard HStack 整个不 render
   - 验证：两个 toggle 都 on 时 bubble 顶部无空行

4. **macOS hover 行为被改变**
   - `hideActionBar = false`（默认）时行为不变：macOS hover 才显示
   - `hideActionBar = true` 时 macOS/iOS 都不 render（连 hover 也没）
   - `.onHover` 在 HoverButtons 内部，不 render 时自然失效

5. **LazyVStack spacing 动画**
   - 改 bubbleSpacing 的瞬间，现有 bubbles 重新布局，可能一抖
   - 不加 `.animation(...)` —— slider 拖动时 AppStorage 每 step 发 publish，动画反而卡
   - 接受非动画切换

## 提醒（给粟粟）

- 未实现，等批注
- 有异议 task 打 ✗ 或写注释
- "开工"开搞

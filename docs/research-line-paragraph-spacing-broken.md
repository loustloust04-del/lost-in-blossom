# Research: 行间距 / 段落间距 slider 无反应

> 2026-04-22 · cc
> 分支：`codex/theme-kelivo-settings`
> 起因：粟粟说改了"气泡顶底对称"补丁（55b391c 之后的 uncommitted 改动）后，行间距 / 段落间距 slider 不生效

---

## 事实清点

### 关键代码位置

**MarkdownTheme.swift 当前（uncommitted，broken 版）**：
```swift
.paragraph { configuration in
    configuration.label
        .relativeLineSpacing(.em(0.42))                                     // ← 移除了 lineSpacingScale
        .markdownMargin(top: 6 * paragraphSpacingScale,
                        bottom: 6 * paragraphSpacingScale)                  // ← top/bottom 对称
}
```

**MarkdownTheme.swift 55b391c（commit 版，粟粟说 work）**：
```swift
.paragraph { configuration in
    configuration.label
        .relativeLineSpacing(.em(0.42 * lineSpacingScale))                  // ← 有 scale
        .markdownMargin(top: 0, bottom: 12 * paragraphSpacingScale)          // ← 非对称
}
```

**CardFlowView.swift 当前 Markdown render**：
```swift
Markdown(displayText)
    .markdownTheme(.memoryPalace(
        fontName: selectedFont,
        scale: fontScale > 0 ? fontScale : 1.0,
        lineSpacingScale: lineSpacingScale,
        paragraphSpacingScale: paragraphSpacingScale
    ))
    .textSelection(.enabled)
    .lineSpacing(5.67 * (fontScale > 0 ? fontScale : 1.0) * (lineSpacingScale - 1))
    .id("md-\(selectedFont)-\(fontScale)-\(paragraphSpacingScale)")
```

**CardFlowView.swift 55b391c Markdown render**：
```swift
Markdown(displayText)
    .markdownTheme(.memoryPalace(
        fontName: selectedFont,
        scale: fontScale > 0 ? fontScale : 1.0,
        lineSpacingScale: lineSpacingScale,
        paragraphSpacingScale: paragraphSpacingScale
    ))
    .textSelection(.enabled)
// 无 .lineSpacing, 无 .id
```

### 两个版本的改动差异（和本 bug 可能相关的）

| 改动 | 55b391c | 当前 |
|---|---|---|
| MarkdownTheme paragraph `.relativeLineSpacing` | `.em(0.42 * lineSpacingScale)` | `.em(0.42)` 无 scale |
| MarkdownTheme paragraph `.markdownMargin` | `top:0, bottom:12*scale` | `top:6*scale, bottom:6*scale` |
| 外层 `.lineSpacing()` | 无 | `.lineSpacing(5.67 * fontScale * (lineSpacingScale - 1))` |
| `.id()` | 无 | `.id("md-font-scale-paraScale")` |
| "展开全文" HStack 结构 | 永远挂（空也挂） | 仅 `cleaned.count > truncateLength` 时挂 |

### BubbleView @AppStorage（两个版本一致，没变）

```swift
@AppStorage("lineSpacingScale") private var lineSpacingScale: Double = 1.0
@AppStorage("paragraphSpacingScale") private var paragraphSpacingScale: Double = 1.0
```

### 用户 Text 侧（两个版本一致，没变）

```swift
Text(...)
    .font(FontManager.font(size: 13.5))
    .foregroundColor(Theme.textPrimary)
    .textSelection(.enabled)
    .lineSpacing(4 * (fontScale > 0 ? fontScale : 1.0) * lineSpacingScale)
```

---

## MarkdownUI 2.4.1 源码证据

- `Markdown` view `@Environment(\.theme.text)` 订阅，body 里调用 `BlockSequence(self.blocks)` 渲染（`swift-markdown-ui/Views/Markdown.swift:192-222`）
- 每个 `ParagraphView` `@Environment(\.theme.paragraph)` 订阅 `BlockStyle<BlockConfiguration>`，`body` 调用 `self.paragraph.makeBody(...)` （`ParagraphView.swift:4-25`）
- `BlockStyle` 是 `struct` 但**不实现 Equatable**，内部存 `body: (Configuration) -> AnyView` closure（`BlockStyle.swift:40-52`）
- `.markdownTheme(theme)` 实现：`self.environment(\.theme, theme)`（`Environment+Theme.swift:6-8`）

### SwiftUI env diff 对非 Equatable 值的行为

- 有 Equatable：值相等时跳过 invalidation
- 无 Equatable：一般退化成"**每次父 body 重算都重写环境**"，下游 observer 收到变更
- 但 `Theme` 是 struct，SwiftUI 可能不能可靠区分 "新 Theme" 和 "旧 Theme"，表现不确定

---

## 假设（按最可能到最不可能排）

### H1. 构建没生效 / Simulator cache stale

粟粟可能没 clean build。新代码没装上去。
- **验证**：Xcode `Product > Clean Build Folder`（Shift+Cmd+K），重新 Build+Run。

### H2. user 侧 `.lineSpacing()` 也没反应 → @AppStorage 根本没写入

user 气泡（纯 Text）用的是 `.lineSpacing(4 * fontScale * lineSpacingScale)`，纯 SwiftUI 原生。如果这个都不反应，说明 slider 根本没往 UserDefaults 写（或者 BubbleView 没重建读新值）。
- **验证**：发一条**长的用户消息**（4 行以上），调 lineSpacingScale slider 到 200%。看**用户气泡**（黄色胶囊）行距有没有变化。
  - 有变化 → @AppStorage 正常，问题只在 Markdown 侧 → 走 H3/H4
  - 无变化 → @AppStorage 没传播（或没重建），问题在更底层 → 走 H5

### H3. MarkdownUI 对 Theme env 不重新订阅（缓存问题）

`BlockStyle` 非 Equatable，SwiftUI env diff 可能判定"未变化"→ ParagraphView 不 invalidate → 老 closure 继续用 → old scale 值被读。
- **验证（已经做了）**：加 `.id()` 强制重建 Markdown view 子树。如果 `.id()` 后仍无变化 → H3 不成立 / 不是唯一问题。

### H4. `.lineSpacing(..)` 外层没生效传到 Markdown 子 Text

SwiftUI `.lineSpacing()` 据说传递给子 Text，但 MarkdownUI 的 InlineText 可能用了 `AttributedString` 或 `TextAttributes` 本地覆盖，绕过外层 lineSpacing 环境。
- **验证**：给一条 **user 消息**调 slider，user 侧纯 Text 应该反应。
  - user 侧反应但 Markdown 不反应 → H4 成立

### H5. @AppStorage 跨 sheet 传播在 iOS Paging 架构下有 bug

聊天页是 child HC 的 rootView，settings sheet 是 modal 覆盖。sheet 里改 UserDefaults 时，child HC 的 BubbleView 可能因为 parent PagingContainerView 的 `updatePages()` 节流（`isStreaming` 判断）等原因没重刷。
- **验证**：改完 slider **关闭 sheet**，用力滚动聊天页（让 LazyVStack 重刷 visible bubbles）。
  - 滚完后出现变化 → H5 成立

### H6. `.id()` 导致 env 传递失效（低可能性）

`.id(someKey)` 让 SwiftUI 完全销毁重建 subtree。理论上新 subtree inherit 父 env 应该拿到当前 theme，但 .id 瞬间的 env transaction 时序可能有坑。
- **验证**：临时注释掉 `.id(...)` 这行，重新测。

---

## 调试步骤（让粟粟或我跑）

### 步骤 1：clean + rebuild（排除 H1）
```
Xcode → Product → Clean Build Folder（Shift+Cmd+K）
Xcode → Product → Run（Cmd+R）
```

### 步骤 2：测 user 侧行距（区分 H2 vs H3/H4）
1. 在 iOS 模拟器 / 真机上发一条**长的用户消息**，比如：
   ```
   这是测试。换行一。
   换行二。
   换行三。
   换行四。
   ```
2. 打开 Settings → 外观 → 气泡外观（高级） → 行间距
3. 拖到 50%，看用户气泡（黄色）的行距
4. 拖到 200%，看用户气泡的行距
5. **报告**：有没有变化？

### 步骤 3：测 assistant Markdown 段间距（区分 H3 vs .id 是否有效）
1. 让 AI 生成**多段落**回复（比如"列 5 段话"）
2. Settings → 段落间距
3. 拖到 50% 和 200%，看 assistant 气泡的段间距
4. **报告**：有没有变化？

### 步骤 4：打开 Xcode console 看日志
- `@AppStorage` 写入 UserDefaults 不会打印，但 UserDefaults.standard.double(forKey:) 能手动查。
- 可以临时加 `print` 到 BubbleView.body 顶部，看 body 触发次数 + 当前 scale 值。

---

## 根据测试结果决定下一步

| 步骤 2 user 侧 | 步骤 3 Markdown 段间 | 诊断 | 修法 |
|---|---|---|---|
| 有变化 | 有变化 | H1 成立，clean build 后正常 | 不用修代码 |
| 有变化 | 无变化 | H3/H4：MarkdownUI env diff 失败 | 放弃 MarkdownUI paragraph scale，把段间距也挪到外层（用 `.padding` + 自己分行？） |
| 无变化 | 无变化 | H2/H5：@AppStorage 写入 / 传播 fail | 改用 @Environment 或 @Observable Manager 承载这俩 scale |
| 无变化 | 有变化 | 非常怪，需要继续深挖 | — |

---

## 当前不要做的事

- **不要**继续在 MarkdownTheme 里加 "更多 scale 参数"——方向错了
- **不要**给 `.id()` 加更多变量——不改变本质诊断
- **不要**回退到 55b891c——需要先弄清楚 55b391c 是**真的 work** 还是**没 work 但粟粟当时没发现**

---

## 问粟粟

1. 55b391c 那次 commit 时你**实测过** slider 对气泡有视觉变化吗？还是只是"build 过了，上了 commit" 没细看？
2. 现在测 slider 时你是在**模拟器**还是**真机**？如果是 simulator，clean build 过吗？
3. user 消息的行距、assistant Markdown 的段间距、还有**字号** slider（fontScale 是已有功能）分别测一下，哪个有反应哪个没反应？

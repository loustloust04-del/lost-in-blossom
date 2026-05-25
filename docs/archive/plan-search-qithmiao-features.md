# Plan: 从起司猫偷来的搜索体验增强

基于 `docs/research-search-competitors.md`，从 QithMiao 移植 4 个功能。

---

## 功能清单

| # | 功能 | QithMiao 做法 | 我们的实现 |
|---|------|-------------|-----------|
| A | Snippet 关键词高亮 | regex → `<span class="highlight">` | `AttributedString` + 薄荷绿背景 |
| B | 目标气泡闪烁 | `scrollToMessage()` + 3s CSS highlight | `BubbleView` overlay + 2s 动画 |
| C | 搜索结果上/下导航 | `flatSearchResults[]` + prev/next btn | 扁平索引 + 导航条 |
| D | 当前对话内搜索 | `performCurrentSearch()` 单对话 filter | `Cmd+F` 触发，CardFlowView 内搜索条 |

---

## A. Snippet 关键词高亮

### 现状
`ContentMatchRow` 行 1151: `Text(preview)` 纯文本，无高亮。
`SearchService.buildPreview()` 返回纯 String。

### 方案
`SearchService.buildPreview()` 改为返回 `AttributedString`，关键词部分加背景色。

或者更简单：保持返回 String，在 `ContentMatchRow` 里用 `Text` 拼接高亮。

选后者——View 层负责渲染，Service 层保持纯数据。

### 原子任务

- [ ] **A.1** `MatchedNode` 加 `keyword: String` 字段（从 SearchFilter 传入）
- [ ] **A.2** `SearchService.performSearch` 在构造 `MatchedNode` 时把 keyword 传进去
- [ ] **A.3** `ContentMatchRow` 加 `keyword: String` 参数
- [ ] **A.4** `ContentMatchRow` 的 preview 渲染改为 `highlightedText(preview, keyword:)` 方法：
  ```swift
  /// 把 preview 中匹配 keyword 的部分标为高亮
  private func highlightedText(_ text: String, keyword: String) -> Text {
      guard !keyword.isEmpty else { return Text(text) }
      let lower = text.lowercased()
      let keyLower = keyword.lowercased()
      var result = Text("")
      var searchStart = lower.startIndex
      
      while let range = lower.range(of: keyLower, range: searchStart..<lower.endIndex) {
          // 匹配前的普通文字
          let before = text[searchStart..<range.lowerBound]
          if !before.isEmpty {
              result = result + Text(before)
          }
          // 匹配部分：薄荷绿背景
          let matched = text[range]
          result = result + Text(matched)
              .foregroundColor(Theme.textPrimary)
              .background(Theme.branchIndicator.opacity(0.3))
          searchStart = range.upperBound
      }
      // 剩余尾部
      let tail = text[searchStart...]
      if !tail.isEmpty {
          result = result + Text(tail)
      }
      return result
  }
  ```
  背景色用 `Theme.branchIndicator.opacity(0.3)`（淡薄荷绿），不用黄色。
- [ ] **A.5** SidebarView 传 `keyword` 给 `ContentMatchRow`：
  ```swift
  ContentMatchRow(
      ...,
      keyword: searchFilter.keyword  // 新增
  )
  ```
- [ ] **A.6** 对话标题也高亮：搜索结果列表里的 `Text(group.convTitle)` 在 `isTitleMatch` 时也做高亮处理。用同样的 `highlightedText()` 方法，提取为顶层 helper 函数。

---

## B. 目标气泡闪烁

### 现状
scroll 到目标后无视觉反馈，用户不知道哪个是匹配的气泡。

### 方案
QithMiao: 给目标消息加 3s CSS `.highlight` class。
我们: `BubbleView` 检测自己是否是 `highlightedNodeId`，是则播放 2s 淡入淡出背景 overlay。

### 原子任务

- [ ] **B.1** `ConversationViewModel` 加 `highlightedNodeId: String? = nil`
- [ ] **B.2** `applyTreeData` 里 `pendingScrollNodeId` 触发后，同时设 `highlightedNodeId`：
  ```swift
  DispatchQueue.main.async { [self] in
      scrollToNodeId = pending
      highlightedNodeId = pending
  }
  ```
- [ ] **B.3** `CardFlowView` 里 `BubbleView` 调用加参数：
  ```swift
  BubbleView(
      ...,
      isHighlighted: viewModel.highlightedNodeId == node.id
  )
  ```
- [ ] **B.4** `BubbleView` 加 `isHighlighted: Bool = false` 参数 + overlay 动画：
  ```swift
  var isHighlighted: Bool = false
  @State private var highlightOpacity: Double = 0
  
  // 在气泡最外层加 overlay
  .overlay(
      RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius)
          .fill(Theme.branchIndicator.opacity(0.2 * highlightOpacity))
          .allowsHitTesting(false)
  )
  .onChange(of: isHighlighted) { _, highlighted in
      if highlighted {
          // 亮起
          withAnimation(.easeIn(duration: 0.3)) { highlightOpacity = 1 }
          // 2 秒后淡出
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
              withAnimation(.easeOut(duration: 0.5)) { highlightOpacity = 0 }
          }
      }
  }
  ```
- [ ] **B.5** `ConversationViewModel`: 在 highlight 动画结束后清除 `highlightedNodeId`。
  在设置 `highlightedNodeId` 时启动 3 秒定时器清除：
  ```swift
  DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
      if highlightedNodeId == pending {
          highlightedNodeId = nil
      }
  }
  ```

---

## C. 搜索结果上/下导航

### 现状
搜索结果只能在侧边栏点击，没有快捷导航。

### QithMiao 做法
`flatSearchResults[]` 扁平数组 + `currentSearchIndex` + prev/next 按钮循环。

### 方案
在搜索结果统计行（"3 个对话，12 条结果"）旁边加 ◀ ▶ 按钮。
维护一个扁平化的 `allMatchedNodes` 数组 + `currentMatchIndex`。

### 原子任务

- [ ] **C.1** SidebarView 加 state：
  ```swift
  @State private var currentMatchIndex: Int = -1
  ```
- [ ] **C.2** 加 computed property `flatMatches`:
  ```swift
  private var flatMatches: [MatchedNode] {
      searchResults.flatMap { $0.matchedNodes }
  }
  ```
- [ ] **C.3** 搜索结果统计行加导航按钮：
  ```swift
  HStack {
      Text("...条结果")
      Spacer()
      if !flatMatches.isEmpty {
          Text("\(currentMatchIndex + 1)/\(flatMatches.count)")
              .font(.caption2)
              .foregroundColor(Theme.textMuted)
          Button(action: { navigatePrev() }) {
              Image(systemName: "chevron.up")
                  .font(.system(size: 11))
          }
          .buttonStyle(.plain)
          Button(action: { navigateNext() }) {
              Image(systemName: "chevron.down")
                  .font(.system(size: 11))
          }
          .buttonStyle(.plain)
      }
  }
  ```
- [ ] **C.4** 实现 `navigateNext()` / `navigatePrev()`：
  ```swift
  private func navigateNext() {
      guard !flatMatches.isEmpty else { return }
      currentMatchIndex = (currentMatchIndex + 1) % flatMatches.count
      let match = flatMatches[currentMatchIndex]
      navigateToNodeById(match.id, conversationId: match.conversationId)
  }
  private func navigatePrev() {
      guard !flatMatches.isEmpty else { return }
      currentMatchIndex = (currentMatchIndex - 1 + flatMatches.count) % flatMatches.count
      let match = flatMatches[currentMatchIndex]
      navigateToNodeById(match.id, conversationId: match.conversationId)
  }
  ```
- [ ] **C.5** 搜索触发时重置 `currentMatchIndex = -1`
- [ ] **C.6** 手动点击搜索结果时同步更新 `currentMatchIndex`：
  在 `ContentMatchRow.onTapGesture` 里找到对应 index 并设置。

---

## D. 当前对话内搜索

### 现状
只有全局搜索。用户想在当前对话里找某句话时，只能全局搜然后在结果里找。

### QithMiao 做法
搜索框切换 "当前对话" / "全部对话" 模式。当前对话模式只搜 `currentMessages`。

### 方案
`Cmd+F`（macOS）触发 CardFlowView 顶部搜索条。只搜 `viewModel.currentPath` 里的消息。

### 原子任务

- [ ] **D.1** `ConversationViewModel` 加状态：
  ```swift
  var inConversationSearchKeyword: String = ""
  var inConversationMatches: [String] = []  // matched node IDs
  var inConversationMatchIndex: Int = -1
  ```
- [ ] **D.2** `ConversationViewModel` 加 `searchInCurrentConversation(keyword:)` 方法：
  ```swift
  func searchInCurrentConversation(keyword: String) {
      inConversationSearchKeyword = keyword
      guard !keyword.isEmpty else {
          inConversationMatches = []
          inConversationMatchIndex = -1
          return
      }
      inConversationMatches = currentPath.filter { node in
          (node.role == "user" || node.role == "assistant") &&
          node.content.localizedStandardContains(keyword)
      }.map(\.id)
      inConversationMatchIndex = inConversationMatches.isEmpty ? -1 : 0
      if let firstId = inConversationMatches.first {
          scrollToNodeId = firstId
          highlightedNodeId = firstId
      }
  }
  ```
- [ ] **D.3** `CardFlowView` 加 `@State private var showInConvSearch = false`
- [ ] **D.4** `CardFlowView` 在 ScrollView 上方加搜索条（只在 `showInConvSearch` 时显示）：
  ```swift
  if showInConvSearch {
      InConversationSearchBar(
          viewModel: viewModel,
          onDismiss: { showInConvSearch = false }
      )
  }
  ```
- [ ] **D.5** 新建 `InConversationSearchBar` struct View：
  ```
  ┌──────────────────────────────────────────┐
  │ 🔍 [搜索当前对话...]  2/8  ▲  ▼  ✕     │
  └──────────────────────────────────────────┘
  ```
  - TextField + 匹配计数 + 上/下按钮 + 关闭按钮
  - `onSubmit` / 文字变化时调 `viewModel.searchInCurrentConversation()`
  - 上/下按钮调 `viewModel.navigateInConvMatch(direction:)`
  - 关闭按钮清除搜索状态 + 隐藏条
- [ ] **D.6** `ConversationViewModel` 加 `navigateInConvMatch(direction:)`:
  ```swift
  func navigateInConvMatch(direction: Int) { // +1 or -1
      guard !inConversationMatches.isEmpty else { return }
      inConversationMatchIndex = (inConversationMatchIndex + direction + inConversationMatches.count) % inConversationMatches.count
      let nodeId = inConversationMatches[inConversationMatchIndex]
      scrollToNodeId = nodeId
      highlightedNodeId = nodeId
  }
  ```
- [ ] **D.7** `Cmd+F` 快捷键绑定：
  ```swift
  .keyboardShortcut("f", modifiers: .command)
  // 或者用 .onKeyPress 在 CardFlowView 层处理
  ```
  macOS 上 `Cmd+F` toggle `showInConvSearch`。
- [ ] **D.8** 当 `inConversationSearchKeyword` 非空时，`BubbleView` 里匹配的气泡显示高亮。
  传 `searchKeyword: String?` 给 BubbleView，在气泡外层加淡薄荷绿边框表示匹配：
  ```swift
  .overlay(
      RoundedRectangle(cornerRadius: Theme.bubbleCornerRadius)
          .stroke(Theme.branchIndicator.opacity(0.5), lineWidth: inConversationMatches.contains(node.id) ? 1.5 : 0)
  )
  ```

---

## 文件改动一览

| 文件 | 功能 | 改动 |
|------|------|------|
| `SearchService.swift` | A | MatchedNode 加 keyword 字段 |
| `SidebarView.swift` | A, C | ContentMatchRow 高亮 + 导航按钮 + index 管理 |
| `ConversationViewModel.swift` | B, D | highlightedNodeId + 对话内搜索状态/方法 |
| `CardFlowView.swift` | B, D | BubbleView 闪烁 overlay + 对话内搜索条 + Cmd+F |

---

## 实施顺序

**先 A+B**（snippet 高亮 + 气泡闪烁）→ build 验证 → commit
**再 C**（上/下导航）→ build 验证 → commit  
**最后 D**（当前对话内搜索）→ build 验证 → commit

A+B 是视觉反馈，改动小收益大。C 是交互增强。D 最大但最独立。

---

## 不做的事

- ❌ 气泡内 Markdown 渲染后的关键词高亮（需要侵入 MarkdownUI 渲染管线，复杂度太高，Phase 3 再说）
- ❌ 中文分词 / 词云（远期）
- ❌ 评分排序（粟粟说先不搞）

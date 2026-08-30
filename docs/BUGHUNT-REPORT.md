# BunnyPalace Bug Hunt Report
## Phase 1 — Reconnaissance (read-only)
Date: 2026-07-14

范围：`MemoryPalace/` Swift 源码。目标 iOS 18.0 / Swift 5.x / Xcode 16。
**只读侦察**，未改任何代码。每条含 `文件:行号`、现象、根因、建议改法、是否触及在途文件。

避开的在途文件（别的窗口地盘）：ConsoleView、AnniversaryManageSheet、TweetsFeedSheet、
AnniversaryClient/TweetsClient/HealthBridgeClient、ConversationViewModel+Group/+Chat（群聊部分）、
GroupMembersSheet、CreateGroupChatView、CardFlowView（群聊部分）、Services/Voice/*、
VoiceCapsuleView、VoiceSettingsSection。以下 bug 的**修改点**均落在非在途文件（个别现象会牵连
到 +Chat 的读取端，已标注）。

iOS 26 API 核查：`.glassEffect` 只出现在 `Utils/GlassEffectCompat.swift` 的 iOS 18 兼容封装
（`.glassEffectCompat` → `.ultraThinMaterial`），无真实 iOS 19+/26 API 调用。✅

---

### Critical (crash / data-loss risk)

- **[BUG-001]** `Services/PromptAssembler.swift:77, 191` — **上下文摘要永远没被注入，压缩后静默丢历史**。
  `assemble()` 把摘要 append 进局部 `var summaryParts`（77 声明、191 追加），此后**再无任何地方读取**
  `summaryParts`（全文件 grep 只有这两处）。触发压缩（60+ 消息）后旧消息按 `ContextSummarizer.windowStart`
  真被裁掉（`+Chat.swift:301`），却没有摘要顶上；「继承上文」(ContextInheritance) 也一并失效——继承内容
  就是靠 ContextSummary 走的。`+Chat.swift:143-146` 按 `tag == "contextSummary"` 过滤 systemParts，而
  该 tag 从未被产出。
  修：191 行改成 `systemParts.append((tag: "contextSummary", content: "[前情提要]\n\(summary)"))`，
  删掉 `summaryParts`。**低风险一行改**，恢复整条长期记忆链路。修改点在 PromptAssembler（非在途）；
  读取端在 +Chat（群聊部分在途，但这段是通用逻辑，只读不改）。

### High (broken feature / bad UX)

- **[BUG-002]** `Services/OpenAICompatibleProvider.swift:434（hold 条件）, 346（[DONE] 未 flush）` —
  **流式正文遇到 `</` 或 `[/` 后永久吞字**。标签缓冲的继续缓冲条件里有 `pendingTagBuffer.contains("[/")`
  和 `.contains("</")`，对**只增不减**的缓冲区做 contains：正文里出现任意 HTML/XML 闭合标签、BBCode、
  路径中的 `</`、`[/` 就永远为真，之后每个 chunk 都追加后 `return`。`[DONE]`（346）`finalContent = streamingContent`
  不 flush 缓冲，held 内容全丢。修：hold 判定改为「以合法标签前缀**结尾**」的 suffix 检查；`[DONE]` 时把
  `pendingTagBuffer` 并入 `streamingContent`。非在途。

- **[BUG-003]** `Services/CCBridgeWebSocketClient.swift:504 vs 511` — **CC 回复带的文件/图片附件丢失**。
  `handleIncoming("reply")` 里 reply handler（504 `DispatchQueue.main.async { handler(content) }`）**先于**
  附件 handler（511）派发；两者都进 main 串行队列，reply 先跑，`CCBridgeProvider` 读到 `pendingAttachment == nil`
  就 onComplete，附件 handler 随后设的值再无人读。Provider 注释假设的是相反顺序。修：附件 handler 与 reply
  handler 同块派发、或附件在前。非在途。

- **[BUG-004]** `Views/SidebarView.swift:881-889` — **「导出为 Markdown」默认档位下是空操作**。
  `exportConversation()` 仅当 `exportMode == "full"` 才设 `exportingConversation`，`else` 分支空实现；默认
  `@AppStorage("exportMode") = "lightweight"`（101 行）走空 else，长按导出无反应。修：在 else 里实现轻量导出，
  或统一弹 `ExportOptionsSheet`。非在途。

- **[BUG-005]** `Views/Reading/BookReaderSheet.swift:747（配合 108-110, 782-788）` — **TXT 书在第 N(>1) 章续读时
  抹掉保存的阅读进度**。`onAppear` 的 `loadBook()` 把 `currentChapter` 从 1 改到 N，触发
  `.onChange(of: currentChapter)` → `loadChapter(N, resetScroll: true)`，把 `latestScrollRatio = 0` 并
  `scheduleSaveProgress()`，用 0 覆盖存档；深链 `initialAnchorOffset` 定位也被冲掉，章节被加载两次。
  修：用 isInitialLoad 标记或 onChange 里比对新旧值避免首帧 reset。非在途。

- **[BUG-006]** `ViewModels/StickerViewModel.swift:168-232（importImages）, 236-265（importImageData）` —
  **贴纸导入在后台线程改 @Observable 状态并跨线程访问 SwiftData @Model**。两个方法是非 `@MainActor` 的
  `async`，被 `StickerImportSheet.swift:171/184` 的裸 `Task { }` 调用 → 跑在全局并发 executor。其中改
  `isImporting`/`importProgress`（169/175/237/243）、调 `deduplicateName`（203/249）读 `stickerAssets.map(\.name)`
  （570）——在主 context 的 @Model 上后台读属性。代码在 `context.insert` 处已知道要 `MainActor.run`，但进度字段和
  dedup 漏了。修：方法标 `@MainActor`，把 CPU 活（SubjectLifter/边框渲染/存盘）丢进 `Task.detached`。非在途。

- **[BUG-007]** `ViewModels/StickerViewModel.swift:382-402（updateStyle）` — 同类：非隔离 async 被
  `StickerLibraryView.swift:163` 的 `Task { }` 调用，383/389/402 在后台读 @Model（`asset.imagePath` 等），
  只有写回 hop 了 MainActor。修：先在主 actor 快照 `asset.id/imagePath/originalImagePath` 再做后台活。非在途。

### Medium (incorrect behavior)

- **[BUG-008]** `Services/AnthropicProvider.swift:215` — 非流式路径硬编码 `max_tokens: 1024`；
  `ContextSummarizer` 要 ≤2000 字（≈2500-3000 token）。BUG-001 修好后摘要会被截断——污染长期记忆。
  修：加 maxTokens 参数或抬到 ≥4096。非在途。

- **[BUG-009]** `Services/ChatService.swift:82（startRequest）, 56（cancel）, 133（didCompleteWithError）` —
  **URLSession 泄漏**。每次请求 `URLSession(configuration:delegate:delegateQueue:)`，URLSession 强持 delegate
  直到 `invalidateAndCancel()`/`finishTasksAndInvalidate()`；而 cancel/didComplete 只把 `urlSession = nil`。
  每条消息、每轮 tool-loop 泄漏一个 session。修：完成时 finishTasksAndInvalidate、cancel 时 invalidateAndCancel。非在途。

- **[BUG-010]** `Services/OpenAICompatibleProvider.swift:310-312` 与 `Services/AnthropicProvider.swift:263-265` —
  **UTF-8 分片解码丢字（中文尤甚）**。`String(data:encoding:.utf8) else { return }` 对 URLSession 任意字节边界，
  多字节字符被切在两次 didReceive 之间就整块丢弃、SSE 分帧也会错位。修：缓冲原始 Data，只解码到最后一个完整
  UTF-8 序列。非在途。

- **[BUG-011]** `Services/OpenAICompatibleProvider.swift:199-213, 341-343` — **function-calling 多轮的竞态 + 正文重复**。
  (a) `[DONE]` 在 URLSession delegate 线程直接调 `runOpenAIToolRound` 读 `streamingContent`（201），但 delta 是
  `DispatchQueue.main.async` 追加（427+），晚到的 delta 还没进去 → 尾段丢。(b) 213 `assistantText = streamingContent`
  用的是**累计**全轮内容而非本轮 `roundText`，第 2 轮起把前轮正文重复塞进 assistant 消息。修：快照前先 hop main；
  assistantMsg 用 `roundText`。非在途。

- **[BUG-012]** `ViewModels/ConversationViewModel+Tree.swift:175 → 449` — **带滚动目标加载时 `mainPathIds` 被冲掉**，
  破坏「永久主路径」不变量。175 `currentNodeId = scrollTargetNodeId ?? conversation.currentNodeId` 同一值既建显示路径
  又追 `mainPathIds`，449 无条件赋值。点击分支搜索结果(126)后该分支被误标为主线，`branchChildren(isMainPath:)`、
  `rebuildPath` 主子回退、`collectAllBranches` depth-0 分类都跟着跑偏。修：`mainPathIds` 恒从 `conversation.currentNodeId`
  追，`scrollTargetNodeId` 只用于显示路径。非在途。

- **[BUG-013]** `ViewModels/ConversationViewModel+Tree.swift:84（set） vs 471（唯一消费）` — `navigateToNodeFast`
  设的 `pendingScrollNodeId` 只被 `applyTreeData` 消费，而快路径走 `rebuildPath()` 不进加载管线：(a) 单击快切不滚动到
  目标；(b) 陈旧值残留到下次任意会话的 full load，用旧会话 node id 触发 scroll/highlight。修：快路径直接设
  `scrollToNodeId`；或 loadConversation 顶部清 `pendingScrollNodeId`。非在途。

- **[BUG-014]** `ViewModels/ConversationViewModel+Actions.swift:50-52` vs `+Tree.swift:405-407, 466` —
  `nodeCount` 两套定义。softDelete 用 currentPath 长度重算，applyTreeData 用全树 displayableCount；有分支时软删一条
  会让侧栏计数从 N 跳到当前路径长度再跳回。修：softDelete 里 `nodeCount = max(0, nodeCount-1)` 或按同一 displayable
  谓词从 nodeMap 重数。非在途。

- **[BUG-015]** `Views/SidebarView.swift:555-558（配合 453, 1050, 1640）` — **Chats 档 >100 会话时分页卡死**。
  `.chats` 模式 fetchPage 用 `sourceFilter = nil`（取所有来源），但 ForEach 只遍历 `filteredConversations`
  （`source == nil`）；load-more 触发比对未过滤数组的 `.last`，若末元素是导入会话（source 非 nil）则永不渲染、
  `loadMore()` 永不触发。修：比对 `filteredConversations.last?.id`。非在途。

- **[BUG-016]** `Views/BranchMapSheet.swift:423-424, 502` — **分支图丢根级兄弟分支**。`topDisplayables` 收了所有顶层
  可显示节点，却只把 `.first` 传给 `build(...)`，其余被丢（首条 user 消息被重生成/分叉时看不到）。修：建虚拟根、
  布局全部 topDisplayables。非在途。

- **[BUG-017]** `Views/Reading/PDFReaderSheet.swift:726` — **0 页 PDF 崩溃**（`Range requires lowerBound <= upperBound`）。
  `for p in max(1, page-1)...min(doc.pageCount, page+1)`，pageCount==0、page==1 时为 `1...0` trap；loadBook(555)
  clamp 后仍得 1。修：循环前 `guard doc.pageCount > 0 else { return }`。非在途。

- **[BUG-018]** `Views/ContentView.swift:176-181` — `.showStickerLibrary` 设 `selectedToolId`/`isRightPanelVisible`
  但没设 `iOSPage = 1`（隔壁 pendingTarget 分支 183-189 有设），iPhone 上点开贴纸库不切页，要手动划。修：动画块里补
  `iOSPage = 1`。非在途。

- **[BUG-019]** `Views/ContentView.swift:369-371` — 全局世界书 toggle/编辑（书数不变）时 `globalWorldBookEntries` 不刷新，
  因为 `.onChange(of: books.count)` 只认数量变化。修：观测启用 ID+条目数的变更 token 或让 manager 发 revision。非在途。

- **[BUG-020]** `Views/Reading/PDFReaderSheet.swift:1039-1055` — 用已废弃的 `UIMenuController.menuItems`（iOS 16 起废弃，
  PDFKit 选中菜单走 `UIEditMenuInteraction`），iOS 18 上自定义「高亮/加笔记/问…/收生词」基本不出现，
  `.pdfNativeSelectionAction` 路径形同死代码，只剩框选兜底。修：改 `buildMenu(with:)` / `UIEditMenuInteractionDelegate`。非在途。

- **[BUG-021]** `Utils/BudgetCalculator.swift:64-82` — 预发送预算把 base64 图片当纯文本估算，一张 300KB 图 ≈ 8.5 万 token，
  保险闸可能误警/误拦图片发送。修：估算前剥掉图片块。非在途。

- **[BUG-022]** `Views/MessageSegmentsView.swift:207` — `ForEach(resolved.indices, id: \.self)` 配合 ToolCallCardView/
  ThinkingBlockView 内部 `@State`，流式中途插入段（如 tool 结果到达）导致索引位移、展开/折叠状态迁移到错误卡片。
  修：用稳定 id（段 id / 源数组内偏移）。非在途。

### Low (code smell / minor)

- **[BUG-023]** `ViewModels/ConversationViewModel+Tree.swift:164（set）, 189（早退守卫）, 467（唯一 reset）` —
  加载被中途放弃（load 期间清了 selection）时守卫 189 提前返回，`isLoading` 卡 true。现被 `isCurrentConvLoading`
  的 AND 兜住，但任何直读 `isLoading` 者会卡 spinner。修：profileWillSwitch observer 与清选删除路径补 `isLoading = false`。

- **[BUG-024]** `ViewModels/ConversationViewModel+Tree.swift:164-171` — 会话内搜索状态在切会话时不清（reset 块漏了）。
  A→B 切换后「n/N」计数仍是 A 的、next/prev 把 `scrollToNodeId` 设成 A 的 node id（B 里是死目标）。修：loadConversation
  里会话 id 变化时调 `clearInConvSearch()`。

- **[BUG-025]** `ViewModels/ConversationViewModel+Actions.swift:43-55` — `softDelete` 把 @Model 写延到下一 runloop，
  若 `.profileWillSwitch`（容器拆除）恰好插入其间，`node.isDeleted = true` 触发正是 observer 防御要防的
  destroyed-instance 崩溃类（此闭包自持 node/conv，observer 清不掉）。且 `inConvMatches` 残留被删 node id。
  修：同步写 isDeleted/deletedAt；`inConvMatches.removeAll { $0 == deletedId }`。

- **[BUG-026]** `Services/AnthropicProvider.swift:174-191` 与 `OpenAICompatibleProvider.swift:383-386` — 多轮 tool loop 每轮
  用 `=` 覆盖 usage，只计最后一轮 input/cache token，预算闸少算。修：跨轮 `+=` 累加（只在 resetState 重置）。

- **[BUG-027]** `Services/PromptPostProcessor.swift:36-40` — TokenEstimator（预览用）对非 ASCII 收 1.5 token/字，
  注释说「中文 ~1.5 字符/token」（应 ≈0.67 token/字），预览数字虚高 ~50-125%。预算闸走的另一套 HeuristicEstimator 正确。

- **[BUG-028]** `Services/CCBridgeProvider.swift:10` — `replyGracePeriod = 120`，注释与错误文案（7/50/110/117）都写「60 秒」；
  且成功路径不调 `unregisterReplyAttachmentHandler`，每 chatId 留陈旧闭包。修：文案/常量对齐；成功后反注册。

- **[BUG-029]** `Services/SyncEngine.swift:131` — suspend `dirSource` 未设 `dirSuspended`，`stop()`(64-66) 会 cancel 已挂起的
  DispatchSource（崩溃）；目前只因 `startDirectoryMonitor()`(104) 是空 stub、dirSource 恒 nil 而不可达。填 Mac 路径前修。

- **[BUG-030]** `Services/PromptAssembler.swift:380-381` — `parseChatExamples` 中 `"\(profile.userName):"` 在名字为空时成 `":"`，
  任何以 `:` 开头的示例行被误判为 user 消息。边缘情况。

- **[BUG-031]** `Views/APISettingsTab.swift:293` — Picker 里 `__separator__` 行的 `.disabled(true)` 在 iOS menu-style picker
  不可靠，选中它会把 `apiSelectedProviderId = "__separator__"`、后续 API key 存到哨兵 id 下。修：从可选项过滤掉或用 Section。

- **[BUG-032]** `Views/Reading/PDFReaderSheet.swift:927-932` — `.pdfReaderGoToPage` observer 不校验 `safeName`（其他 handler 都校验），
  两个活跃 PDF 视图会一起跳页。修：比对 `userInfo["safeName"]`。

- **[BUG-033]** `Views/SidebarView.swift:1352` — `Image(systemName: ... ? "checkmark" : "")` 空 symbol 名，运行时报
  "No symbol named ''"。修：用 `Color.clear.frame(width:14)` 或条件视图。

- **[BUG-034]** `Views/SidebarView.swift:1797, 1826` — 搜索结果行 Button(action: 展开) 又叠 `.onTapGesture`(加载会话)，
  一次点击可能两个都触发（展开+跳转）。修：把 chevron 命中区与行点击分开。

### Summary
Total: **34 bugs found**（1 Critical, 6 High, 15 Medium, 12 Low）。

最该先动的三条（都低风险、隔离性强、不碰在途文件）：
1. **BUG-001**（PromptAssembler.swift:191）—— 一行修，恢复整条上下文摘要/继承记忆链路，静默数据丢失。
2. **BUG-003**（CCBridgeWebSocketClient.swift:504/511）—— 换两个派发块顺序，修好 CC 附件丢失。
3. **BUG-002**（OpenAICompatibleProvider.swift:434/346）—— 修流式吞字，正文含 `</`/`[/` 即触发。

核查结论：无真实 iOS 19+/26 API；Models/Utils 层无危险强解包；已存在的 force-unwrap
（BookImporter/BranchMapSheet/BookReaderSheet/CalendarPanelView 等）均有前置 guard，安全。

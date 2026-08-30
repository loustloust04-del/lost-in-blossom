# Views 目录代码审查

> 审查范围：`MemoryPalace/Views/` 下 115 个 Swift 文件，共 42677 行。
> 审查日期：2026-08-12
> 排序原则：按「值不值得动」排序，不是按「有多丑」排序。

---

## P0 · 会咬人的

### 1. CareView.swift:49,51 — 饮水/进食双源取 max() 创可贴仍在

```
let waterVal = Double(max(t?.waterCount ?? 0, vitals?.water.count ?? 0))
let foodVal = Double(max(t?.meals.count ?? 0, vitals?.food.count ?? 0))
```

**问题**：本地和网关两套计数取 max()，但两边计数可能各自漏记（网关没同步到本地的 / 本地没上报的），导致数据只增不减、删除/撤回无法体现。
**危害**：P0 —— 双源取 max 是已知的数据一致性创可贴（TASK-CODE-AUDIT 原文提到），能跑但会给用户错觉。
**建议**：按 DEBT-MAP 规划做双向同步，消灭 max() 创可贴。

### 2. AddMemorySheet.swift:72 — try? 吞掉记忆写入失败

```
try? store.add(content: trimmed, ...)
```

**问题**：添加记忆失败时静默返回，用户点了「保存」以为成功，实际没写入。
**危害**：P0 —— 静默数据丢失，用户无感知。
**建议**：改 do-catch，失败时 toast 提示「记忆保存失败」。

### 3. MemoryPanelView.swift:400 — try? 吞掉记忆加载失败

```
memories = (try? store.listAll(profileId: profileId, context: modelContext)) ?? []
```

**问题**：记忆列表加载失败时展示空列表，用户以为没有记忆。
**危害**：P0 —— 静默把数据丢失伪装成「没有数据」。
**建议**：改 do-catch，失败时设 errorMessage state 并展示。

### 4. MemorySettingsTab.swift:201,327 — try? 吞掉记忆写入/更新失败

与 AddMemorySheet 同类问题：记忆添加和编辑保存都用 try? 静默吞错误。
**危害**：P0
**建议**：同上，改 do-catch + toast。

### 5. StickerStyleSheet.swift:223 — catch 块只重置 UI 状态，不报告错误

```
} catch {
    await MainActor.run { isRendering = false }
}
```

**问题**：贴纸滤镜/描边渲染失败时，用户只看到 loading 消失但没有预览更新，不知道出了什么问题。
**危害**：P0 —— 静默失败，用户可能反复重试。
**建议**：catch 里加 toast 或 error state 展示具体原因。

### 6. FileLibraryPanelView.swift:66,231,240 — try? 吞掉远程文件操作结果

```
try? await NotebookRemoteStore.write(f.path, content: newContent)
try? await NotebookRemoteStore.write(name, content: "")
try? await NotebookRemoteStore.delete(p)
```

**问题**：文件写入/创建/删除失败时用户无感知，以为操作成功。
**危害**：P0 —— 静默数据操作失败。
**建议**：改 do-catch，失败时 set remoteError 展示。

### 7. ImportHistoryView.swift:101,118-121 — 撤销导入错误处理不完整

fetch 用 try? 吞错误（:101），循环中 catch 只 reset isDeleting 然后 return（:118-121），不告诉用户哪条失败了、已回滚到哪。
**危害**：P0 —— 导入撤销中途失败会让数据处于半回滚状态，用户不知道。
**建议**：catch 里记录失败条目信息并展示给用户。

### 8. AttachmentPreviewSheet.swift:165,170,175 — try? 吞掉临时文件写入失败

预览附件时写临时文件用 try?，文件写入失败会导致预览空白或 QuickLook 打不开。
**危害**：P0 —— 不严重（只影响预览），但用户会困惑。可降为 P1。
**建议**：写入失败时跳过该项并 toast 提示。

---

## P1 · 拖慢的

### 9. CardFlowView.swift:42-103 — makeBubbleView 闭包重建成本高

每次 body 重算都重建所有 BubbleView 的闭包参数（onToggleFavorite, onSwitchBranch, onRegenerate, onEdit, regexScripts, groupMembers）。虽然有 `.equatable()` 拦截，但闭包创建本身仍有开销，尤其 `regexScripts` 每次都 alloc 新数组。
**危害**：P1 —— 流式期间高频重算时累积。已有 equatable 缓解，但根因未解决。
**建议**：把 regexScripts 提升到 @State 级别按需刷新，闭包参数考虑用 id-based 比较。

### 10. ConsoleView.swift:655-674 / LogView.swift:136,150,154,157 / MemoBoardView.swift:189-198 — DateFormatter 每调用一次 alloc 一个

```
let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
```

反复出现的模式：在 helper function 里每次调用都新建 DateFormatter / ISO8601DateFormatter。DateFormatter 初始化开销大，在 ForEach 循环中被频繁调用时可见。
**危害**：P1 —— 列表长时微卡。
**建议**：统一用 `private static let` 缓存 formatter，或用 `.formatted()` API。

### 11. BookshelfView.swift:60 — 5秒定时器在书架页常驻刷新

```
.onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
    BookStore.refreshEntries(profileId: profileId, context: modelContext)
}
```

**问题**：只要书架页在视图树中就每 5 秒扫一次文件夹 + 同步 SwiftData 索引。如果用户不在书架页但视图未销毁（paging container 常驻），白跑。
**危害**：P1 —— 后台空转，尤其影响电池。
**建议**：加 scenePhase 检查或只在 onAppear 和 fileLibraryDidChange 通知时刷新。

### 12. MessageSegmentsView.swift:500-523 — computed property 里反复 JSON 反序列化

`query`, `errorMessage`, `sources` 三个 computed property 分别对同一个 JSON 字符串独立做 JSONSerialization。每次 body 重算这三个都要跑。
**危害**：P1 —— 每条搜索结果气泡每次 body 重算做 3 次 JSON 解析。
**建议**：改为一次解析，结果存 @State 或用 struct 缓存。

### 13. SidebarView.swift — 1877 行，30+ @State 变量

一个 View 文件承载了：对话列表、搜索（含高级筛选）、收藏气泡、回收站、标签管理、导出、项目跳转等全部侧边栏逻辑。
**危害**：P1 —— 任何一个 @State 变化都可能触发整个 body 重算。
**建议**：拆分为 SidebarListView / SidebarSearchView / SidebarFooterView 等子组件，各自管理自己的 state。

### 14. CardFlowView.swift — 2491 行，包含 CardFlowView + ChatInputBar + InputFieldContainer + BubbleView 扩展

文件包含 4 个完整的 struct，职责跨越消息流、输入栏、模型选择、贴纸面板。
**危害**：P1 —— 维护成本高，改一处容易踩另一处。
**建议**：ChatInputBar 和 InputFieldContainer 拆到独立文件。

### 15. PersonaSettingsTab.swift:250-251 — exportPreset 是空函数

```
private func exportPreset(_ preset: Preset) {
}
```

被两处 call site 调用（:156, :1416），点击后什么都不会发生。
**危害**：P1 —— 用户以为导出了但实际没有。
**建议**：要么实现，要么移除菜单项和函数。

---

## P2 · 屎山本身

### 16. GlassBackButton.swift — 整个文件无 call site

`GlassBackButton` 在整个项目中没有任何引用。
**危害**：P2 —— 死代码。
**建议**：删除。

### 17. RegexSettingsTab.swift — 整个文件无外部 call site

`RegexSettingsTab` 只在自身文件内引用（内嵌使用 RegexScriptEditor），但 RegexSettingsTab 本身从未被外部引用。
**危害**：P2 —— 死代码。
**建议**：确认是否有 NavigationLink 动态引用，如果没有则删除。

### 18. PersonaSettingsTab.swift — 1619 行

包含：预设管理、采样参数、系统提示词编辑（macOS/iOS 双布局）、角色卡导入/导出、正则脚本管理。
**危害**：P2 —— 太大，但目前能跑。
**建议**：待有精力时拆分，优先级低于 P0/P1。

### 19. MedsSheet.swift:94 — 条件安全但风格不好的 force unwrap

```
ForEach(snap!.meds) { med in medRow(med) }
```

逻辑上安全（else 分支已覆盖 snap==nil 的情况），但依赖非本地推理。
**危害**：P2 —— 目前不会崩，但改动上下文后可能崩。**可不改**。
**建议**：改成 `ForEach(snap?.meds ?? [])` 更防御性。

### 20. HealthPanelView.swift:570 — 条件安全但风格不好的 force unwrap

```
_remainingInput = State(initialValue: (med?.remaining ?? 0) > 0 ? HealthPanelView.numText(med!.remaining) : "")
```

同上，逻辑安全但脆弱。
**危害**：P2 —— **可不改**。
**建议**：改成 `med.map { HealthPanelView.numText($0.remaining) } ?? ""`。

### 21. BranchMapSheet.swift:461 — 条件安全的 force unwrap

```
id: chain.first!
```

在 `chain.count >= 2` guard 内，安全。
**危害**：P2 —— **可不改**。

### 22. MiniBrowserView.swift:22 — .first! force unwrap

```
let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
```

实际上 applicationSupportDirectory 在 iOS 上永远有值，但理论上可以用 guard let。
**危害**：P2 —— **可不改**（系统 API 保证非空）。

### 23. TokenStatsView.swift:20-43 — UserDefaults 存储 2000 条 token 记录

用 UserDefaults 存大量 JSON 数据，每次 append 都全量 load + save。
**危害**：P2 —— 数据量大时 encode/decode 成本高，但 2000 条上限控住了。
**建议**：未来可迁移到 SwiftData 或文件存储。**可不改**。

### 24. AnniversaryView.swift:41-53 — 同样用 UserDefaults 存 JSON

与 TokenStatsView 同模式，数据量小，不是问题。
**危害**：P2 —— **可不改**。

### 25. DebugSettingsTab.swift (IOSDebugPage) — 文件名与 struct 名不一致

文件名 `DebugSettingsTab.swift`，实际 struct 名 `IOSDebugPage`。
**危害**：P2 —— 找代码时会困惑。**可不改**。

### 26. CareView.swift:207 — DateFormatter 在 map 回调中 alloc

```
private func dayLabel(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "M.d"; return f.string(from: d)
}
```

在 7 天趋势图中被 `.map` 调用 7 次，每次新建 formatter。数据量小，影响微弱。
**危害**：P2 —— **可不改**（只 7 次）。

### 27. ImportView.swift:589-590 — try? 连续两行吞文件操作

```
try? FileManager.default.removeItem(at: tempURL)
try? FileManager.default.copyItem(at: url, to: tempURL)
```

复制源文件到临时目录，如果 copyItem 失败会导致后续导入操作读不到文件。但导入器自身应该会报错。
**危害**：P2 —— 导入器会兜底报错。
**建议**：copyItem 改 do-catch 明确报错更好。

### 28. SleepSheet.swift:152,161 — try? modelContext.save() 吞错误

保存睡眠记录失败时静默。
**危害**：P2 —— 睡眠数据不是高频操作，丢一次不致命但不好。
**建议**：改 do-catch + toast。优先级低于记忆写入。

### 29. GroupMembersSheet.swift:122 — try? modelContext.save() 吞错误

群成员修改后保存失败静默。
**危害**：P2 —— 同上。

---

## 总结

| 等级 | 数量 | 主要类型 |
|------|------|---------|
| P0   | 8    | 静默失败（try? 吞数据操作错误）、双源数据不一致 |
| P1   | 7    | 性能（DateFormatter alloc、JSON 重解析、空转定时器）、超长文件、空函数 |
| P2   | 13   | 死代码、风格问题、低风险 force unwrap |

**最值得动的前 3 件事**：
1. P0 记忆相关的 try? 全部改 do-catch + toast（AddMemorySheet、MemoryPanelView、MemorySettingsTab）—— 记忆是核心功能，静默丢失最痛。
2. P0 FileLibraryPanelView 远程文件操作 try? 改 do-catch —— 文件操作失败用户会以为成功。
3. P1 exportPreset 空函数 —— 用户点了没反应，修复或移除只需一步。

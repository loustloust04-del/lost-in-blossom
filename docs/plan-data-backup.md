# Plan：数据与备份（导入导出重构）

**branch**: `feature/data-backup`
**worktree**: `.claude/worktrees/data-backup`
**research**: `docs/research-data-backup.md`（已 approved）
**status**: plan — 粟粟批注后进入 implement

---

## 已确认的设计（粟粟 approved）

- **Q1**：D2 指 (a) **和** (b)。即 **「数据与备份」tab 里加导入按钮** + **新建楼层 sheet 里加导入按钮**，两处都补。
- **Q2**：新建楼层交互选 **A** —— 楼层创建成功后**自动**弹 ImportView。（用户不想导入随时 dismiss。）
- **Q3**：全局导出选 **语义 A** —— 遍历所有楼层，每楼层一个子文件夹，里面是 `.md`。不做整包 zip。
- **Q4**：图标让我定 —— 我选 **`archivebox`**（档案盒，贴「备份」语义，线条风格与其他 tab 图标协调）。
- **Q5**：按钮命名选 **(b)** —— 「**导出本楼层数据**」+「**导出全部数据**」。现在只导 md，但命名为「数据」给未来扩展（角色卡/世界书/预设/记忆）留口子。

---

## 架构变化地图

```
设置 → 「数据与备份」 tab (rename from 「导入导出」)
  ├─ [NEW] 导入 section
  │    └─ 「导入对话」按钮 → 打开 ImportView sheet
  ├─ 导出 section
  │    ├─ 模式选择（轻量/全面）— 保持
  │    ├─ 「导出本楼层数据」按钮（rename from「导出全部对话」）
  │    └─ [NEW] 「导出全部数据」按钮 → 遍历 profiles，逐楼层导出到子文件夹
  └─ 导入历史 section — 保持

新建楼层 (ProfileEditorSheet, mode == .create)
  保存成功 → [NEW] 自动弹 ImportView
```

---

## Task Checklist

> 规则：每项做完立刻 `xcodegen generate && xcodebuild build`，过了才勾；UI 改动小步迭代；方向错了 revert 不打补丁。

### 1. D1 改名（「导入导出」→「数据与备份」）

- [ ] **1.1** `Views/SettingsView.swift:28` enum 值：`case data = "数据与备份"`
- [ ] **1.2** `Views/SettingsView.swift:53` iOS list 行 title：`"导入导出"` → `"数据与备份"`；icon：`"square.and.arrow.up.on.square"` → `"archivebox"`
- [ ] **1.3** `Views/DataSettingsTab.swift:114` iOS `.navigationTitle("导入导出")` → `"数据与备份"`
- [ ] **1.4** build 验证。

### 2. D4 导出按钮改造（文案 + 新按钮）

- [ ] **2.1** `Views/DataSettingsTab.swift` 把「导出全部对话」按钮文案改为 **「导出本楼层数据」**（macOS + iOS 两个 body）。
- [ ] **2.2** 新增 `exportAllProfilesData()` 方法：
  - 接 `profileManager.profiles` 参数（通过 `@Environment(ProfileManager.self)` 注入到 DataSettingsTab）
  - NSOpenPanel 选根目录
  - 遍历 profiles：
    - `let container = ProfileManager.makeContainer(for: profile)`
    - `let bgContext = ModelContext(container)`
    - fetch conversations，`MarkdownExporter.loadAndExport(...)` 导出
    - 输出到 `根目录/{sanitize(profile.name)}/{conv_title}.md`
  - 进度条（总量 = Σ 各楼层 conv 数）
- [ ] **2.3** 新增按钮 **「导出全部数据」**，放在「导出本楼层数据」下方。iOS 平台 return（和现有行为一致）。
- [ ] **2.4** DataSettingsTab 注入 `@Environment(ProfileManager.self) private var profileManager: ProfileManager?`。
- [ ] **2.5** build 验证 + macOS 跑一下确认全局导出能产出 `{楼层名}/*.md` 结构。

### 3. D2 在「数据与备份」tab 加「导入对话」按钮

- [ ] **3.1** `Views/DataSettingsTab.swift` 加 `@State private var showImporter = false`
- [ ] **3.2** 在最顶部加「导入」section（macOS body + iOS body 两份）：
  - 按钮「导入对话」，icon `square.and.arrow.down`，点击 `showImporter = true`
  - 小提示文字「支持 ChatGPT / Claude 导出包」
- [ ] **3.3** 挂 `.sheet(isPresented: $showImporter) { ImportView() }` （iOS 加 `.presentationDetents([.large])`，和 ContentView 里现有的保持一致）
- [ ] **3.4** build 验证。

### 4. D3 新建楼层保存后自动弹 ImportView

- [ ] **4.1** `MemoryPalaceApp.swift` `ProfileEditorSheet`：
  - 加 `@State private var pendingImportAfterCreate = false`
  - 保存流程里，**只在 `mode == .create`** 时：保存 profile → 置 `pendingImportAfterCreate = true` → dismiss
- [ ] **4.2** 找 ProfileEditorSheet 的调用方（sheet presenter）：
  - 接 sheet dismiss 回调，检查 `pendingImportAfterCreate`（可能需要把这个 flag 上提到 caller，或用 callback）
  - 简化方案：ProfileEditorSheet 加 `onCreate: ((Profile) -> Void)? = nil` 回调，保存成功 + create mode 时调 `onCreate(newProfile)`，然后 dismiss
  - caller 在回调里置自己的 `showImporter = true`
- [ ] **4.3** 确认 caller 层已经有/可加 `@State showImporter` + `.sheet { ImportView() }`（如果它已有这个 state，直接复用；没有就新增）
- [ ] **4.4** build 验证 + 跑 app 确认：
  - 新建楼层保存后，ImportView 自动弹出
  - ImportView 里取消 → 回到正常状态，楼层已创建
  - 编辑现有楼层（mode == .edit）保存 → **不**弹 ImportView

### 5. 收尾

- [ ] **5.1** 全局扫「导入导出」字面量确认无遗漏（Grep `导入导出` across MemoryPalace/）。
- [ ] **5.2** 全部 build 通过 + 跑 app 过一遍 3 个关键路径（数据与备份 tab 导入、导出本楼层、新建楼层自动弹）。
- [ ] **5.3** `git add` + commit（message 参考：`feat: 「导入导出」→「数据与备份」重构，补全导入入口 + 全局导出`）。
- [ ] **5.4** `git push -u origin feature/data-backup`。

---

## 明确**不做**的事（避免范围蔓延）

- ❌ 不做语义 B 整包备份 zip（SwiftData store 打包、schema 版本、恢复合并）— 留 Phase 1.5+
- ❌ 不扩展导出内容到角色卡/世界书/预设/记忆（按钮名叫「数据」只是为未来铺路）
- ❌ 不改 iOS 的导出限制（iOS 还是 return，因为 NSOpenPanel 是 macOS 独有，iOS 需要 `UIDocumentPickerViewController` 另做）
- ❌ 不改现有的 3 处导入入口（sidebar ➕ / DetailTopBar「导入」/ EmptyStateView）— 它们仍保留，这次只是**增加**数据与备份 tab 和新建楼层两处入口
- ❌ 不动 ImportHistoryView（导入历史）

---

## 跑 app 前提醒（给自己看）

粟粟授权我自己跑 worktree 的 Xcode。但这是 UI 敏感区，**小步迭代**：
- 改完 **1 (D1 改名)** 就 run 一次，确认 tab 名字和图标没看错
- 改完 **2 (导出改造)** 再 run 一次，验证「导出本楼层数据」和「导出全部数据」两个按钮都能触发、NSOpenPanel 弹出、导出成功
- 改完 **3 (tab 导入按钮)** 再 run，确认 sheet 能开
- 改完 **4 (新建楼层弹 ImportView)** 再 run，这是最 tricky 的（sheet 栈可能冲突）

每 run 一次前确认：主仓库或其他 worktree 的 app 实例没在跑。

---

## 风险 / 注意

1. **Sheet 栈冲突（Task 4）**：ProfileEditorSheet 还没完全 dismiss 就弹 ImportView，SwiftUI 可能静默失败。可能需要用 `.onDisappear` 或 0.3s 延迟来规避。实施阶段遇到就处理。
2. **全局导出慢**：遍历每个楼层开 container + fetch，大楼层可能卡。现有单楼层导出在 `DispatchQueue.global(qos: .userInitiated)` 里做，全局版本沿用同样模式（backgrounding）。
3. **`makeContainer` 是 `fatalError` 路径**：如果某个楼层 container 创建失败，会 crash 整个 app。风险低（线上用户的 profile 已经 run 过一次都没崩），本次 PR 不改成 throws——后续技术债。
4. **图标切换用户感知**：粟粟对 UI 变动敏感；`archivebox` 如果她不喜欢，plan checklist 1.2 这一项可以回滚不影响其他（独立原子）。
5. **新建楼层自动弹 ImportView 的"烦"感**：如果粟粟只想建个空楼层，每次都要多一次 dismiss。本次按 Q2 = A 做；如果她反馈"烦"，改成 Q2 = B（「创建并导入」单独按钮）只需局部改动 Task 4，不影响其他。

---

## 粟粟批注区

（粟粟批完意见，我进入 implement。）

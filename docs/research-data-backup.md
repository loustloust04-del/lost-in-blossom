# Research：数据与备份（导入导出重构）

**branch**: `feature/data-backup`
**worktree**: `.claude/worktrees/data-backup`
**date**: 2026-04-19
**status**: research — 等粟粟批注后进入 plan

---

## 粟粟的诉求（roadmap line 246）

> **导入导出改名为数据与备份｜现在的导入 conversation 键消失了｜全局所有数据导出，楼层导出｜新建楼层没看见导入 conv 按钮**

拆成 4 件事：

| # | 诉求 | 类别 |
|---|------|------|
| D1 | 「导入导出」tab → 改名「数据与备份」 | 改名 |
| D2 | 「导入 conversation 键消失了」 | Bug 修复 |
| D3 | 新建楼层里看不见导入 conv 按钮 | Bug 修复 / 功能补齐 |
| D4 | 「全局所有数据导出」+「楼层导出」两级 | 功能扩展 |

---

## 现状盘点

### 1. 「导入导出」tab（=现「数据与备份」的入口）

**位置**：`Views/DataSettingsTab.swift` + 注册在 `Views/SettingsView.swift:28`

```swift
enum SettingsTab: String, CaseIterable {
    ...
    case data = "导入导出"       // ← 粟粟要改成「数据与备份」
}
```

**tab 内现有内容**（DataSettingsTab）：
- **导出** section：
  - 模式选择：轻量（最长分支）/ 全面（全部路径折叠）
  - 「导出全部对话」按钮（只支持 macOS，iOS 直接 return）
  - 底下一行提示「右键对话可单独导出为 Markdown」
- **导入历史** section（`ImportHistoryView`）：展示历次导入记录 + 支持撤回

**⚠️ 没有「导入」按钮**。主动导入只能从别处触发。

### 2. 主动导入入口（当前 3 处）

| 位置 | 触发方式 | 平台 |
|---|---|---|
| `SidebarView.swift:144` | 侧边栏标题行 ➕ 按钮 | macOS only |
| `ContentView.swift:497` `DetailTopBar「导入」按钮` | 主面板顶部栏（选中对话时？需确认） | 双端 |
| `ContentView.swift:699` `EmptyStateView「导入 conversations.json」` | 楼层无对话时的空态 CTA | 双端 |

都通过 `@State showImporter = true` 打开 `ImportView` sheet。ImportView 支持 ChatGPT + Claude 两种 provider。

### 3. 新建/编辑楼层 Sheet（`ProfileEditorSheet`，在 `MemoryPalaceApp.swift:516`）

现有导入能力：
- `showFileImporter`（line 577）— **只导入角色卡**（TavernCard JSON/PNG），会自动填充楼层名/assistantName/emoji 等
- **没有 conversation 导入入口**

### 4. 导出现状（粒度）

`DataSettingsTab.exportAllConversations()`（line 119-185）：
- 用的是 `@Environment(\.modelContext)` —— 是**当前楼层**的 SwiftData context
- `FetchDescriptor<Conversation>` 拿当前楼层全部对话（含删除过滤），逐条导出为 `.md`
- 所以按钮名叫「导出**全部**对话」，但实际范围=**当前楼层**。

**跨楼层的「全局数据导出」不存在。**

还可以单条导出：`ExportOptionsSheet`（右键对话触发）。

### 5. Git log 核验：导入 conv 键"消失"考古

| 查询 | 结果 |
|---|---|
| `git log -S "导入 conversations"` | 只命中初始提交 `4aa3a59`，之后无变更 |
| `git log DataSettingsTab.swift` | 一次提交（`6ab5076` 从 SettingsView 拆出来），拆出来**就没有导入按钮** |

所以严格来讲「导入 conv 键消失」**在 git 历史里找不到被删除的证据**——可能的解读：
- 粟粟记忆中某个早期版本有（已无法核对），**或**
- 粟粟指的其实就是 **D3（新建楼层里没有）**，两句话说的是同一件事

写 research 阶段倾向后者解读，但要向粟粟确认。

---

## 现象→设计点映射

### D1 改名：「导入导出」 → 「数据与备份」

- 改 `SettingsView.swift:28`：`case data = "数据与备份"`
- 改 `SettingsView.swift:53`（iOS list 行 title 显式写死「导入导出」）：换成「数据与备份」
- 改 `DataSettingsTab.swift:114`：`.navigationTitle("导入导出")` → `"数据与备份"`
- 图标现在是 `square.and.arrow.up.on.square`（导出箭头）——改名后语义偏了，建议改成 `externaldrive` 或 `tray.and.arrow.down.and.arrow.up`。**待粟粟定。**

### D2 + D3 修 Bug：补回导入按钮

**D2 解读不确定**——要问粟粟到底指哪个位置。候选：
- (a) 设置 →「数据与备份」tab 里应该有「导入对话」按钮（现在没有）
- (b) 新建楼层 sheet 里应该有（= D3，重复表达）
- (c) 某个我没发现的位置

**D3 明确**：`ProfileEditorSheet` 里角色卡导入按钮之外，应再加一个「导入 ChatGPT/Claude 对话」按钮。
- 交互设计：楼层创建**完成前**导入？还是楼层创建成功后立刻跳 ImportView？
  - 选项 A：楼层创建成功后自动弹 ImportView（`showImporter = true` 在保存后触发）
  - 选项 B：sheet 里加「创建并导入」按钮，二连击
  - 选项 C：sheet 里加一个按钮直接打开 ImportView，但先 apply 当前表单（风险：用户没保存楼层就跳出）

  **我的倾向**：选项 A（楼层创建成功 → auto 弹 ImportView）。理由：用户新建楼层的典型意图就是「建个空间装 ChatGPT/Claude 的对话」，一条龙最顺。

### D4 两级导出

现有「导出全部对话」=**当前楼层导出**（范围已经是这个，只是名字没标明）。

需要加的是**跨楼层的全局导出**。语义要先和粟粟对齐：

**语义 A（简单）**：遍历所有楼层，对每个楼层做现有的"导出对话为 md"，输出到 `export/{楼层名}/*.md`
- 优点：直观、实现简单
- 缺点：只导 conversation.md，不含角色卡 / 世界书 / 预设 / 记忆 / 贴纸 / 正则 / 设置——那还叫「数据」不叫「全部数据」

**语义 B（完整）**：真 backup——导出 app 的全部用户数据
- 所有楼层（Profile + SwiftData store 文件整包打包）
- `~/Library/Application Support/MemoryPalace/*.store` 直接打包进 zip
- UserDefaults（选择性序列化 key）
- 贴纸文件
- 输出：`MemoryPalace-backup-{日期}.zip`
- 对称地，要有**导入/恢复**能力（打开 backup zip → 覆盖或合并本地数据）
- 优点：真正叫「备份」。粟粟说 roadmap X8 要"开源准备"，备份/还原是用户级关键功能
- 缺点：复杂度高得多（schema 版本、合并策略、冲突处理）

**中间方案**：
- **语义 A + 部分数据**：所有楼层对话 md + 每个楼层的预设 JSON + 角色卡文件 + 世界书 JSON —— 不打包整个 SwiftData store
- 好处：用户得到**可读的导出**（md 可以直接查看），不绑死在 app 里

---

## 建议方案（阶段化）

### 阶段一（本次 PR）：改名 + 修 Bug + 楼层导出清晰化

- ✅ D1 改名到位（3 处）+ 图标可选换
- ✅ D2/D3 新建楼层 sheet 加「导入对话」按钮（倾向选项 A：楼层创建成功后弹 ImportView）
- ✅ D2 如果粟粟确认「数据与备份」tab 内也要有一个常驻「导入对话」按钮，同步加
- ✅ D4 当前「导出全部对话」→ 改文案为「导出当前楼层对话」，并加一个**新按钮**「导出全部楼层对话（跨楼层）」走语义 A：遍历 ProfileManager.allProfiles，每个 profile 建独立 bgContext，输出到 `选定文件夹/{楼层名}/*.md`

### 阶段二（另开 PR 或 Phase 1.5+）：完整备份能力

- 语义 B 整包 backup/restore
- schema 版本号、迁移策略
- 安全风险（API key 导不导出？）

**本次 PR 不做阶段二。**

---

## 问 Susu 的问题

### Q1：D2「导入 conversation 键消失了」具体指哪里？

- (a) 设置 →「数据与备份」tab 里应有一个「导入对话」按钮（现在没有）✅
- (b) 就是 D3 = 新建楼层里（上下两句在说同一件事）✅
- (c) 别的位置，请指明

### Q2：新建楼层里的导入 conv 按钮，交互方式偏好？

- A（**推荐**）：楼层创建**成功后自动弹** ImportView（一条龙）✅
- B：sheet 里加「创建并导入」按钮，点一下先保存再弹
- C：sheet 里直接点「导入对话」会先保存楼层、再跳到 ImportView

### Q3：D4「全局所有数据导出」要做到哪一层？

- 语义 A：遍历所有楼层，每楼层一个子文件夹，全是 `.md`（简单，**本次 PR 建议做到这层**）✅
- 语义 A+：加上角色卡/世界书/预设 JSON 一起打包（可读导出包）
- 语义 B：整包备份 zip（含 SwiftData store），完整 backup/restore（**不建议本次 PR 做**，工作量巨大）

### Q4：tab 图标是否换？

- 现在：`square.and.arrow.up.on.square`（导出箭头）
- 改名后语义偏了，候选：`externaldrive` / `tray.and.arrow.down.and.arrow.up` / `archivebox` / `internaldrive`
- 粟粟定或让我选【看不懂你选】

### Q5：导出文案是否区分「对话」vs「数据」？

阶段一只导 markdown 对话，按钮名偏好：
- (a) 「导出当前楼层对话」+「导出全部楼层对话」
- (b) 「导出本楼层数据」+「导出全部数据」（用「数据」暗示未来能包含更多）✅
- (c) 其他

---

## 下一步

粟粟回答 Q1-Q5 后，我写 plan（含 task checklist）。

**不动代码，等批注。**

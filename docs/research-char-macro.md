# Research：文案 / 宏替换（酒馆风格）

**branch**: `feature/char-macro`
**worktree**: `.claude/worktrees/char-macro`
**date**: 2026-04-19
**status**: research — 等粟粟批注后进入 plan

---

## 粟粟的需求（我的理解）

- **目标**：所有「带名字」的文案模板化，不再硬编码「小雾」。
- **风格**：学酒馆，用 `{{char}}` `{{user}}` 这种双花括号宏。
- **例子**：MemoryPanelView 里「和**小雾**聊天时会自动记住重要的事」→「和**{{char}}**聊天时会自动记住重要的事」，展示时根据当前楼层的 `assistantName` 展开。
- **本质**：这不是「改几个字」，是**文案宏系统的基建**——以后加角色卡 / 多楼层，UI 文案自动跟随角色名变，不用改 Swift。

---

## 现状盘点

### 1. 「小雾」在哪里硬编码？

| 文件 | 行 | 类型 | 要不要改 |
|---|---|---|---|
| `Views/MemoryPanelView.swift` | 147 | **真 UI 文案**：`Text("和小雾聊天时会自动记住重要的事")` | ✅ 改 `{{char}}` |
| `MemoryPalaceApp.swift` | 83 | 楼层默认 description `"小雾的家"` | ⚠️ 待定（见问题 Q3） |
| `MemoryPalaceApp.swift` | 85 | 楼层默认 assistantName `"小雾"` | ❌ 这是默认**值**不是文案 |
| `MemoryPalaceApp.swift` | 95–96 | 第二楼层默认 `"小克"` | ❌ 同上，默认值 |
| `Views/*.swift` × 8 处 | — | `@AppStorage("assistantName") = "小雾"` | ❌ fallback default，用户改过就不出现 |
| `Utils/Theme.swift` | 9 | 注释 `// 小雾气泡` | ❌ 注释 |

**结论**：**真正需要宏替换的 UI 文案，目前只有 1 处**（MemoryPanelView.swift:147）。

所以这个 feature 的产出不是「替换几个字」，而是**铺宏系统基建，让未来的文案可以直接写 `{{char}}` 不犯愁**。

### 2. 现有宏系统：**已存在但分散**

三处独立实现，逻辑重复，只支持 `{{user}}` / `{{char}}`：

| 位置 | 函数 | 用途 |
|---|---|---|
| `Services/PromptAssembler.swift:264` | `applyMacros(_:profile:)` | prompt 组装阶段 |
| `Services/WorldBookScanner.swift:128` | 内联 `replacingOccurrences` | 世界书条目展开 |
| `Models/RegexScript.swift:98, 128` | 内联 `replacingOccurrences` × 2 | 正则脚本 find / replace 两端 |

**问题**：
- 三处各自 `replacingOccurrences`，将来加 `{{time}}` `{{date}}` 要改三份。
- UI 文案层（SwiftUI Text）**没有任何宏支持**，硬编码只能死写。
- `MemoryService.swift:274` 用的 `{{MEMORIES}}` 是另一种占位符语义（一次性模板填充），**不是用户面向的宏**，不应混入。

### 3. 数据源架构（重要）

```
Profile (SwiftData, per-楼层)
  ├─ userName: String       ← source of truth
  └─ assistantName: String  ← source of truth
          │
          │ MemoryPalaceApp.swift:130 / 150 切楼层时同步
          ▼
UserDefaults ("userName", "assistantName")
          │
          │ @AppStorage 读
          ▼
SwiftUI Views
```

- **Profile 是 SSOT**，`@AppStorage` 是 cached view（切楼层时被刷新）。
- **任何宏展开都应该从 Profile 拿值**，不要直接读 @AppStorage（免得在楼层切换的瞬间读到旧值）。
- `CardFlowView.swift:707` 有 fallback：`Profile(..., userName: "你", assistantName: "AI")` — profile 缺失时 AI 名用 `"AI"` 而非 `"小雾"`，合理。

### 4. 酒馆宏参考清单（SillyTavern）

全部参考，**不是都要做**：

**Identity（本次范围候选）**
- `{{user}}` — 用户名 ✅ 已有
- `{{char}}` — 角色名 ✅ 已有
- `{{persona}}` — 用户 persona 描述 ✅ 已有
- `{{description}}` / `{{personality}}` / `{{scenario}}` ✅ 已有（角色卡字段）

**Time/Date（低成本，易加）**
- `{{time}}` — 当前时间 HH:mm
- `{{date}}` — 当前日期
- `{{weekday}}` — 星期几
- `{{isotime}}` — ISO 8601

**Random（非幂等，渲染每次结果不同）**
- `{{random:A,B,C}}` — 随机挑一个
- `{{pick:A,B,C}}` — 按种子挑一个（本会话幂等）
- `{{roll:N}}` / `{{roll:XdY}}` — 掷骰子

**Control**
- `{{newline}}`
- `{{//注释}}`

**Dynamic（需要运行时上下文）**
- `{{input}}` — 当前用户输入
- `{{lastMessage}}` / `{{lastUserMessage}}`

---

## 建议方案

### 阶段一（这次 PR 做）：抽统一 MacroExpander + UI 文案接入

1. 新建 `Services/MacroExpander.swift`，提供：
   ```swift
   struct MacroExpander {
       static func expand(_ text: String, profile: Profile) -> String
       // 仅支持当前已有宏：{{user}} {{char}} {{persona}} {{description}} {{personality}} {{scenario}}
   }
   ```
2. 三处旧 `applyMacros` / 内联替换 → 全部改调用 `MacroExpander.expand`。
3. UI 文案层接入：
   - 提供 `View` 扩展 `.expandMacros(profile:)` 或 `Text` 工厂 `MacroText("和{{char}}聊天...", profile:)`
   - 改 `MemoryPanelView.swift:147` 示例落地
4. 扫一遍所有面向用户的 `Text("...")`，把**未来可能涉及角色名的表述**预留 `{{char}}` / `{{user}}`（这次 PR 不大改，只示范一两处）。

**不做**的事：
- ❌ 不新增酒馆宏（time/date/random/...）— 放阶段二
- ❌ 不改 `@AppStorage` → `@Environment` — 范围蔓延
- ❌ 不动 `MemoryService.swift` 的 `{{MEMORIES}}` — 另一种语义

### 阶段二（未来另开 PR）：扩展酒馆宏

按需加 `{{time}}` `{{date}}` `{{random}}` ...，每种加测试。**本次不做，留接口。**

---

## 问 Susu 的问题

### Q1：UI 文案层接入方式，两个选择

**A. `MacroText` 专用组件**
```swift
MacroText("和{{char}}聊天时会自动记住重要的事")
// 内部读 ProfileManager.currentProfile, 调 MacroExpander.expand
```
优：调用点干净；缺：失去 `Text` 的所有 modifier 拼接能力。

**B. `String` 扩展 + 普通 `Text`**
```swift
Text("和{{char}}聊天时会自动记住重要的事".expandingMacros(profile: profile))
```
优：保留 `Text` 全部能力，可拼 `+`、可 `.bold()`；缺：每个调用点要拿 profile。

**我倾向 B**——SwiftUI modifier 链是核心生产力，不想为了封装牺牲。profile 可通过 `@Environment(ProfileManager.self)` 拿到，一行代码。

粟粟选哪个？

### Q2：这次只做 `{{user}}` `{{char}}` `{{persona}}` 等**已有**宏的统一，**不加**酒馆的 time/date/random。对吗？

（我的建议是 yes，先打地基，加宏留给后续 PR。）

### Q3：`MemoryPalaceApp.swift:83` 楼层默认 description `"小雾的家"` 要不要宏化？

- 改为 `"{{char}}的家"` → 楼层创建时展开（或保存含宏的原文、显示时展开）
- 若保存含宏原文：用户之后改了 assistantName，description 自动跟着变
- 若创建时展开：用户改 AI 名后，楼层描述还是「小雾的家」—— 不跟随

粟粟偏好哪种？（酒馆风格是「保存原文、显示时展开」。）

### Q4：`CardFlowView.swift:707` fallback `Profile(..., assistantName: "AI")` 要不要也统一成 `{{char}}` 无 profile 时显示什么？

（我倾向：profile 为 nil 时不展开宏，直接显示原文「{{char}}」不好看——这个 fallback 其实是死代码还是真的会发生？需要粟粟确认。）

---

## 下一步

粟粟在这份 doc 里批注（或口头回复）上面 4 个 Q 之后，我进入 plan 阶段，把方案拆成 task checklist 放 `docs/plan-char-macro.md`。

**不要我现在动代码。**

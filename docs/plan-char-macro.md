# Plan：文案 / 宏替换（酒馆风格）

**branch**: `feature/char-macro`
**worktree**: `.claude/worktrees/char-macro`
**research**: `docs/research-char-macro.md`（已 approved）
**status**: plan — 粟粟批注后进入 implement

---

## 已确认的设计（粟粟 approved）

- **Q1**：UI 接入用方案 B —— `String` 扩展 `.expandingMacros(profile:)`，配普通 `Text`。
- **Q2**：本次只统一**已有**宏（`{{user}}` `{{char}}` `{{persona}}` `{{description}}` `{{personality}}` `{{scenario}}`）。**不加** `{{time}} {{date}} {{random}}` 等，留将来 PR。
- **Q3**：楼层默认 description `"小雾的家"` **不动**，保留作示例。
- **Q4**：`CardFlowView:707` 的 profile-nil fallback 我自己处理（防御性代码，用户看不见）。
- **新增需求**：空值 fallback
  - `userName` 为空字符串 → `「你」`（与 CLAUDE.md 一致）
  - `assistantName` 为空字符串 → `「助手」`

---

## 架构

### MacroExpander（新建 `Services/MacroExpander.swift`）

两个公开 API，语义区分清晰：

```swift
enum MacroExpander {
    /// 通用展开：用于 prompt、world book、UI 文案、regex result 端
    static func expand(_ text: String, profile: Profile?) -> String

    /// Regex-safe 展开：用于 RegexScript.findRegex 宏替换
    /// - escape: true 时对 userName/charName 做 NSRegularExpression 转义
    static func expandForRegex(_ pattern: String, profile: Profile, escape: Bool) -> String
}
```

内部实现：

```swift
private static func resolvedName(_ raw: String, fallback: String) -> String {
    raw.isEmpty ? fallback : raw
}

// expand:
let user = resolvedName(profile?.userName ?? "", fallback: "你")
let char = resolvedName(profile?.assistantName ?? "", fallback: "助手")
let persona = profile?.userPersona ?? ""
// ...
return text
    .replacingOccurrences(of: "{{user}}", with: user)
    .replacingOccurrences(of: "{{char}}", with: char)
    .replacingOccurrences(of: "{{persona}}", with: persona)
    .replacingOccurrences(of: "{{description}}", with: profile?.characterDescription ?? "")
    .replacingOccurrences(of: "{{personality}}", with: profile?.characterPersonality ?? "")
    .replacingOccurrences(of: "{{scenario}}", with: profile?.scenario ?? "")
```

### String 扩展（`Extensions/String+Macros.swift`）

```swift
extension String {
    func expandingMacros(profile: Profile?) -> String {
        MacroExpander.expand(self, profile: profile)
    }
}
```

UI 调用点：

```swift
@Environment(ProfileManager.self) private var profileManager
// ...
Text("和{{char}}聊天时会自动记住重要的事".expandingMacros(profile: profileManager?.currentProfile))
```

---

## Task Checklist

> 规则：每项做完**立刻** `xcodegen generate && xcodebuild build`，通过了才勾；失败了先定位，方向错了 `git revert` 不打补丁。

### 1. 建地基

- [ ] **1.1** 新建 `MemoryPalace/Services/MacroExpander.swift`，实现 `expand` + `expandForRegex` 两个 API。
- [ ] **1.2** 新建 `MemoryPalace/Extensions/String+Macros.swift`，实现 `expandingMacros(profile:)`。
- [ ] **1.3** build 验证地基编译通过（未接入任何调用点）。

### 2. 迁移三处旧宏调用 → MacroExpander

- [ ] **2.1** `Services/PromptAssembler.swift:264` 的 `applyMacros` → 内部改调 `MacroExpander.expand`（保留函数名，或直接删函数、所有 call site 改调 Expander——先按前者，改动小）。
- [ ] **2.2** `Services/WorldBookScanner.swift:128-131` 的内联 `replacingOccurrences` → 改调 `MacroExpander.expand`。
- [ ] **2.3** `Models/RegexScript.swift:98-100`（find 端）→ 改调 `MacroExpander.expandForRegex`，传入 `substituteRegex == 2` 作为 `escape`。
- [ ] **2.4** `Models/RegexScript.swift:127-129`（result 端）→ 改调 `MacroExpander.expand`。
- [ ] **2.5** build 验证三处迁移后编译通过 + 行为一致（无逻辑变化）。

### 3. UI 文案层接入

- [ ] **3.1** `Views/MemoryPanelView.swift:147` 从 `Text("和小雾聊天时会自动记住重要的事")` 改为 `Text("和{{char}}聊天时会自动记住重要的事".expandingMacros(profile: ...))`。
  - 拿 profile 的方式：优先 `@Environment(ProfileManager.self)` → `currentProfile`；该 view 上下文里已经注入的话直接用，没注入则加注入。
- [ ] **3.2** build 验证。
- [ ] **3.3** 跑 app 手工验证（见【跑 app 前提醒】）：
  - 默认楼层：显示「和小雾聊天时会自动记住重要的事」✅
  - 切到第二楼层（小克）：显示「和小克聊天时会自动记住重要的事」✅
  - 把 AI 名字改成空：显示「和助手聊天时会自动记住重要的事」✅

### 4. 清理 & 收尾

- [ ] **4.1** 搜一遍 `grep -rn "replacingOccurrences.*{{" MemoryPalace/`，确认除 `MemoryService.swift:274`（`{{MEMORIES}}` 是另一语义，不动）外，没有遗漏的内联实现。
- [ ] **4.2** 所有测试仍通过（如果项目有 XCTest target；当前 research 未发现测试 target，这步可能是 no-op，确认下）。
- [ ] **4.3** `git add` + commit，message 规范参考最近 commit 风格（`feat: MacroExpander 统一 {{char}} {{user}} 等宏展开`）。
- [ ] **4.4** `git push` 到 GitHub。
- [ ] **4.5** 在主仓库（master）跟粟粟汇报：这个 worktree 可以回去合了 / 还是等后续阶段二再合。

---

## 跑 app 前提醒（给自己看）

- 此时主仓库有 5 个其他 worktree。SwiftData 数据库 `~/Library/Application Support/MemoryPalace/{profileId}.store` 是**全局共享的**。
- 跑 app 前**问粟粟一声**：「我这边要 run app 验证 UI 了，其他窗口是不是没在跑？」
- 确认后再 xcodebuild run / 开 Xcode run。

---

## 明确**不做**的事（避免范围蔓延）

- ❌ 不加 `{{time}}` `{{date}}` `{{weekday}}` `{{random}}` 等新宏
- ❌ 不动 `@AppStorage` → `@Environment` 架构
- ❌ 不改楼层默认 `"小雾的家"` 描述
- ❌ 不动 `Services/MemoryService.swift` 的 `{{MEMORIES}}` 占位符
- ❌ 不改 `Preset.swift` 的 `characterFormat/scenarioFormat/personaFormat` 里的宏（它们已经在走 `applyMacros` 后的链路，2.1 迁移后自动生效）
- ❌ 不遍历所有 `Text(...)` 把能改成 `{{char}}` 的都改（基建铺好就停，遇到硬编码再改）

---

## 风险 / 注意

1. **MacroExpander 当前接 `Profile?`** —— 记得传 optional 的 call site（UI 层）不要误写成强解包。
2. **RegexScript 迁移测试难** —— 用户未必立刻触发，可能有潜伏回归。合并前我会人工读一遍迁移前后 diff，确认 userReplacement/charReplacement 的变量在 expandForRegex 里等价还原。
3. **performance**：`expand` 每次 UI 渲染都跑 6 次 `replacingOccurrences`——对于短字符串（UI 文案）无感；如果将来用在长 prompt 且高频调用，考虑一次性正则编译。**本次不优化。**

---

## 粟粟批注区

（粟粟批完意见，我进入 implement。）

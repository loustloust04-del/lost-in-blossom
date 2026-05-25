# Plan: 资产管理层 — 角色卡库 + 世界书独立导入

> 右栏新增角色卡库 tab，世界书支持独立导入
> 日期：2026-04-13

---

## Task Checklist

### H1：角色卡持久化模型

- [ ] 新建 `Models/CharacterCard.swift`
  - SwiftData `@Model`，全局资产（不绑定楼层）
  - 字段：id, name, description, personality, scenario, firstMes, alternateGreetings, mesExample, systemPrompt, postHistoryInstructions, creatorNotes, imageData, characterBookName, characterBookEntriesData (JSON), createdAt
  - 从 `TavernCard` 转换的 init
- [ ] SwiftData schema 注册
- [ ] 注意：CharacterCard 是全局的，存在默认 store 里？不对 — 现在每个楼层各自有 store。全局资产需要一个共享 store。
  - 方案：CharacterCard 存 UserDefaults（JSON encode），和 Profile/Preset 一样
  - 或者：存到一个固定的全局 SwiftData store
  - 选择：用 UserDefaults JSON，和现有 Preset/Profile 模式一致，简单可靠

### H2：角色卡库管理器

- [ ] `CharacterCardManager`（和 PresetManager 类似）
  - 存 UserDefaults，key: `"savedCharacterCards"`
  - CRUD：import, delete, list
  - `importFromFile(url:)` → TavernCard.parseFile → 转存为 CharacterCard
  - `createFloor(from:profileManager:)` → 从卡创建楼层（复用现有 importCardContent 逻辑）

### H3：右栏角色卡库 Tab

- [ ] `RightPanelTab` 加 `.cardLibrary`
- [ ] tab 按钮："卡库"（icon: "person.crop.rectangle.stack"）
- [ ] 新建 `Views/CardLibraryPanelView.swift`
  - 顶部：导入按钮（从文件导入 PNG/JSON 到卡库）
  - 卡片列表：每张卡显示封面图缩略图 + 名称 + 描述摘要
  - 点卡 → 详情展开：创作者注释、字段预览、世界书条目数
  - 操作按钮："创建楼层"（一键从卡创建楼层）、"删除"
  - 空状态提示

### H4：世界书独立导入

- [ ] 世界书 tab 空状态下加"导入世界书"按钮
- [ ] fileImporter 选择 .json 文件
- [ ] 解析 JSON → 创建 WorldBook → 绑定到当前楼层
- [ ] 支持酒馆格式的世界书 JSON（entries 数组）

### H5：改造新建楼层流程

- [ ] 新建楼层 sheet 里"导入角色卡"改为两个入口：
  - "从文件导入" → 和现在一样直接选文件
  - "从卡库选择" → 弹出卡库列表选择
- [ ] 或者：简化为只保留"从卡库选择"，导入文件统一走右栏卡库

### H6：build + 重启 + commit + push

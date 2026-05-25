# Plan: 全局世界书 + 独立创建世界书

> 世界书从"只能跟着角色卡导入"升级为完整的独立资产
> 日期：2026-04-14

---

## 目标

1. 可以从零新建一本空白世界书，手动添加条目
2. 世界书可以设为"全局"——不绑定楼层，所有楼层都生效
3. 楼层设置里可以查看/添加/移除绑定的世界书

---

## 现状

- WorldBook 是 SwiftData @Model，存在楼层的 store 里，profileId 绑定楼层
- 全局世界书的问题：每个楼层有独立 SwiftData store，全局世界书需要跨 store 可见
- 解决方案：全局世界书存 UserDefaults（和 CharacterCard/Preset 一样），注入时合并

---

## Task Checklist

### K1：全局世界书存储

- [ ] 新建 `GlobalWorldBookManager`（@Observable, UserDefaults）
  - `var globalBooks: [GlobalWorldBook]` — Codable struct，不是 SwiftData
  - `GlobalWorldBook`：id, name, entries ([WorldBookEntry]), isEnabled, createdAt, updatedAt
  - CRUD：add, delete, update, toggleEnabled
  - 复用现有 `WorldBookEntry` struct（它已经是 Codable）
- [ ] 注入到 app environment

### K2：PromptAssembler / ConversationViewModel 合并全局世界书

- [ ] `assemblePrompt()` 里除了查询楼层绑定的 WorldBook，也查询 GlobalWorldBookManager 的 enabled 全局书
- [ ] 两者合并传入 `PromptAssembler.assemble(worldBooks:)`
- [ ] 全局世界书需要转成 `[WorldBook]` 或者 WorldBookScanner 直接接受 `[WorldBookEntry]`
  - 最简方案：WorldBookScanner.scan() 改为接受 `[[WorldBookEntry]]` 或者 `entries: [WorldBookEntry]`

### K3：世界书 tab 支持新建 + 全局

- [ ] 世界书 tab 顶部加"新建世界书"按钮（和导入并列）
  - 点击 → 弹 alert 输入名称 → 创建空白世界书（绑定到当前楼层）
  - 然后用现有的"+"按钮添加条目
- [ ] 世界书列表分两区：
  - **楼层世界书** — 绑定到当前楼层的（现有逻辑）
  - **全局世界书** — 所有楼层都生效的，带"全局"标签
- [ ] 全局世界书条目也可编辑/新增/删除（复用现有 WorldBookEntryEditor）
- [ ] 全局世界书有 enabled 开关（整本书开/关）

### K4：楼层设置绑定管理

- [ ] 在 Settings > 通用 tab 或楼层编辑 sheet 里加一小区域："已绑定的世界书"
  - 列出当前楼层 linkedWorldBookIDs 对应的世界书名称
  - 每个旁边有"解绑"按钮
  - 底部有"绑定更多"→ 弹出已有世界书选择列表
- [ ] 这个可能放 Phase 2，先做 K1-K3

### K5：build 双平台 + commit + push

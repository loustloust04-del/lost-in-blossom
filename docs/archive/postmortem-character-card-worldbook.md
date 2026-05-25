# 复盘：角色卡 & 世界书功能

> 分支：`research/character-card-worldbook`
> 基于：粟粟的架构决策文档 `architecture-character-worldbook.md`
> 日期：2026-04-14

---

## 一、架构文档 vs 实现对照

### 第二节：四种资源

| 资源 | 架构文档设计 | 实现状态 | 备注 |
|------|------------|---------|------|
| 预设 (Preset) | 全局资源，已有 | ✅ 不动 | — |
| 角色卡 (CharacterCard) | 全局角色卡库 | ✅ 已实现 | `CharacterCard` Codable + `CharacterCardManager` (UserDefaults)，右栏卡库 tab |
| 世界书 (WorldBook) | 全局资源，可绑定楼层 | ⚠️ 部分实现 | 模型 + 注入 + 编辑已完成，但**全局世界书**和**独立世界书库**未做 |
| 记忆 (Memory) | 楼层内部，AUDN | ✅ 已有 + 加了对话记忆开关 | `memoryEnabled` toggle |

### 第三节：角色卡字段映射

| TavernCard 字段 | 映射目标 | 状态 |
|----------------|---------|------|
| description → characterDescription | ✅ |
| personality → characterPersonality | ✅ |
| scenario → scenario | ✅ |
| first_mes → 首条 assistant 消息 | ✅ |
| alternate_greetings → 多个独立对话 | ✅ |
| mes_example → chatExamples | ✅ |
| system_prompt → systemPrompt | ✅ |
| post_history_instructions → postInstructions | ✅ |
| creator_notes → UI 显示 | ✅ 卡库详情里展示 |
| character_book → WorldBook 实例 | ✅ |

### 第四节：世界书条目数据模型

| 字段 | 状态 | 备注 |
|------|------|------|
| keys / secondaryKeys / selectiveLogic | ✅ | AND_ANY/NOT_ALL/NOT_ANY/AND_ALL |
| scanDepth / matchWholeWords / caseSensitive | ✅ | |
| isConstant | ✅ | 常驻注入 |
| content / position / insertionOrder / depth | ✅ | 7 种注入位置 |
| comment / probability | ✅ | |
| group / group_override | ❌ 未实现 | 互斥逻辑，低优先级 |

### 第五节：世界书注入流程

| 步骤 | 状态 | 备注 |
|------|------|------|
| 收集激活的世界书 | ✅ | 当前楼层绑定的 |
| 扫描最近 N 条消息 | ✅ | scanDepth，默认 10 |
| 关键词匹配 + selectiveLogic | ✅ | |
| 按 insertionOrder 排序 | ✅ | |
| 按 position 注入到 PromptAssembler | ✅ | tagged systemParts |
| Token 预算控制 | ❌ 已移除 | 粟粟要求不截断 |

### 第六节：楼层数据模型变更

| 字段 | 状态 |
|------|------|
| Profile.characterCardID | ✅ |
| Profile.linkedWorldBookIDs | ✅ |
| Profile.coverImageData | ✅ |
| Conversation.memoryEnabled | ✅ |

### 第七节：UI 变更

| UI | 架构文档设计 | 状态 |
|----|------------|------|
| 角色卡库入口 | 侧边栏或设置 | ✅ 右栏 tab（卡库） |
| 世界书库入口 | 侧边栏或设置 | ✅ 右栏 tab（世界书） |
| 楼层设置绑定管理 | 添加/移除/排序世界书 | ❌ 未实现 |
| 对话记忆开关 | 对话侧边栏 toggle | ✅ 右键菜单 |
| 新建楼层两种路径 | 手动 / 从角色卡 | ✅ sheet 里加导入按钮 + 卡库创建楼层 |

### 第八节：实现优先级（全部完成）

1. ✅ 世界书核心
2. ✅ 世界书注入
3. ✅ 角色卡解析
4. ✅ 角色卡库 UI
5. ✅ 角色卡 → 楼层
6. ✅ 楼层世界书绑定
7. ✅ 对话记忆开关

### 第九节：明确排除（未实现，符合预期）

- ❌ 跨楼层记忆连通 — 远期
- ❌ 楼层模式切换 — 不需要
- ❌ 插件系统 — 远期
- ❌ 正则表达式引擎 — Phase 2+
- ❌ 对话级角色卡切换 — 不做
- ❌ 角色卡市场 — 远期

---

## 二、额外完成的功能（架构文档未涉及）

| 功能 | 说明 |
|------|------|
| PNG 角色卡解析 | tEXt/iTXt chunk 手动解析，V2/V3 兼容 |
| 世界书条目编辑器 | 完整 CRUD：编辑关键词/内容/位置/排序/常驻等 |
| 世界书独立导入 | 不跟角色卡，直接导入 JSON 世界书文件 |
| 组装预览展示世界书 | Settings > Prompt > 组装/请求 tab 传入世界书 |
| 右栏工具抽屉 | 插件注册制 + 一条 bar + 选中展开 + 长按工具箱 + 橡皮绳切换动画 |
| iOS 适配 | CardLibraryPanelView 跨平台图片处理，iOS build 通过 |

---

## 三、遗留项（下一步可做）

### 高优先级

1. **全局世界书** — `WorldBook.isGlobal` 字段，不绑定楼层，所有楼层都注入
2. **独立创建世界书** — 不依赖角色卡，从零新建世界书
3. **楼层设置绑定管理** — 在楼层设置里查看/添加/移除绑定的世界书

### 低优先级

4. 世界书条目 sticky/cooldown/delay
5. 世界书条目 group 互斥逻辑
6. 正则关键词匹配（use_regex）
7. 角色卡封面图在侧边栏展示

---

## 四、新增文件清单

| 文件 | 说明 |
|------|------|
| `Models/WorldBook.swift` | WorldBook @Model + WorldBookEntry Codable |
| `Models/CharacterCard.swift` | CharacterCard Codable + CharacterCardManager |
| `Models/RightPanelPlugin.swift` | RightPanelTool + RightPanelToolManager |
| `Services/TavernCardParser.swift` | TavernCard V2/V3 JSON + PNG 解析 |
| `Services/WorldBookScanner.swift` | 关键词扫描 + 注入位置解析 |
| `Views/WorldBookPanelView.swift` | 世界书面板 + 条目编辑器 |
| `Views/CardLibraryPanelView.swift` | 角色卡库面板 |
| `Views/ToolBarView.swift` | 工具栏 + 工具抽屉 |

## 五、修改文件清单

| 文件 | 改动 |
|------|------|
| `MemoryPalaceApp.swift` | Profile 加字段 + SwiftData schema 加 WorldBook + environment 注入 CardManager/ToolManager + ProfileEditorSheet 加导入 |
| `Services/PromptAssembler.swift` | assemble() 加 worldBooks 参数 + tagged systemParts + 按 position 注入 |
| `ViewModels/ConversationViewModel.swift` | 查询 WorldBook 传入 assemble + memoryEnabled 过滤 |
| `Views/MemoryPanelView.swift` | RightPanelView 改用 ToolBarView + 橡皮绳动画 |
| `Views/ContentView.swift` | selectedTab → selectedToolId + 去掉 RightPanelTopBar 重复 |
| `Views/SettingsView.swift` | 组装/请求预览传入 worldBooks |
| `Views/SidebarView.swift` | 对话右键菜单加记忆开关 |
| `Views/CardFlowView.swift` | 玻璃按钮阴影调轻 |
| `Models/Conversation.swift` | 加 memoryEnabled 字段 |

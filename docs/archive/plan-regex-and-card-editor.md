# Plan: 正则脚本 + 角色卡编辑

> 日期：2026-04-14

---

## 一、正则脚本（Regex Scripts）

### 背景

酒馆角色卡可以自带正则脚本（`extensions.regex_scripts`），用于对 AI 输出做正则替换。典型用途：
- 状态栏：AI 输出 `<nagi_status>[Time|...]</nagi_status>`，正则替换为 HTML 卡片
- 格式化：去掉某些标记、加样式

### 柚木凪实例

```json
{
  "scriptName": "状态栏",
  "findRegex": "/<nagi_status>...pattern...</nagi_status>/s",
  "replaceString": "<!DOCTYPE html>...",
  "placement": [2],        // 2 = AI 消息
  "disabled": false,
  "markdownOnly": true,    // 只在渲染时替换，不改原始消息
  "promptOnly": false,
  "runOnEdit": true
}
```

### Task Checklist

- [ ] **L1** 数据模型
  - `RegexScript` Codable struct：id, scriptName, findRegex, replaceString, placement, disabled, markdownOnly, promptOnly, runOnEdit
  - 存在 `CharacterCard` 里（随卡导入）
  - Profile 加 `regexScripts: [RegexScript]`（楼层级，可编辑）

- [ ] **L2** TavernCardParser 解析 regex_scripts
  - `TavernCard` 加 `regexScripts: [[String: Any]]`
  - 导入角色卡到楼层时，同时导入 regex_scripts 到 Profile

- [ ] **L3** 正则引擎
  - `RegexEngine.apply(scripts:text:placement:) -> String`
  - placement: 0=用户消息, 1=所有, 2=AI消息
  - markdownOnly=true：只在渲染时替换（不改 SwiftData 里的原始 content）
  - promptOnly=true：只在发送给 API 时替换（不影响显示）

- [ ] **L4** 接入渲染层
  - 气泡渲染 assistant 消息时，先过 RegexEngine（markdownOnly 脚本）
  - PromptAssembler 里，promptOnly 脚本替换消息内容

- [ ] **L5** 正则脚本管理 UI（可选，Phase 2）
  - 设置 > Prompt tab 或右栏新 tab
  - 查看/编辑/开关/新增/删除正则脚本

---

## 二、角色卡编辑

### 背景

当前角色卡导入到卡库后不可编辑（只能查看详情 + 创建楼层）。需要：
- 在卡库里编辑卡的字段（description, personality, scenario 等）
- 编辑后创建的新楼层用修改后的值
- 已创建的楼层不受影响（导入是复制，不是引用）

### Task Checklist

- [ ] **M1** CardLibraryPanelView 加编辑入口
  - 展开卡详情后加"编辑"按钮
  - 弹 sheet：CharacterCardEditor

- [ ] **M2** CharacterCardEditor sheet
  - 可编辑字段：name, description, personality, scenario, mesExample, systemPrompt, postHistoryInstructions, creatorNotes
  - first_mes + alternate_greetings 也可编辑
  - 保存 → 更新 CharacterCardManager

- [ ] **M3** build 双平台 + commit + push

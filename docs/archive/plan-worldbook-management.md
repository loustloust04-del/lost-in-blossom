# Plan: 世界书管理 Phase 2

> 在 Phase 1 只读查看 + 开关的基础上，加编辑能力
> 日期：2026-04-13

---

## Task Checklist

### G1：条目编辑 sheet

- [ ] 点击展开的条目 → 出现"编辑"按钮
- [ ] 点编辑 → 弹 sheet `WorldBookEntryEditor`
- [ ] sheet 里可编辑：
  - **备注**（comment）— TextField
  - **关键词**（keys）— 逗号分隔输入，显示为 capsule 标签
  - **次关键词**（secondaryKeys）— 同上
  - **内容**（content）— TextEditor，不限高度
  - **注入位置**（position）— Picker，7 个选项
  - **排序**（insertionOrder）— 数字输入
  - **常驻**（isConstant）— Toggle
  - **全词匹配**（matchWholeWords）— Toggle
  - **大小写敏感**（caseSensitive）— Toggle
- [ ] 确定 → 更新 WorldBook.entries[index]，save context
- [ ] 取消 → 不保存

### G2：新增条目

- [ ] 世界书 header 旁加"+"按钮
- [ ] 点击 → 弹同一个 `WorldBookEntryEditor` sheet，空白初始值
- [ ] 确定 → append 到 WorldBook.entries 末尾

### G3：删除条目

- [ ] 展开的条目里加"删除"按钮（红色）
- [ ] 点击 → 确认弹窗 → 从 WorldBook.entries 移除

### G4：世界书 header 操作

- [ ] header 右侧加 context menu（右键或长按）
- [ ] 菜单项：重命名、删除世界书
- [ ] 重命名 → 弹 alert 输入新名称
- [ ] 删除 → 确认弹窗 → 从 SwiftData 删除 WorldBook + 从 profile.linkedWorldBookIDs 移除

### G5：build + 重启 + commit + push

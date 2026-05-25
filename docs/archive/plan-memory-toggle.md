# Plan: 对话记忆开关

> 在对话右键菜单里加记忆开关 toggle
> 日期：2026-04-13

---

## Task Checklist

- [ ] **I1** Conversation 模型加 `memoryEnabled: Bool = true` 字段
- [ ] **I2** 侧边栏对话右键菜单加 toggle："参与记忆" / "不参与记忆"
  - 位置：在"收藏整个对话"下面，加 Divider 后
  - 显示：当前状态 + 切换
- [ ] **I3** AUDN 记忆提取时过滤：memoryEnabled=false 的对话不提取
  - 找到 MemoryExtractor 调用点，加 conversation.memoryEnabled 判断
- [ ] **I4** AUDN 记忆注入时过滤：memoryEnabled=false 的对话不注入记忆
  - 找到 assemblePrompt 调用链，检查当前对话是否 memoryEnabled
- [ ] **I5** build + 重启 + commit + push

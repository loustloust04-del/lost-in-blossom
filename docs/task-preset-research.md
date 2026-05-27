# 任务：研究 Preset 系统 — 为 Caelum 入住做准备

## 目标
搞清楚粟粟的 Preset 系统怎么用，写一份简短的使用指南。

## 需要回答的问题

1. **Preset 的七个插槽分别是什么？** 读 `MemoryPalace/Models/Preset.swift`，列出所有 PromptSlot 类型和用途。

2. **Preset 怎么被加载到对话中的？** 读 `MemoryPalace/Services/PromptAssembler.swift`，描述 system prompt 的组装顺序。

3. **每个插槽的字符限制是多少？** 有没有长度限制？三万字的人设能不能全塞进去？

4. **Preset 怎么跟对话关联？** 是全局默认还是每个对话单独选？

5. **怎么在 App 里创建/编辑 Preset？** UI 入口在哪里？PersonaSettingsTab.swift 的结构。

6. **Preset 跟 API Provider 的关系？** 不同模型用不同 Preset？

## 输出
写到 `docs/research-preset-system.md`。格式简洁。代码引用标注行号。

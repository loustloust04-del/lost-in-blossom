# 上游同步欠债清单

> 从粟粟（SusuPalace）cherry-pick P0 修复时，以下内容因依赖缺失被跳过。
> 后续做完整同步时需要补回来。

## 1. MCP 模块完整同步
- **欠什么**：粟粟重构了整个 MCP 模块（MCPClient/MCPProvider/MCPSSETransport/MCPModels/MCPTransport/MCPStreamableHTTP），包含 P0-3 超时修复
- **为什么跳过**：新版 MCPServerConfig（MCPModels.swift）与旧版（APIProvider.swift:7）字段完全不同，编译冲突
- **怎么补**：用粟粟的 MCPModels.swift 替换 APIProvider.swift 里的旧 MCPServerConfig，同时更新所有引用点（ChatService.swift、MCPSettingsView 等）
- **粟粟的 commit**：60bf8f5 + 周边 MCP 改动

## 2. Preset 楼层实例化迁移
- **欠什么**：MemoryPalaceApp.swift 里的 `migratePresetInstances` 函数
- **为什么跳过**：依赖 Preset.ownerProfileId 和 PresetManager.instantiate()，我们的 Preset 模型没有这些字段
- **怎么补**：同步粟粟的 Preset.swift + PresetManager 改动后自然回来
- **粟粟的 commit**：1c6eeee（P0-2 附带）

## 3. 粟粟比我们多的 CC Bridge 功能
- edit_message 工具（编辑已发消息）
- reply_to 参数（引用回复）
- command 消息类型
- set_cc_config（App 配置 CC 参数）
- set_bind（绑定配置）
- hub.ts 差异：粟粟 1091 行 vs 我们 713 行

---
更新日期：2026-06-11

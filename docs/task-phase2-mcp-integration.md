# 任务：Phase 2 — MCP 工具调用集成

## 背景
Lost in Blossom 基于粟粟的 MemoryPalace 改造。粟粟的 App 已有完整的聊天、API、Preset 系统。
现在需要在现有架构上**新增 MCP（Model Context Protocol）工具调用能力**。

## 目标
让 Caelum 在聊天时能调用 MCP 工具——比如 imprint-memory（记忆系统）、搜索、文件操作等。

## 现有架构
- `ChatService.swift` — 核心聊天服务，支持 OpenAI compatible + Anthropic 两种 API
- `PromptPostProcessor.swift` — prompt 组装，区分 openaiCompatible / anthropic
- `APIProvider.swift` — 多 provider 管理（DeepSeek、Claude、OpenRouter 等）

## 需要做的
1. **研究**：读 ChatService.swift 和 PromptPostProcessor.swift，理解当前的请求构建流程
2. **研究**：Anthropic Messages API 的 MCP 工具调用格式（mcp_servers 参数）
3. **研究**：OpenAI compatible API 的 function calling 格式
4. **设计**：在现有 APIProvider 模型中加入 MCP server 配置（URL、名称）
5. **设计**：在 Profile/Preset 层加入 MCP 开关（哪些 MCP server 对这个角色启用）
6. **实现**：修改 ChatService 的请求构建，在 API 调用中注入 MCP servers
7. **实现**：修改响应解析，处理 tool_use / tool_result 类型的 content blocks
8. **实现**：在聊天界面展示工具调用结果（可折叠的卡片）

## MCP Servers（天奕的）
- imprint-memory SSE: https://imprint.amberrib.com/sse
- 更多以后加

## 约束
- 不动现有聊天 UI 布局
- 不动现有 API 调用逻辑——在旁边加，不改原来的
- 先做 research 文档 (docs/research-mcp-integration.md)，天奕确认后再写代码

## 开发流程
Research → Plan → Implement（继承粟粟的流程）

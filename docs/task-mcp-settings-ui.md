# MCP 设置页面

> 在 App 设置里暴露 MCP server 管理功能。
> 后端数据模型已存在（MCPServerConfig, APIProvider.mcpServers）。

---

## 背景

MCPServerConfig 模型已有：
```swift
struct MCPServerConfig: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var url: String
    var isEnabled: Bool
    var authorizationToken: String?
}
```

APIProvider 已有 per-provider 的 MCP server 存储：
- `provider.mcpServers: [MCPServerConfig]`
- `APIProviderManager.addOrUpdateMCPServer(_:for:)`
- `APIProviderManager.removeMCPServer(id:from:)`

ChatService 已有注入逻辑：Anthropic provider 发请求时注入 `mcp_servers` 参数。

缺的是：设置页面的 UI 入口。

---

## Commit 1: MCPSettingsView

创建 `MemoryPalace/Views/MCPSettingsTab.swift`

### 页面结构

```
MCP 工具连接
├── 已连接的 server 列表
│   ├── 每行：名字 + URL + 开关（isEnabled）
│   ├── 左滑删除
│   └── 点击编辑
├── 「+ 添加 MCP Server」按钮
│   └── 弹 sheet：
│       ├── 名字输入框
│       ├── URL 输入框（placeholder: "https://mcp.example.com/sse"）
│       ├── Token 输入框（可选，placeholder: "Bearer token"）
│       └── 保存按钮
└── 说明文字："MCP 让 AI 连接外部工具（文件系统、数据库、API 等）"
```

### 实现要点

- 读写通过 `APIProviderManager.shared`
- MCP servers 是 per-provider 的（每个 API provider 有自己的 MCP 列表）
- 当前选中的 provider 从 `@Environment` 或 SettingsView 传入
- 只有 Anthropic 类型的 provider 支持 MCP（OpenAI/DeepSeek 不支持原生 MCP）
- 如果当前 provider 不是 Anthropic，显示提示："MCP 仅支持 Claude API"

### 颜色和样式

- 跟其他 SettingsTab 保持一致（用 Theme.SettingsFont）
- server 列表每行左侧有绿色/灰色圆点指示 isEnabled
- 添加按钮用 `Image(systemName: "plus.circle")`

---

## Commit 2: 入口集成

在 SettingsView 里加入 MCPSettingsTab：
- 位置：API 设置下面
- 标签：「🔧 MCP 工具」
- 图标：`wrench.and.screwdriver`

同时确认：
- ChatService 的 MCP 注入逻辑已有，不需要改
- APIProvider 的 mcpServers 存储已有，不需要改
- 只需要把 UI 暴露出来

---

## 注意

- 不要改 MCPServerConfig 模型
- 不要改 ChatService 的注入逻辑
- 只做 UI 层
- 两个 commit 分开做分开 push

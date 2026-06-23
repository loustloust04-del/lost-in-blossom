# 后端工具集成方案

## 现状调查

### VPS上的全部工具

| 工具 | 所在服务 | API能用 | CC能用 |
|------|---------|---------|--------|
| exec（shell命令） | Gateway内置 | ✅ | ❌ |
| recall（记忆搜索） | Gateway内置 | ✅ | ❌ |
| remember（记忆存储） | Gateway内置 | ✅ | ❌ |
| gmail_inbox/read/send/search | Gateway内置 | ✅ | ❌ |
| vitals_water/food/meds | Gateway内置 | ✅ | ❌ |
| get_phone_status | Gateway内置 | ✅ | ❌ |
| VPS exec MCP | :3100 /mcp | ✅ (MCP Client) | ❌ |
| Browser MCP | :3001 /mcp | ✅ (MCP Client) | ❌ |
| reply（回复App） | cc-bridge MCP | ❌ | ✅ |
| imprint-memory | :8100 SSE | ❌ | ✅ |
| Memory Palace | :3501 | ❌ | ❌ (需auth) |

### 核心Gap
- **CC 缺 Gateway 的所有工具**：exec, recall, remember, gmail, vitals, phone
- **API 缺 imprint-memory**：跨会话的长期记忆系统
- 两边各有一半工具，互相看不见

## 方案

### 方案A：CC → Gateway工具（推荐，改动最小）

在 `cc-bridge/mcp-server.ts` 里加代理工具。CC调用时，MCP server 转发请求到 Gateway 的内部API。

```
CC 调 exec/recall/gmail...
  → cc-bridge/mcp-server.ts 收到请求
  → fetch("http://localhost:4567/internal/tool-call", {tool, input})
  → Gateway 执行，返回结果
  → mcp-server.ts 返回给 CC
```

**需要改的文件：**
1. `cc-bridge/mcp-server.ts` — 加 Gateway 工具的代理定义
2. `gateway/src/app.ts` — 加 `/internal/tool-call` 内部端点（只允许127.0.0.1）

**优点：** CC的MCP配置不用改，工具自动出现在CC的工具列表里。
**工作量：** ~50行 mcp-server.ts + ~20行 gateway

### 方案B：API → imprint-memory

Gateway 的 `MCP_SERVERS` 环境变量加上 imprint-memory 的 endpoint。

```
# gateway/.env
MCP_SERVERS=http://127.0.0.1:3100/mcp,http://127.0.0.1:3001/mcp,http://127.0.0.1:8100/mcp
```

**需要改的：** gateway/.env 一行。但需要确认 imprint-memory 是否暴露了 `/mcp` 端点（当前只有 SSE jsonrpc）。如果不兼容，需要在 Gateway 的 mcp-client.ts 里加 SSE transport 支持。

### 方案C：统一 MCP Hub（长期方案）

建一个中间层 MCP Hub，所有工具注册到这里，API 和 CC 都只连 Hub：

```
API → MCP Hub → [exec, recall, gmail, vitals, browser, imprint, ...]
CC  → MCP Hub → [同上 + reply]
```

**优点：** 一处注册，到处可用。新增工具只改 Hub。
**缺点：** 需要全新的组件，工作量大。

## 推荐实施顺序

1. **先做方案A**（CC→Gateway工具） — 立即让CC拥有exec/recall/gmail等能力，~70行代码
2. **再做方案B**（API→imprint） — 让API也能用长期记忆，改配置为主
3. **方案C留后面** — 等工具多到管不过来再统一

## 给CC的任务指令

方案A可以直接让CC自己实现——它改自己的mcp-server.ts，加Gateway代理工具。

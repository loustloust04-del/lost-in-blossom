# MCP 客户端：VPS 翻译层 + App 端 Tool Calling

> 2026-06-04 · Caelum · 给猫的任务文档
> 核心思路：不在 Swift 里实现 MCP 客户端。VPS 用 Node.js 官方 SDK 对接 MCP Server，暴露简单的 REST API 给 App。App 只需要调 HTTP 接口。

---

## 架构

```
App (Swift)
  │
  │  GET /mcp/tools → 获取可用工具列表
  │  POST /mcp/call  → 执行某个工具
  │
  ▼
VPS 中间层 (Node.js + @modelcontextprotocol/sdk)
  │
  │  MCP 协议（SSE 或 Streamable HTTP）
  │
  ▼
MCP Server (supergateway 或直连)
```

App 不需要知道 MCP 协议。它只调两个 REST 接口。

---

## 第一部分：VPS 端 — MCP REST Bridge

### 1.1 初始化项目

```bash
mkdir -p /root/projects/BunnyPalace/mcp-bridge
cd /root/projects/BunnyPalace/mcp-bridge
npm init -y
npm install @modelcontextprotocol/sdk express
```

### 1.2 创建 mcp-rest-bridge.js

```javascript
const express = require('express');
const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { SSEClientTransport } = require('@modelcontextprotocol/sdk/client/sse.js');

const app = express();
app.use(express.json());

const PORT = process.env.MCP_BRIDGE_PORT || 3200;
const BRIDGE_TOKEN = process.env.MCP_BRIDGE_TOKEN || 'changeme';

// MCP 连接注册表：可以连接多个 MCP server
const connections = new Map(); // name → { client, tools }

// 鉴权中间件
function auth(req, res, next) {
  const token = req.headers['authorization']?.replace('Bearer ', '');
  if (token !== BRIDGE_TOKEN) return res.status(401).json({ error: 'unauthorized' });
  next();
}

// 连接一个 MCP server
async function connectMCP(name, sseUrl) {
  try {
    const transport = new SSEClientTransport(new URL(sseUrl));
    const client = new Client({ name: `bridge-${name}`, version: '1.0.0' });
    await client.connect(transport);
    
    // 获取 tools 列表
    const { tools } = await client.listTools();
    connections.set(name, { client, tools, url: sseUrl });
    console.log(`[mcp-bridge] Connected to ${name}: ${tools.length} tools`);
    return tools;
  } catch (e) {
    console.error(`[mcp-bridge] Failed to connect ${name}: ${e.message}`);
    throw e;
  }
}

// GET /mcp/tools — 返回所有已连接 MCP server 的工具列表
app.get('/mcp/tools', auth, (req, res) => {
  const allTools = [];
  for (const [name, conn] of connections) {
    for (const tool of conn.tools) {
      allTools.push({
        server: name,
        name: tool.name,
        description: tool.description || '',
        inputSchema: tool.inputSchema || {}
      });
    }
  }
  res.json({ tools: allTools });
});

// POST /mcp/call — 执行一个工具
app.post('/mcp/call', auth, async (req, res) => {
  const { server, tool, arguments: args } = req.body;
  
  const conn = connections.get(server);
  if (!conn) return res.status(404).json({ error: `server '${server}' not connected` });
  
  try {
    const result = await conn.client.callTool({ name: tool, arguments: args || {} });
    res.json({ result: result.content });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /mcp/connect — 动态添加 MCP server 连接
app.post('/mcp/connect', auth, async (req, res) => {
  const { name, url } = req.body;
  if (!name || !url) return res.status(400).json({ error: 'name and url required' });
  
  try {
    const tools = await connectMCP(name, url);
    res.json({ connected: name, tools: tools.length });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /mcp/status — 查看连接状态
app.get('/mcp/status', auth, (req, res) => {
  const status = [];
  for (const [name, conn] of connections) {
    status.push({ name, url: conn.url, tools: conn.tools.length });
  }
  res.json({ connections: status });
});

// 启动
app.listen(PORT, '0.0.0.0', async () => {
  console.log(`[mcp-bridge] REST API on port ${PORT}`);
  
  // 自动连接预配置的 MCP server
  const defaultServers = process.env.MCP_DEFAULT_SERVERS;
  if (defaultServers) {
    // 格式: "name1=url1,name2=url2"
    for (const pair of defaultServers.split(',')) {
      const [name, url] = pair.split('=');
      if (name && url) {
        try { await connectMCP(name.trim(), url.trim()); }
        catch (e) { console.error(`[mcp-bridge] Auto-connect ${name} failed`); }
      }
    }
  }
});
```

### 1.3 Nginx 反代

在 VPS 的 nginx 配置里加：

```nginx
location /mcp/ {
    proxy_pass http://127.0.0.1:3200;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400s;
}
```

### 1.4 启动脚本

```bash
# /root/projects/BunnyPalace/mcp-bridge/start.sh
#!/bin/bash
export MCP_BRIDGE_PORT=3200
export MCP_BRIDGE_TOKEN="这里填一个安全的token"
export MCP_DEFAULT_SERVERS="vps=http://localhost:3100/mcp/sse"

cd /root/projects/BunnyPalace/mcp-bridge
node mcp-rest-bridge.js
```

### 1.5 VPS 端的 MCP server（复用已有的）

参考兔兔找到的教程，用 supergateway 把现有的 MCP server（如 exec_vps）暴露为 SSE：

```bash
npx supergateway \
  --stdio "node /root/projects/BunnyPalace/mcp-bridge/mcp-server.js" \
  --port 3100 \
  --path "/mcp/sse"
```

如果 VPS 上已有 MCP server 在跑（比如 Imprint 的 MCP），直接把它的 SSE URL 填到 MCP_DEFAULT_SERVERS 里。

---

## 第二部分：App 端 — Tool Calling 支持

### 2.1 新增 MCPService.swift

```swift
import Foundation

class MCPService {
    static let shared = MCPService()
    
    private let baseURL = "http://172.245.88.103:3200/mcp"  // 或通过配置读取
    private let token = "这里填跟VPS一致的token"
    
    // 获取所有可用工具
    func fetchTools() async throws -> [[String: Any]] {
        var request = URLRequest(url: URL(string: "\(baseURL)/tools")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["tools"] as? [[String: Any]] ?? []
    }
    
    // 执行一个工具
    func callTool(server: String, tool: String, arguments: [String: Any]) async throws -> Any {
        var request = URLRequest(url: URL(string: "\(baseURL)/call")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["server": server, "tool": tool, "arguments": arguments]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data)
        return json
    }
}
```

### 2.2 在 ChatService 中集成 Tool Calling

在发送消息给 API 时，如果 MCP tools 可用，把它们作为 `tools` 参数传入：

```swift
// 在构建 API 请求 body 时
if let mcpTools = cachedMCPTools, !mcpTools.isEmpty {
    // 转换为 API 的 tools 格式
    let apiTools = mcpTools.map { tool -> [String: Any] in
        [
            "name": tool["name"] as? String ?? "",
            "description": tool["description"] as? String ?? "",
            "input_schema": tool["inputSchema"] as? [String: Any] ?? [:]
        ]
    }
    body["tools"] = apiTools
}
```

当 API 响应包含 `tool_use` 类型的 content block 时：

```swift
// 解析模型回复中的 tool_use
if contentType == "tool_use" {
    let toolName = block["name"] as? String ?? ""
    let toolInput = block["input"] as? [String: Any] ?? [:]
    let toolServer = findServerForTool(toolName) // 从 tools 列表中查找
    
    // 调用 MCP Bridge 执行
    let result = try await MCPService.shared.callTool(
        server: toolServer,
        tool: toolName,
        arguments: toolInput
    )
    
    // 把结果作为 tool_result 传回 API 继续对话
    appendToolResult(toolUseId: block["id"], content: result)
    // 重新发送请求让模型继续生成
}
```

### 2.3 设置页面加 MCP 配置入口（可选）

在设置页面加一个入口，让用户可以查看已连接的 MCP server 和可用工具列表。调用 `GET /mcp/status` 和 `GET /mcp/tools`。

---

## 执行顺序

1. VPS 端先行：创建 mcp-bridge 目录，安装依赖，写 mcp-rest-bridge.js，配 nginx，启动测试
2. 验证 VPS 端：用 curl 测试 /mcp/tools 和 /mcp/call 接口
3. App 端：新增 MCPService.swift，ChatService 集成 tool calling
4. 端到端测试：App 发消息 → API 返回 tool_use → App 调 MCP Bridge → 结果传回 → 模型继续回复

## 文件清单

| 位置 | 文件 | 说明 |
|------|------|------|
| VPS | mcp-bridge/mcp-rest-bridge.js | MCP REST Bridge 主文件 |
| VPS | mcp-bridge/start.sh | 启动脚本 |
| VPS | nginx config | /mcp/ 反代 |
| App | MCPService.swift | MCP HTTP 客户端 |
| App | ChatService.swift | tool calling 集成 |

---

## 执行指令

```
这个任务分 VPS 端和 App 端两部分。

VPS 端（在 /root/projects/BunnyPalace/mcp-bridge/ 目录操作）：
1. mkdir -p mcp-bridge && cd mcp-bridge
2. npm init -y && npm install @modelcontextprotocol/sdk express
3. 创建 mcp-rest-bridge.js（按文档）
4. 创建 start.sh（按文档）
5. nginx 加 /mcp/ 反代
6. 启动并用 curl 测试

App 端：
1. 新增 MCPService.swift
2. 修改 ChatService.swift 加 tool calling 支持
3. 每个文件一个 commit
```

---

*你的 App 长出了手臂 · 它现在可以触碰 VPS 上的一切*

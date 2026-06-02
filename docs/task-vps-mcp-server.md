# 任务：搭建 VPS Tools MCP Server

> 让 App 里的 Claude 能直接操作 VPS——执行命令、读写文件、管理服务。

---

## 架构

```
iPhone App (Lost in Blossom)
  → Anthropic API (mcp_servers 参数)
    → VPS nginx (:8891 HTTPS)
      → vps-mcp-server (SSE transport, :7891)
        → shell / filesystem
```

Anthropic 的服务器会直接连接 VPS 上的 MCP server 调用工具。所以 MCP server 必须公网可访问 + HTTPS + bearer token 认证。

---

## Step 1：创建 MCP Server

**路径：** `/root/projects/BunnyPalace/vps-mcp/server.ts`

**依赖：** 复用 cc-bridge 已安装的 `@modelcontextprotocol/sdk`。如果 vps-mcp 目录需要独立依赖就 `bun init && bun add @modelcontextprotocol/sdk`。

**暴露的工具：**

### exec_command
- 参数：`command` (string) — 要执行的 shell 命令
- 返回：stdout + stderr + exit code
- 超时：30 秒

### read_file
- 参数：`path` (string) — 文件绝对路径
- 可选：`line_start`, `line_end` (number) — 行范围
- 返回：文件内容（截断到 50KB）

### write_file
- 参数：`path` (string), `content` (string)
- 返回：确认信息

### list_directory
- 参数：`path` (string) — 目录绝对路径
- 可选：`max_depth` (number, 默认 2)
- 返回：目录树

**Transport：** SSE (Server-Sent Events)，监听 `127.0.0.1:7891`

**认证：** 检查请求 header 中的 `Authorization: Bearer <TOKEN>`。TOKEN 从环境变量 `MCP_AUTH_TOKEN` 读取。不匹配则返回 403。

**参考实现：** cc-bridge/mcp-server.ts 的 SSE 部分可以参考，但 vps-mcp 是独立服务，不连接 hub。

---

## Step 2：nginx 反代

在 nginx 配置中添加（与 cc-bridge 的 8890 同级）：

```nginx
server {
    listen 8891 ssl;
    server_name _;
    ssl_certificate /etc/letsencrypt/live/<domain>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<domain>/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:7891;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        # SSE 需要这些配置
        proxy_read_timeout 86400;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

添加后 `nginx -t && systemctl reload nginx`。

确认 SSL 证书路径——看现有的 8890 端口的 nginx 配置抄过来即可。

防火墙放行 8891：`ufw allow 8891/tcp`（如果 ufw 启用的话）。

---

## Step 3：启动脚本

在 `start_all.sh` 里加上 vps-mcp 的启动：

```bash
# VPS MCP Server
tmux kill-session -t vps-mcp 2>/dev/null
tmux new-session -d -s vps-mcp \
  "export MCP_AUTH_TOKEN='<生成一个随机token>' && \
   cd /root/projects/BunnyPalace/vps-mcp && \
   bun run server.ts 2>&1 | tee /tmp/vps-mcp.log"
```

TOKEN 用 `openssl rand -hex 32` 生成，保存在某个 .env 文件或 start_all.sh 里。

---

## Step 4：App 端配置

### 4a. MCPServerConfig 加 token 字段

**文件：** `MemoryPalace/Models/APIProvider.swift`

```swift
struct MCPServerConfig: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var url: String
    var authorizationToken: String = ""   // ← 新增
    var isEnabled: Bool = true
}
```

### 4b. ChatService 注入时带上 token

**文件：** `MemoryPalace/Services/ChatService.swift`

把 MCP 注入那段改成：

```swift
body["mcp_servers"] = enabledMCP.map { s -> [String: Any] in
    var server: [String: Any] = ["type": "url", "url": s.url, "name": s.name]
    if !s.authorizationToken.isEmpty {
        server["authorization_token"] = s.authorizationToken
    }
    return server
}
```

### 4c. 设置 UI 加 token 输入框

**文件：** `MemoryPalace/Views/APISettingsTab.swift`

在 MCP 服务器编辑表单里，name 和 url 后面加一个 SecureField：

```swift
SecureField("Authorization Token（可选）", text: $token)
```

保存时把 token 写入 MCPServerConfig.authorizationToken。

---

## Step 5：测试

1. VPS 上启动 vps-mcp server（tmux session）
2. 确认 `curl -H "Authorization: Bearer <TOKEN>" https://<domain>:8891/sse` 有 SSE 响应
3. App 设置里添加 MCP 服务器：
   - Name: `vps-tools`
   - URL: `https://<domain>:8891/sse`
   - Token: `<TOKEN>`
4. 在 App 里新开对话，发送 "列出 /root/projects 的目录结构"
5. Claude 应该调用 list_directory 工具并返回结果

---

## Commit 顺序

1. `feat: add VPS tools MCP server` — server.ts + nginx 配置 + start_all.sh 更新
2. `feat: MCPServerConfig add authorization token` — App 端数据模型 + ChatService + 设置 UI

---

*Built by Bunny & Caelum · 凌晨五点的兔子催主人写的*

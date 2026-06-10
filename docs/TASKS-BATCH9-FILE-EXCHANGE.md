# 第九批任务 — CC Bridge 图片/文件互发

> 日期：2026-06-10
> 前置：`cd /home/user/lost-in-blossom && git pull origin main`
> 参考代码：粟粟 VPS `/root/projects/SusuPalace/cc-bridge/hub.ts` 第 145-220 行

---

## 背景

CC Bridge Phase 4.2——让用户和 CC 能互发图片和文件。
粟粟的实现在 hub.ts 里有完整的双向文件交换。

---

## Task 1: hub.ts 加入站文件处理（用户→CC）

**参考**: 粟粟 hub.ts 的 `saveInboundImages()` 和 `saveInboundFiles()`

**要做的事**:
1. 定义存储目录：`cc-bridge/inbound/{chat_id}/`
2. `saveInboundImages(chatId, images)` 函数：
   - images 数组每项含 base64 数据 + mime type
   - 解码保存为文件（jpg/png/gif/webp/heic）
   - 返回保存的文件路径数组
3. `saveInboundFiles(chatId, files)` 函数：
   - files 数组每项含 base64 数据 + name + mime type
   - 解码保存，文件名用原始 name（sanitize 掉 / \ 等危险字符）
   - 返回保存的文件路径数组
4. MIME 类型辅助函数：`mimeToExt()` 和 `extToMime()`
   - 参考粟粟的实现（第 145-165 行）
5. 处理 WebSocket 消息：
   - App 发 `{ type: "chat", chat_id, content, images?, files? }` 时
   - 先保存图片/文件到磁盘
   - 把文件路径注入到 tmux send-keys 的消息里（让 CC 知道文件在哪）

**commit**: `feat(cc-bridge): Phase 4.2 — inbound image/file save + path injection`

---

## Task 2: mcp-server.ts 加 file_path 参数（CC→用户）

**参考**: 粟粟 mcp-server.ts 的 reply 工具 file_path 参数

**要做的事**:
1. reply 工具 inputSchema 加 `file_path` 参数（可选）：
   ```
   file_path: { type: "string", description: "Absolute path of file to send to user" }
   ```
2. CC 调 reply 时带 file_path → MCP Server 把 file_path 传给 hub
3. hub 收到带 file_path 的 reply → 读取文件 → base64 编码 → 发给 App 客户端

**commit**: `feat(cc-bridge): Phase 4.2 — reply tool file_path for CC→user file send`

---

## Task 3: hub.ts 出站文件处理（CC→用户）

**参考**: 粟粟 hub.ts 的 `stageOutboundFile()` 相关代码

**要做的事**:
1. `stageOutboundFile(filePath)` 函数：
   - 检查文件是否存在
   - 检查文件大小（限制 10MB）
   - 读取文件 → base64 编码
   - 检测 MIME 类型
   - 返回 `{ name, mime, data_base64 }`
2. hub 收到 CC 的 reply（带 file_path）时：
   - 调 stageOutboundFile 准备文件
   - 发给 App 客户端：`{ type: "reply", chat_id, content, file?: { name, mime, data } }`
3. `isImageMime(mime)` 辅助函数——区分图片和普通文件

**commit**: `feat(cc-bridge): Phase 4.2 — outbound file staging + broadcast`

---

## Task 4: App 端 CCBridgeWebSocketClient 文件支持

**文件**: `MemoryPalace/Services/CCBridgeWebSocketClient.swift`

**要做的事**:
1. 发送消息时支持附带图片/文件（base64 编码后放在 WebSocket 消息里）
2. 接收 reply 时支持解析 file 字段（base64 → Data → 显示为图片或文件卡片）
3. 对接 ChatAttachment 模型（猫之前已搬过来了）

**commit**: `feat(cc-bridge): Phase 4.2 — App-side file send/receive support`

---

## 规则

- 按 Task 1-4 顺序做，每个单独 commit + push
- 开始前读粟粟的参考代码（hub.ts 第 145-220 行）
- 在现有 hub.ts 基础上增量添加
- 文件大小限制 10MB
- 文件名 sanitize：去掉 / \ ' " 等危险字符

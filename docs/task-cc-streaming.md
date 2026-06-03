# CC 流式输出：tmux capture-pane 轮询 + App 端流式渲染

> 2026-06-04 · Caelum · 给猫的任务文档
> 参考：CcCompanion (CyberSealNull), cc-self-hosting-guide (Shitsuten)

---

## 背景

CC Bridge (hub.ts) 已有完整的 WebSocket 通信。入站通过 tmux send-keys 注入 CC 终端，出站通过 MCP reply 工具广播给 App。但 CC 的回复目前是一次性送达——CC 处理完后调一次 reply，整段文字一起到。

用户需要的是流式输出——CC 一边生成一边显示在 App 上，像打字机效果。

## 方案：tmux capture-pane 差量推送

不依赖 CC 的 reply 行为。直接轮询 CC 所在 tmux pane 的终端内容，跟上一次比对，把新增文字实时推给 App。

---

## 第一部分：hub.ts 改动

文件：`/root/projects/BunnyPalace/cc-bridge/hub.ts`

### 新增 capture-pane 轮询

在 startHub() 函数里，WSS 启动后加一个定时器：

```typescript
// ── CC 输出流式轮询 ──────────────────────────────
let lastCapture = ""
let isStreaming = false

const POLL_INTERVAL_MS = 500  // 轮询间隔
const IDLE_THRESHOLD_MS = 3000  // 连续无变化超过此时间认为 CC 停止输出

let lastChangeTime = Date.now()

const captureTimer = setInterval(() => {
  if (mpClients.size === 0) return  // 没有客户端连接时不轮询
  if (!tmux.hasSession(TMUX_SESSION)) return

  try {
    const current = execFileSync("tmux", [
      "capture-pane", "-t", TMUX_SESSION, "-p", "-S", "-50"  // 捕获最近50行
    ], { encoding: "utf-8" })

    if (current !== lastCapture) {
      // 有新内容
      const newContent = extractDelta(lastCapture, current)
      lastCapture = current
      lastChangeTime = Date.now()

      if (newContent.trim()) {
        isStreaming = true
        // 广播给所有 MP 客户端
        const streamMsg = JSON.stringify({
          type: "cc_stream",
          content: newContent,
          timestamp: new Date().toISOString()
        })
        for (const ws of mpClients) {
          if (ws.readyState === WebSocket.OPEN) ws.send(streamMsg)
        }
      }
    } else if (isStreaming && Date.now() - lastChangeTime > IDLE_THRESHOLD_MS) {
      // CC 停止输出了
      isStreaming = false
      const endMsg = JSON.stringify({
        type: "cc_stream_end",
        timestamp: new Date().toISOString()
      })
      for (const ws of mpClients) {
        if (ws.readyState === WebSocket.OPEN) ws.send(endMsg)
      }
    }
  } catch (e) {
    // tmux capture-pane 失败（session 可能不存在）
  }
}, POLL_INTERVAL_MS)
```

### 差量提取函数

```typescript
function extractDelta(prev: string, current: string): string {
  // 简单方案：找到最长公共前缀，返回新增部分
  const prevLines = prev.split("\n")
  const currLines = current.split("\n")
  
  // 从末尾找新增的行
  let commonEnd = 0
  for (let i = 0; i < prevLines.length; i++) {
    if (prevLines[i] === currLines[i]) {
      commonEnd = i + 1
    } else {
      break
    }
  }
  
  // 返回 commonEnd 之后的所有新行
  return currLines.slice(commonEnd).join("\n")
}
```

注意：差量提取有很多 edge case（终端滚动、ANSI 转义码、CC 的进度条等）。上面是最简实现，可以后续优化。核心是让流式推送跑起来。

### ANSI 清理

tmux capture-pane 的输出可能包含 ANSI 转义码。加一个清理函数：

```typescript
function stripAnsi(text: string): string {
  return text.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "")
}
```

在 extractDelta 返回前调用 `stripAnsi()`。

---

## 第二部分：App 端改动

文件：App 的 WebSocket 连接管理 + 消息渲染

### 接收流式消息

App 的 WebSocket 客户端在收到消息时，根据 type 分发：

```swift
case "cc_stream":
    // CC 正在输出，追加到当前消息的 buffer
    if let content = json["content"] as? String {
        appendToStreamBuffer(content)
        updateUIWithStreamContent()
    }
    
case "cc_stream_end":
    // CC 输出完成，把 buffer 内容固化为正式消息
    finalizeStreamMessage()
```

### 流式渲染

在聊天界面底部维护一个"正在输入"的临时消息气泡。每收到 cc_stream 就追加内容。收到 cc_stream_end 时把临时气泡转成正式消息。

---

## 第三部分：思考链显示（可选增强）

CC 的 settings.json 里加 `"showThinkingSummaries": true` 可以让 CC 输出思考摘要。这些内容会出现在 tmux pane 里，被 capture-pane 捕获。

App 端可以检测思考内容的特征标记（通常有特殊前缀或格式），用折叠块渲染——默认折叠，用户点击展开。类似 Claude.ai 的思考链显示方式。

---

## 执行顺序

1. 先改 hub.ts（后端）—— 加 capture-pane 轮询 + 差量提取 + WebSocket 广播
2. 在 VPS 上测试：连 WebSocket 确认流式消息能发出来
3. 再改 App 端 —— WebSocket 接收 + 流式渲染
4. 端到端测试

hub.ts 的改动可以直接在 VPS 上完成，不需要编译 App。先把后端跑通，再做前端。

---

## 文件清单

| 文件 | 位置 | 改动 |
|------|------|------|
| hub.ts | VPS /root/projects/BunnyPalace/cc-bridge/ | capture-pane 轮询 + 差量推送 |
| App WebSocket 客户端 | iOS App | 接收 cc_stream / cc_stream_end |
| App 聊天界面 | iOS App | 流式渲染临时气泡 |

---

*CC 的文字像水一样流到你的手机上 · 不再是一坨一坨的*

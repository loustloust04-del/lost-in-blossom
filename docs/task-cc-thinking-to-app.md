# CC 思考链 → App 展示

> CC 执行任务时的 thinking block 推送到 Lost in Blossom App 里展示。
> 不走 Telegram，所有东西住在自己的家里。

---

## 架构

```
CC 执行任务（Opus model, extended thinking）
    │  Stop hook 触发
    ▼
extract-thinking.sh
    │  从 transcript JSONL 提取 thinking block
    │  原子写入文件
    ▼
/tmp/cc-thinking-{timestamp}.json
    │  hub.ts 轮询检测（复用现有 setInterval）
    ▼
hub.ts 广播 { type: "cc_thinking" }
    │  WebSocket
    ▼
App CCBridgeWebSocketClient
    │  回调 / @Observable
    ▼
UI 展示（折叠思考链组件）
```

文件系统做 IPC：stop hook 写文件，hub 轮询读文件。不需要给 hub 加 HTTP 端点，不需要改服务器架构，改动最小。

---

## Commit 1: Stop hook 脚本（VPS 端）

创建 `cc-bridge/hooks/extract-thinking.sh`

```bash
#!/bin/bash
set -euo pipefail

# CC Stop hook: 从 transcript 提取 thinking block，写入 /tmp 供 hub 轮询

# 从 stdin 读 hook input JSON
HOOK_INPUT=$(cat)

# 解析 transcript 路径
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# 从 transcript JSONL 提取最后一个 thinking block
# transcript 格式：每行一个 JSON，assistant 消息的 content 数组里有 type=thinking 的 block
THINKING=$(python3 -c "
import sys, json

thinking_texts = []
with open('$TRANSCRIPT_PATH', 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            # CC transcript 格式：顶层有 type 和 message 字段
            if obj.get('type') == 'assistant':
                for block in obj.get('message', {}).get('content', []):
                    if block.get('type') == 'thinking':
                        thinking_texts.append(block.get('thinking', ''))
        except:
            pass

# 取最后一个 thinking block
if thinking_texts:
    print(thinking_texts[-1])
" 2>/dev/null)

if [[ -z "$THINKING" ]]; then
  exit 0
fi

# 原子写入：先写 .tmp 再 rename，避免 hub 读到写了一半的文件
TIMESTAMP=$(date +%s%N)
TMP_FILE="/tmp/cc-thinking-${TIMESTAMP}.tmp"
FINAL_FILE="/tmp/cc-thinking-${TIMESTAMP}.json"

python3 -c "
import json, sys
thinking = sys.stdin.read()
data = {
    'thinking': thinking,
    'session_id': '$SESSION_ID',
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}
with open('$TMP_FILE', 'w') as f:
    json.dump(data, f, ensure_ascii=False)
" <<< "$THINKING"

mv "$TMP_FILE" "$FINAL_FILE"
```

chmod +x 后测试：`echo '{"transcript_path":"/path/to/test","session_id":"test"}' | bash extract-thinking.sh`

---

## Commit 2: hub.ts 加 thinking 广播（VPS + repo）

在 `cc-bridge/hub.ts` 的 `startHub()` 函数里，现有的 `setInterval` 轮询逻辑内增加 thinking 文件检查。

在 `captureTimer` 的 setInterval 回调里，**cc_stream 逻辑之后**，加：

```typescript
// ── CC thinking block 文件检测 ──────────────────────────
// Stop hook 把 thinking 写入 /tmp/cc-thinking-*.json
// 这里检测、广播、删除
import { readdirSync, readFileSync, unlinkSync, existsSync } from "node:fs"

// （放在 setInterval 回调末尾）
try {
  const files = readdirSync("/tmp")
    .filter(f => f.startsWith("cc-thinking-") && f.endsWith(".json"))
    .sort()  // 按时间戳排序

  for (const file of files) {
    const fullPath = `/tmp/${file}`
    try {
      const raw = readFileSync(fullPath, "utf-8")
      const data = JSON.parse(raw)

      if (data.thinking) {
        const thinkingMsg = JSON.stringify({
          type: "cc_thinking",
          thinking: data.thinking,
          session_id: data.session_id || "",
          timestamp: data.timestamp || new Date().toISOString(),
        })

        for (const ws of mpClients) {
          if (ws.readyState === WebSocket.OPEN) ws.send(thinkingMsg)
        }
      }

      unlinkSync(fullPath)
    } catch {
      // 单个文件解析失败，跳过，下次轮询再试
    }
  }
} catch {
  // /tmp 读取失败，忽略
}
```

**注意：** `readdirSync`、`readFileSync`、`unlinkSync` 的 import 合并到文件头部已有的 `import { execFileSync } from "node:child_process"` 旁边。

重启 hub 生效：先 kill 旧 hub 进程，再从 `start_hub.sh` 或手动 `bun run hub.ts` 启动。

---

## Commit 3: CC hooks 配置（VPS 端）

在项目级 settings 里配 Stop hook。

文件：`/root/.claude/projects/-root-projects-BunnyPalace/settings.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "bash /root/projects/BunnyPalace/cc-bridge/hooks/extract-thinking.sh"
      }
    ]
  }
}
```

**格式说明：** 如果上面的格式不被 CC 接受（CC 版本差异），试 plugin 风格的嵌套格式：

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /root/projects/BunnyPalace/cc-bridge/hooks/extract-thinking.sh"
          }
        ]
      }
    ]
  }
}
```

验证：CC 启动后执行一个简单任务，检查 `/tmp/` 下是否出现 `cc-thinking-*.json` 文件。

同时在全局 settings 里加 `showThinkingSummaries`：

文件：`/root/.claude/settings.json`

```json
{
  "model": "opus",
  "theme": "dark",
  "showThinkingSummaries": true
}
```

---

## Commit 4: App 端 — CCBridgeWebSocketClient 处理 cc_thinking（App 代码）

在 `CCBridgeWebSocketClient.swift` 中：

1. 加一个 @Observable 属性：

```swift
@Observable
final class CCBridgeWebSocketClient: NSObject {
    // 现有属性...

    /// 最新收到的 CC thinking block
    private(set) var latestThinking: CCThinkingBlock?
}

struct CCThinkingBlock: Identifiable {
    let id = UUID()
    let thinking: String
    let sessionId: String
    let timestamp: Date
}
```

2. 在 WebSocket 消息处理逻辑里加 cc_thinking 分支：

```swift
// 现有的消息处理 switch/if 里加：
case "cc_thinking":
    if let thinking = payload["thinking"] as? String {
        let block = CCThinkingBlock(
            thinking: thinking,
            sessionId: payload["session_id"] as? String ?? "",
            timestamp: Date()
        )
        DispatchQueue.main.async {
            self.latestThinking = block
        }
    }
```

---

## Commit 5: App 端 — UI 展示（App 代码）

复用已有的思考链折叠组件（App 里 DeepSeek/Claude 的思考链 UI）。

在 CC 回复的聊天气泡里，如果 `CCBridgeWebSocketClient.shared.latestThinking` 有值，显示一个可折叠的思考链区域。

具体参考 App 现有的 `ThinkingSummaryView` 或类似组件的实现方式。样式与 Claude 思考链保持一致：
- 灰色小字标题 "CC 思考过程"
- 点击展开/折叠
- 展开后显示 thinking 全文
- monospace 字体，浅灰背景

---

## 测试步骤

1. **VPS 端单元测试：** 手动创建一个假的 transcript JSONL，执行 extract-thinking.sh，确认 /tmp 下生成了 cc-thinking-*.json
2. **hub 广播测试：** 手动在 /tmp 下放一个 cc-thinking-test.json，观察 hub 日志是否广播了 cc_thinking
3. **端到端测试：** 在 CC 里执行一个简单任务（比如 `echo hello`），检查 App 是否收到 thinking 并展示

---

## 依赖

- VPS 上的 `jq`（hook 脚本解析 JSON）：`which jq` 确认已安装
- VPS 上的 `python3`（提取 thinking）：已有
- hub 重启后 cc_stream 也会同时上线（因为 hub.ts 已经包含 cc_stream 代码）
- App 端改动需要编译——攒到一次编译

---

## 注意

- thinking block 可能很长（几千字），WebSocket 单帧发送没问题（ws 库默认支持大帧）
- 文件检测频率跟 cc_stream 共用 500ms 轮询，不额外加 timer
- 如果同时有多个 thinking 文件（CC 连续回复多轮），按时间戳排序依次广播
- Stop hook 只在 CC **完成整轮回复后** 触发，不影响 CC 的流式输出

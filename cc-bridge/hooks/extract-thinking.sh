#!/bin/bash
set -euo pipefail

# CC Stop hook: 从 transcript 提取最后一个 thinking block，原子写入 /tmp 供 hub 轮询。
# hub.ts 检测 /tmp/cc-thinking-*.json，广播 { type: "cc_thinking" } 给 App 后删除文件。

# 从 stdin 读 hook input JSON
HOOK_INPUT=$(cat)

# 解析 transcript 路径 + session id
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
" 2>/dev/null) || true

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

#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

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
            if obj.get('type') == 'assistant':
                for block in obj.get('message', {}).get('content', []):
                    if block.get('type') == 'thinking':
                        thinking_texts.append(block.get('thinking', ''))
        except:
            pass

if thinking_texts:
    print(thinking_texts[-1])
" 2>/dev/null)

if [[ -z "$THINKING" ]]; then
  exit 0
fi

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

#!/bin/bash
set -e
export HOME=/root
export PATH="/root/.bun/bin:$PATH"

# 从credential文件读token
OAUTH_RAW=$(python3 -c "import json; d=json.load(open('/root/.claude/.credentials.json')); print(d['oauthToken'])")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_DIR="/root/projects/MemoryPalace/cc-bridge"

# 生成MCP配置
PARENT_DIR="/root/projects/MemoryPalace"
sed "s|REPLACE_WITH_ABSOLUTE_PATH|$PARENT_DIR|g" "$MCP_DIR/mcp.template.json" > "$MCP_DIR/.mcp.json"

echo "Starting CC Bridge..."

# 启动Hub（如果没在跑）
if ! tmux has-session -t cc-hub 2>/dev/null; then
    tmux new-session -d -s cc-hub "cd $MCP_DIR && export HOME=/root && export PATH=/root/.bun/bin:\$PATH && bun run hub.ts"
    echo "Hub started"
    sleep 2
else
    echo "Hub already running"
fi

# 启动CC（如果没在跑）
if ! tmux has-session -t mp-cc 2>/dev/null; then
    tmux new-session -d -s mp-cc -c /root/projects/BunnyPalace \
        -e "CLAUDE_CODE_OAUTH_TOKEN=$OAUTH_RAW" \
        -e "HOME=/root" \
        -e "PATH=/root/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "claude --mcp-config '$MCP_DIR/.mcp.json'"
    echo "CC started"
else
    echo "CC already running"
fi

echo "CC Bridge ready. Hub: ws://127.0.0.1:7890/cc | App: wss://172.245.88.103/cc"

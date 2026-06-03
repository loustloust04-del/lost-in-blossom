#!/bin/bash
set -e
export HOME=/root
export PATH="/root/.bun/bin:$PATH"

REPO_DIR="/root/projects/BunnyPalace"

# ── CC Bridge ────────────────────────────────────────────────────────────────

OAUTH_RAW=$(python3 -c "import json; d=json.load(open('/root/.claude/.credentials.json')); print(d['oauthToken'])")
MCP_DIR="$REPO_DIR/cc-bridge"

# 生成MCP配置
sed "s|REPLACE_WITH_ABSOLUTE_PATH|$REPO_DIR|g" "$MCP_DIR/mcp.template.json" > "$MCP_DIR/.mcp.json"

# Hub
tmux kill-session -t cc-hub 2>/dev/null || true
tmux new-session -d -s cc-hub \
  "cd $MCP_DIR && export HOME=/root && export PATH=/root/.bun/bin:\$PATH && bun run hub.ts 2>&1 | tee /tmp/cc-hub.log"
echo "cc-hub started"
sleep 2

# Claude Code
tmux kill-session -t mp-cc 2>/dev/null || true
tmux new-session -d -s mp-cc -c "$REPO_DIR" \
  -e "CLAUDE_CODE_OAUTH_TOKEN=$OAUTH_RAW" \
  -e "HOME=/root" \
  -e "PATH=/root/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "claude --mcp-config '$MCP_DIR/.mcp.json'"
echo "mp-cc started"

# ── VPS MCP Server ───────────────────────────────────────────────────────────

VPS_MCP_DIR="$REPO_DIR/vps-mcp"

# Install deps if needed
if [ ! -d "$VPS_MCP_DIR/node_modules" ]; then
  echo "Installing vps-mcp dependencies..."
  cd "$VPS_MCP_DIR" && bun install
fi

# Load token from .env if present
if [ -f "$REPO_DIR/.env" ]; then
  # shellcheck disable=SC1091
  source "$REPO_DIR/.env"
fi
MCP_AUTH_TOKEN="${MCP_AUTH_TOKEN:-25791d6ab21b2de4d956be03aa1a6519bd3faba32e83f75235c3130c8bdef6b4}"

tmux kill-session -t vps-mcp 2>/dev/null || true
tmux new-session -d -s vps-mcp \
  "export MCP_AUTH_TOKEN='$MCP_AUTH_TOKEN' && \
   export HOME=/root && \
   export PATH=/root/.bun/bin:\$PATH && \
   cd $VPS_MCP_DIR && \
   bun run server.ts 2>&1 | tee /tmp/vps-mcp.log"
echo "vps-mcp started"

echo ""
echo "All services started:"
echo "  cc-hub  → ws://127.0.0.1:7890"
echo "  vps-mcp → http://127.0.0.1:7891 (HTTPS via nginx :8891)"
echo ""
echo "VPS MCP token: $MCP_AUTH_TOKEN"

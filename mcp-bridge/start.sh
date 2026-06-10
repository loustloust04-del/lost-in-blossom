#!/bin/bash
set -e

cd /root/projects/BunnyPalace/mcp-bridge

# Start supergateway (stdio→streamableHttp, port 3100)
supergateway \
  --port 3100 \
  --stateful \
  --stdio "node vps-mcp-server.js" \
  --outputTransport streamableHttp \
  --cors \
  > /tmp/supergateway.log 2>&1 &
SG_PID=$!
echo "[start.sh] supergateway PID=$SG_PID"

# Wait for supergateway to be ready
# Readiness probe: plain GET (no MCP session, no child spawned).
# In stateful mode a child is spawned only on POST initialize, so probing
# with GET avoids leaking an orphan session/child on every restart.
for i in $(seq 1 10); do
  if curl -s -o /dev/null http://localhost:3100/mcp 2>/dev/null; then
    echo "[start.sh] supergateway ready"
    break
  fi
  sleep 1
done

# Start MCP REST bridge (port 3200), auto-connect to supergateway
export MCP_BRIDGE_PORT=3200
export MCP_BRIDGE_TOKEN="bunny-mcp-2026"
export MCP_DEFAULT_SERVERS="vps=http://localhost:3100/mcp"

exec node mcp-rest-bridge.js

#!/bin/bash
set -e

cd /root/projects/BunnyPalace/mcp-bridge

# Start supergateway (stdio→streamableHttp, port 3100)
supergateway \
  --port 3100 \
  --stdio "node vps-mcp-server.js" \
  --outputTransport streamableHttp \
  --cors \
  > /tmp/supergateway.log 2>&1 &
SG_PID=$!
echo "[start.sh] supergateway PID=$SG_PID"

# Wait for supergateway to be ready
# Stateless mode (2026-07-28): single persistent stdio child shared by all
# requests — no per-session spawn, no session-id requirement, no child leak.
# Was --stateful: sessions accumulated orphan children and cold-start races
# made gateway tools/list intermittently return 0.
for i in $(seq 1 10); do
  if curl -s -o /dev/null http://localhost:3100/mcp 2>/dev/null; then
    echo "[start.sh] supergateway ready"
    break
  fi
  sleep 1
done

# Start MCP REST bridge (port 3200), auto-connect to supergateway
export MCP_BRIDGE_PORT=3200
# MCP_BRIDGE_TOKEN must be set in the environment before calling this script.
# Do NOT set a default here — the bridge will refuse to start without a real token.
# Load local .env if present (holds MCP_BRIDGE_TOKEN)
if [ -f .env ]; then set -a; . ./.env; set +a; fi
if [ -z "${MCP_BRIDGE_TOKEN}" ]; then
  echo "[mcp-bridge] error: MCP_BRIDGE_TOKEN is not set" >&2
  exit 1
fi
export MCP_DEFAULT_SERVERS="vps=http://localhost:3100/mcp"

exec node mcp-rest-bridge.js

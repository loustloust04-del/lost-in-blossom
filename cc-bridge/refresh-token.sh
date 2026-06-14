#!/bin/bash
# Claude Code OAuth token 自动刷新
# cron: */30 * * * * /root/projects/BunnyPalace/cc-bridge/refresh-token.sh

CRED_FILE="/root/.claude/.credentials.json"

if [ ! -f "$CRED_FILE" ]; then
    echo "[refresh] credentials file not found"
    exit 1
fi

REFRESH_TOKEN=$(python3 -c "import json; print(json.load(open('$CRED_FILE')).get('refreshToken',''))")

if [ -z "$REFRESH_TOKEN" ]; then
    echo "[refresh] no refresh token"
    exit 1
fi

# 用 refresh token 获取新的 access token
RESPONSE=$(curl -s -X POST "https://console.anthropic.com/v1/oauth/token" \
    -H "Content-Type: application/json" \
    -d "{\"grant_type\": \"refresh_token\", \"refresh_token\": \"$REFRESH_TOKEN\", \"client_id\": \"9d1c250a-e61b-44d9-88ed-5944d1962f5e\"}" 2>/dev/null)

NEW_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)
NEW_REFRESH=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('refresh_token',''))" 2>/dev/null)

if [ -n "$NEW_TOKEN" ] && [ ${#NEW_TOKEN} -gt 20 ]; then
    python3 -c "
import json
with open('$CRED_FILE') as f:
    d = json.load(f)
d['oauthToken'] = '$NEW_TOKEN'
if '$NEW_REFRESH':
    d['refreshToken'] = '$NEW_REFRESH'
with open('$CRED_FILE','w') as f:
    json.dump(d, f, indent=2)
print('[refresh] token refreshed successfully')
"
else
    echo "[refresh] failed: $RESPONSE"
fi

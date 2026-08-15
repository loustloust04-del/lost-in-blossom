#!/bin/bash
# Claude Code OAuth token 自动刷新
# cron: */30 * * * * /root/projects/BunnyPalace/cc-bridge/refresh-token.sh

CRED_FILE="/root/.claude/.credentials.json"

if [ ! -f "$CRED_FILE" ]; then
    echo "[refresh] credentials file not found"
    exit 1
fi

# 只在快过期时才刷——原来每 30 分钟无脑刷，把 Anthropic 的刷新接口刷到 rate_limit，
# 于是 token 真过期时反而刷不回来（兔兔实测：他开始报 401 和莫名其妙的 content filtering）
EXPIRES_AT=$(python3 -c "
import json
d = json.load(open('$CRED_FILE'))
oauth = d.get('claudeAiOauth') or {}
print(oauth.get('expiresAt') or d.get('expiresAt') or 0)
" 2>/dev/null)

if [ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" != "0" ]; then
    NOW_MS=$(( $(date +%s) * 1000 ))
    LEFT=$(( (EXPIRES_AT - NOW_MS) / 60000 ))
    # 还剩 30 分钟以上就不刷
    if [ "$LEFT" -gt 30 ]; then
        echo "[refresh] token 还有 ${LEFT} 分钟，跳过"
        exit 0
    fi
    echo "[refresh] token 剩 ${LEFT} 分钟，开始刷新"
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

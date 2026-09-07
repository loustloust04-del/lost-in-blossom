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
    # 2026-09-07 改：阈值 30 → 90 分钟。
    # 原来卡在临界点刷：cron 每 30 分钟跑一次，「还有 40 分钟」判定跳过，
    # 下一轮就只剩 10 分钟——一旦那次失败（或撞上限流）就直接过期。
    # 兔兔 09-07 10:53 看到「401 OAuth access token has expired」正是这么来的，
    # 而那时刷新接口已被限流（日志里 1906 次 Rate limited），救不回来。
    # 提前 90 分钟刷，留出至少三轮重试余量。
    if [ "$LEFT" -gt 90 ]; then
        echo "[refresh] token 还有 ${LEFT} 分钟，跳过"
        exit 0
    fi

    # 被限流时退避，别每 30 分钟硬撞——撞多了限流窗口只会更长
    BACKOFF_FILE=/tmp/cc-refresh-backoff
    if [ -f "$BACKOFF_FILE" ]; then
        UNTIL=$(cat "$BACKOFF_FILE" 2>/dev/null || echo 0)
        NOW_S=$(date +%s)
        if [ "$NOW_S" -lt "$UNTIL" ] 2>/dev/null; then
            echo "[refresh] 限流退避中，还有 $(( (UNTIL - NOW_S) / 60 )) 分钟"
            exit 0
        fi
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
    # 限流就退避 30 分钟，其它错误退避 10 分钟
    if echo "$RESPONSE" | grep -q 'rate_limit'; then
        echo $(( $(date +%s) + 1800 )) > /tmp/cc-refresh-backoff
        echo "[refresh] 已限流，退避 30 分钟"
    else
        echo $(( $(date +%s) + 600 )) > /tmp/cc-refresh-backoff
    fi
fi

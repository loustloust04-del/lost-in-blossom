#!/bin/bash
# 切换 CC 消息是否携带最近对话上下文
# 用法: ./toggle-context.sh [on|off|status]

HUB_DIR=/root/projects/BunnyPalace/cc-bridge
STATE_FILE=$HUB_DIR/.context-state
HUB_TOKEN="SH74v-IveupxWPr-6TU0CH0GDvfIxSDC"

current_state() {
  PID=$(lsof -t -i :7890 -sTCP:LISTEN 2>/dev/null | head -1)
  if [ -z "$PID" ]; then echo "hub-down"; return; fi
  VAL=$(tr '\0' '\n' < /proc/$PID/environ 2>/dev/null | grep '^CC_INJECT_SUMMARY=' | cut -d= -f2)
  if [ "$VAL" = "0" ]; then echo "off"; else echo "on"; fi
}

restart_hub() {
  local inject=$1
  kill $(lsof -t -i :7890 -sTCP:LISTEN) 2>/dev/null
  sleep 2
  cd $HUB_DIR
  HOME=/root PATH=/root/.bun/bin:$PATH \
    MP_CC_HUB_TOKEN="$HUB_TOKEN" \
    MP_CC_WORKDIR=/root/projects/BunnyBridge \
    CC_INJECT_SUMMARY=$inject \
    nohup bun run hub.ts >> /tmp/hub.log 2>&1 &
  echo "$inject" > $STATE_FILE
  sleep 3
  if lsof -i :7890 -sTCP:LISTEN >/dev/null 2>&1; then return 0; else return 1; fi
}

case "${1:-status}" in
  on)
    restart_hub 1 && echo "✅ 上下文注入已开启 — CC 收到消息时会带上最近对话" \
                  || echo "❌ hub 启动失败，看 /tmp/hub.log"
    ;;
  off)
    restart_hub 0 && echo "✅ 上下文注入已关闭 — CC 只收到当前这条消息" \
                  || echo "❌ hub 启动失败，看 /tmp/hub.log"
    ;;
  status)
    S=$(current_state)
    case $S in
      on)       echo "📎 当前：开启 — CC 收到消息时会带上最近对话" ;;
      off)      echo "✂️  当前：关闭 — CC 只收到当前这条消息" ;;
      hub-down) echo "⚠️  hub 没在运行" ;;
    esac
    ;;
  *)
    echo "用法: $0 [on|off|status]"
    exit 1
    ;;
esac

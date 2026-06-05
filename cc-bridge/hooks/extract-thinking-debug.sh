#!/bin/bash
# 先把stdin保存一份
STDIN_COPY=$(cat)
echo "$STDIN_COPY" > /tmp/hook-debug-stdin.json

# 跑真正的脚本，把stderr捕获
echo "$STDIN_COPY" | bash /root/projects/BunnyPalace/cc-bridge/hooks/extract-thinking.sh > /tmp/hook-debug-stdout.log 2> /tmp/hook-debug-stderr.log
echo "exit: $?" >> /tmp/hook-debug-stderr.log

# 记录环境
env > /tmp/hook-debug-env.log 2>&1

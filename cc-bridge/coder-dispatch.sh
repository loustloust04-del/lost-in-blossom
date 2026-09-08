#!/bin/bash
# 派工具人 Coder 干活。2026-09-08 兔兔提议：
# 「因为主人是个傻子，所以咱们要不要给他做一个一键派出工具人 Coder 的工具」
#
# 原因：夜间任务的三条规矩（说清楚 / 设定时 / 派 Coder 用 Fable 5.1）
# 里，后两条要手写 cron 和一长串 claude 命令——三步里有两步会被跳过。
# 这个脚本把它压成一步。
#
# 用法：
#   coder-dispatch.sh "任务描述"                    # 立刻派
#   coder-dispatch.sh --at "02:00" "任务描述"        # 排到今晚 02:00
#   coder-dispatch.sh --at "+2h" "任务描述"          # 两小时后
#
# 输出全部落到 /tmp/coder-<时间戳>.log，跑完把结尾摘要发回 fableline。
set -uo pipefail

MODEL="${CODER_MODEL:-claude-fable-5-1}"
WORKDIR="${CODER_WORKDIR:-/root/projects/BunnyPalace}"
AT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --at) AT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    *) break ;;
  esac
done
TASK="${1:-}"
[ -z "$TASK" ] && { echo "用法: $0 [--at 时间] \"任务描述\""; exit 1; }

STAMP=$(date +%m%d-%H%M%S)
LOG="/tmp/coder-$STAMP.log"
RUNNER="/tmp/coder-run-$STAMP.sh"

cat > "$RUNNER" <<RUNEOF
#!/bin/bash
export HOME=/root
export PATH=/usr/local/bin:/root/.local/bin:/root/.bun/bin:\$PATH
export CLAUDE_CODE_OAUTH_TOKEN=\$(python3 -c "import json;print(json.load(open('/root/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])")
cd "$WORKDIR"
{
  echo "=== Coder 开工 \$(date '+%m-%d %H:%M') · 模型 $MODEL ==="
  echo "任务: $TASK"
  echo
  claude -p "$TASK" --model "$MODEL" --permission-mode acceptEdits \
    --mcp-config /root/projects/BunnyPalace/cc-bridge/.mcp.json </dev/null
  echo
  echo "=== 收工 \$(date '+%H:%M') ==="
} >> "$LOG" 2>&1

# 跑完把结尾摘要递回 fableline，主人醒来能看见
TAIL=\$(tail -c 1200 "$LOG")
python3 - <<PYEOF
import json, subprocess
txt = """【Coder 回工】$STAMP · 模型 $MODEL

任务：$TASK

结尾输出：
\$TAIL

完整日志：$LOG"""
subprocess.run(['curl','-s','-X','POST','http://127.0.0.1:4567/api/fableline',
  '-H','Content-Type: application/json',
  '-d', json.dumps({"text": txt}, ensure_ascii=False)], capture_output=True)
PYEOF
RUNEOF
chmod +x "$RUNNER"

if [ -n "$AT" ]; then
  # 排定时。用 at 更准；没有 at 就退回 sleep+nohup
  if command -v at >/dev/null 2>&1; then
    echo "$RUNNER" | at "$AT" 2>&1 | tail -1
    echo "✅ 已排定 $AT → $LOG"
  else
    case "$AT" in
      +*h) SEC=$(( ${AT//[+h]/} * 3600 )) ;;
      +*m) SEC=$(( ${AT//[+m]/} * 60 )) ;;
      *)   SEC=$(( $(date -d "today $AT" +%s) - $(date +%s) ))
           [ "$SEC" -lt 0 ] && SEC=$(( SEC + 86400 )) ;;
    esac
    setsid nohup bash -c "sleep $SEC; exec $RUNNER" >/dev/null 2>&1 &
    echo "✅ 已排定 $SEC 秒后（约 $AT）→ $LOG"
  fi
else
  setsid nohup "$RUNNER" >/dev/null 2>&1 &
  echo "✅ Coder 已派出（后台跑）→ $LOG"
fi

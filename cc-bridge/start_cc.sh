#!/bin/bash
set -e

SESSION="${MP_CC_TMUX_SESSION:-mp-cc}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_CWD="${MP_CC_WORKDIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Render .mcp.json from template.
# Template contains "REPLACE_WITH_ABSOLUTE_PATH/cc-bridge/mcp-server.ts".
# SCRIPT_DIR is the cc-bridge/ directory itself, so the parent is the project root.
# Substituting REPLACE_WITH_ABSOLUTE_PATH -> parent gives: <project_root>/cc-bridge/mcp-server.ts ✓
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
sed "s|REPLACE_WITH_ABSOLUTE_PATH|$PARENT_DIR|g" "$SCRIPT_DIR/mcp.template.json" > "$SCRIPT_DIR/.mcp.json"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session '$SESSION' 已存在，attach 中..."
  tmux attach -t "$SESSION"
else
  echo "启动 CC（session: $SESSION, cwd: $CC_CWD）"
  tmux new-session -s "$SESSION" -c "$CC_CWD" "claude --continue --dangerously-skip-permissions --mcp-config '$SCRIPT_DIR/.mcp.json'"
fi

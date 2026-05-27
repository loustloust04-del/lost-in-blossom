#!/usr/bin/env bash
#
# sync-skill-dropdowns.sh
#
# Syncs the skill dropdown options in GitHub issue templates
# with the actual contents of the skills/ directory.
#
# Usage:
#   ./.github/scripts/sync-skill-dropdowns.sh          # update in place
#   ./.github/scripts/sync-skill-dropdowns.sh --check  # exit 1 if out of sync (CI mode)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
TEMPLATE_DIR="$REPO_ROOT/.github/ISSUE_TEMPLATE"

TEMPLATES=(
  "$TEMPLATE_DIR/skill-content-bug.yml"
  "$TEMPLATE_DIR/skill-enhancement.yml"
)

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=true
fi

# Write the new options to a temp file for insertion
OPTIONS_FILE="$(mktemp)"
trap 'rm -f "$OPTIONS_FILE"' EXIT

for skill in $(ls "$SKILLS_DIR" | sort); do
  echo "        - ${skill}" >> "$OPTIONS_FILE"
done

# Replace the options list under the `id: skill` dropdown in a template.
# State machine:
#   0 = scanning for `id: skill`
#   1 = found `id: skill`, scanning for `options:`
#   2 = inside options block, eating old entries
patch_template() {
  local file="$1"

  awk -v optfile="$OPTIONS_FILE" '
    BEGIN { state = 0 }

    state == 0 && /^[[:space:]]*id:[[:space:]]*skill[[:space:]]*$/ {
      state = 1
      print
      next
    }

    state == 1 && /^[[:space:]]*options:[[:space:]]*$/ {
      state = 2
      print
      while ((getline line < optfile) > 0) print line
      close(optfile)
      next
    }

    # While in state 2, skip old option lines (        - lowercase-name)
    state == 2 && /^[[:space:]]*- [a-z]/ {
      next
    }

    # Any non-option line while in state 2 means the block ended
    state == 2 {
      state = 0
      print
      next
    }

    { print }
  ' "$file"
}

dirty=false

for template in "${TEMPLATES[@]}"; do
  if [[ ! -f "$template" ]]; then
    echo "WARNING: template not found: $template" >&2
    continue
  fi

  patched="$(patch_template "$template")"

  if ! diff -q <(echo "$patched") "$template" > /dev/null 2>&1; then
    if $CHECK_MODE; then
      echo "DRIFT: $template is out of sync with skills/ directory" >&2
      diff --unified <(echo "$patched") "$template" >&2 || true
      dirty=true
    else
      echo "$patched" > "$template"
      echo "UPDATED: $template"
    fi
  else
    echo "OK: $template (already in sync)"
  fi
done

if $CHECK_MODE && $dirty; then
  echo "" >&2
  echo "Run './.github/scripts/sync-skill-dropdowns.sh' to fix." >&2
  exit 1
fi

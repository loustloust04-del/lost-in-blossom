#!/usr/bin/env bash
#
# validate-issue-template.sh
#
# Validates an issue body against the repository's supported issue form shapes.
#
# Usage:
#   bash ./.github/scripts/validate-issue-template.sh <issue-body-file>
#
# Exits 0 if the issue matches one of the supported templates, 1 otherwise.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash ./.github/scripts/validate-issue-template.sh <issue-body-file>" >&2
  exit 2
fi

BODY_FILE="$1"

if [[ ! -f "$BODY_FILE" ]]; then
  echo "ERROR: issue body file not found: $BODY_FILE" >&2
  exit 2
fi

section_has_content() {
  local heading="$1"
  local heading_line="### $heading"

  awk -v heading_line="$heading_line" '
    $0 == heading_line {
      in_section = 1
      next
    }

    in_section && /^### / {
      finished = 1
      exit
    }

    in_section && $0 !~ /^[[:space:]]*$/ {
      has_content = 1
    }

    END {
      if (!in_section) {
        exit 1
      }

      exit has_content ? 0 : 1
    }
  ' "$BODY_FILE"
}

matches_template() {
  local template_name="$1"
  shift

  local heading
  for heading in "$@"; do
    if ! section_has_content "$heading"; then
      return 1
    fi
  done

  echo "VALID: issue matches template '$template_name'"
  return 0
}

if matches_template \
  "skill-content-bug" \
  "Affected Skill" \
  "What is incorrect?" \
  "Apple Documentation References" \
  "Environment"; then
  exit 0
fi

if matches_template \
  "skill-enhancement" \
  "Affected Skill" \
  "Type of Enhancement" \
  "What should be improved?"; then
  exit 0
fi

if matches_template \
  "new-skill-request" \
  "Proposed Skill Name" \
  "What should the skill cover?" \
  "Why is this needed?" \
  "Key Apple Documentation"; then
  exit 0
fi

echo "INVALID: issue does not match any supported issue template" >&2
exit 1
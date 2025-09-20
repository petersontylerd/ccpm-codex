#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
META_FILE="$PLAN_DIR/plan-meta.yaml"
LOG_FILE="$PLAN_DIR/revisions.log"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

EPIC_ID=""
NAME=""
DESCRIPTION=""
PRIORITY=""
FACILITATOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic)
      shift
      EPIC_ID=${1:-}
      ;;
    --name)
      shift
      NAME=${1:-}
      ;;
    --description)
      shift
      DESCRIPTION=${1:-}
      ;;
    --priority)
      shift
      PRIORITY=${1:-}
      ;;
    --facilitator)
      shift
      FACILITATOR=${1:-}
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
  shift || true
done

if [ -z "$EPIC_ID" ]; then
  log_fatal "--epic is required (format E###)"
fi

if [[ ! $EPIC_ID =~ ^E[0-9]{3}$ ]]; then
  log_fatal "Epic id must look like E###"
fi

EPIC_DIR="$PLAN_DIR/epics/epic-$EPIC_ID"
EPIC_FILE="$EPIC_DIR/epic-$EPIC_ID.yaml"
if [ ! -f "$EPIC_FILE" ]; then
  log_fatal "Epic file not found: $EPIC_FILE"
fi

if [ -z "$NAME$DESCRIPTION$PRIORITY$FACILITATOR" ]; then
  log_fatal "Provide at least one field to update (--name/--description/--priority/--facilitator)."
fi

TIMESTAMP=$(get_chicago_timestamp)
[ -n "$TIMESTAMP" ] || log_fatal "Failed to capture timestamp"

python3 - "$EPIC_FILE" "$NAME" "$DESCRIPTION" "$PRIORITY" "$FACILITATOR" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
name, description, priority, facilitator = sys.argv[2:6]
text = path.read_text()

def replace_field(text, key, value):
    if not value:
        return text
    pattern = re.compile(rf'({key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

def replace_overview_desc(text, value):
    if not value:
        return text
    pattern = re.compile(r'(overview:\n(?:.*\n)*?\s{2}description:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

text = replace_field(text, 'epic_name', name)
text = replace_field(text, 'priority', priority)
text = replace_field(text, 'facilitator', facilitator)
text = replace_overview_desc(text, description)

path.write_text(text)
PY

update_meta() {
  local ts=$1
  local command=$2
  local initialized_at initialized_by revision_count
  if [ -f "$META_FILE" ]; then
    initialized_at=$(awk -F'"' '/initialized_at:/ {print $2; exit}' "$META_FILE")
    initialized_by=$(awk -F'"' '/initialized_by:/ {print $2; exit}' "$META_FILE")
    revision_count=$(awk -F':' '/revision_count:/ {gsub(/ /,"",$2); print $2; exit}' "$META_FILE")
  fi
  initialized_at=${initialized_at:-$ts}
  initialized_by=${initialized_by:-plan:init}
  revision_count=${revision_count:-0}
  revision_count=$((revision_count + 1))
  cat > "$META_FILE" <<EOF_META
initialized_at: "$initialized_at"
initialized_by: "$initialized_by"
last_updated: "$ts"
last_command: "$command"
revision_count: $revision_count
EOF_META
}

update_meta "$TIMESTAMP" "epic:update"
printf '%s | epic:update | Updated epic %s\n' "$TIMESTAMP" "$EPIC_ID" >> "$LOG_FILE"

log_info "Updated epic $EPIC_ID"

exit 0

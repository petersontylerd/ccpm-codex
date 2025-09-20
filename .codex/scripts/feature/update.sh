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
FEATURE_ID=""
NAME=""
DESCRIPTION=""
USER_VALUE=""
PRIORITY=""
FACILITATOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic)
      shift
      EPIC_ID=${1:-}
      ;;
    --feature)
      shift
      FEATURE_ID=${1:-}
      ;;
    --name)
      shift
      NAME=${1:-}
      ;;
    --description)
      shift
      DESCRIPTION=${1:-}
      ;;
    --user-value)
      shift
      USER_VALUE=${1:-}
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

if [ -z "$EPIC_ID" ] || [ -z "$FEATURE_ID" ]; then
  log_fatal "--epic and --feature are required (E### / F###)"
fi
if [[ ! $EPIC_ID =~ ^E[0-9]{3}$ ]] || [[ ! $FEATURE_ID =~ ^F[0-9]{3}$ ]]; then
  log_fatal "IDs must match E### and F### formats"
fi

FEATURE_FILE="$PLAN_DIR/epics/epic-$EPIC_ID/features-$EPIC_ID/feature-$EPIC_ID-$FEATURE_ID/feature-$EPIC_ID-$FEATURE_ID.yaml"
if [ ! -f "$FEATURE_FILE" ]; then
  log_fatal "Feature file not found: $FEATURE_FILE"
fi

if [ -z "$NAME$DESCRIPTION$USER_VALUE$PRIORITY$FACILITATOR" ]; then
  log_fatal "Provide at least one field to update"
fi

TIMESTAMP=$(get_chicago_timestamp)
[ -n "$TIMESTAMP" ] || log_fatal "Failed to capture timestamp"

python3 - "$FEATURE_FILE" "$NAME" "$DESCRIPTION" "$USER_VALUE" "$PRIORITY" "$FACILITATOR" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
name, description, user_value, priority, facilitator = sys.argv[2:7]
text = path.read_text()

def replace_field(text, key, value):
    if not value:
        return text
    pattern = re.compile(rf'({key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

def replace_overview(text, key, value):
    if not value:
        return text
    pattern = re.compile(rf'(overview:\n(?:.*\n)*?\s{{2}}{key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

text = replace_field(text, 'feature_name', name)
text = replace_field(text, 'priority', priority)
text = replace_field(text, 'facilitator', facilitator)
text = replace_overview(text, 'description', description)
text = replace_overview(text, 'user_value', user_value)

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

update_meta "$TIMESTAMP" "feature:update"
printf '%s | feature:update | Updated feature %s under %s\n' "$TIMESTAMP" "$FEATURE_ID" "$EPIC_ID" >> "$LOG_FILE"

log_info "Updated feature $FEATURE_ID (epic $EPIC_ID)"

exit 0

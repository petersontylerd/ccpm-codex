#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
PLAN_TEMPLATE_DIR="$REPO_ROOT/.codex/product-plan.template"
META_FILE="$PLAN_DIR/plan-meta.yaml"
LOG_FILE="$PLAN_DIR/revisions.log"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

NAME=""
DESCRIPTION=""
PRIORITY=""
FACILITATOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [ -z "$NAME" ]; then
  log_fatal "--name is required"
fi

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan missing. Run plan:init first."
fi

template_epic="$PLAN_TEMPLATE_DIR/epics/epic-E001/epic-E001.yaml"
if [ ! -f "$template_epic" ]; then
  log_fatal "Epic template not found at $template_epic"
fi

get_next_epic_id() {
  local max=0
  if [ -d "$PLAN_DIR/epics" ]; then
    while IFS= read -r dir; do
      local base
      base=$(basename "$dir")
      local num
      num=${base#epic-E}
      if [[ $num =~ ^[0-9]+$ ]]; then
        if ((10#$num > max)); then
          max=$((10#$num))
        fi
      fi
    done < <(find "$PLAN_DIR/epics" -mindepth 1 -maxdepth 1 -type d -name 'epic-*' 2>/dev/null)
  fi
  local next=$((max + 1))
  printf 'E%03d' "$next"
}

NEW_EPIC_ID=$(get_next_epic_id)
NEW_EPIC_DIR="$PLAN_DIR/epics/epic-$NEW_EPIC_ID"
FEATURES_DIR="$NEW_EPIC_DIR/features-$NEW_EPIC_ID"

if [ -d "$NEW_EPIC_DIR" ]; then
  log_fatal "Epic directory already exists: $NEW_EPIC_DIR"
fi

mkdir -p "$FEATURES_DIR"
cp "$template_epic" "$NEW_EPIC_DIR/epic-$NEW_EPIC_ID.yaml"

TIMESTAMP=$(get_chicago_timestamp)
if [ -z "$TIMESTAMP" ]; then
  log_fatal "Failed to capture current timestamp"
fi

epic_file="$NEW_EPIC_DIR/epic-$NEW_EPIC_ID.yaml"
python3 - "$epic_file" "$NEW_EPIC_ID" "$NAME" "$TIMESTAMP" "$PRIORITY" "$FACILITATOR" "$DESCRIPTION" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
epic_id, epic_name, date_value, priority, facilitator, description = sys.argv[2:8]
text = path.read_text()

def replace_field(text, key, value):
    if value == "":
        return text
    pattern = re.compile(rf'({key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

def replace_overview_description(text, value):
    if value == "":
        return text
    pattern = re.compile(r'(overview:\n(?:.*\n)*?\s{2}description:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

text = replace_field(text, 'epic_id', epic_id)
text = replace_field(text, 'epic_name', epic_name)
text = replace_field(text, 'date', date_value)
text = replace_field(text, 'priority', priority)
text = replace_field(text, 'facilitator', facilitator)
text = replace_overview_description(text, description)

path.write_text(text)
PY

update_meta() {
  local timestamp=$1
  local command=$2
  local initialized_at initialized_by revision_count
  if [ -f "$META_FILE" ]; then
    initialized_at=$(awk -F'"' '/initialized_at:/ {print $2; exit}' "$META_FILE")
    initialized_by=$(awk -F'"' '/initialized_by:/ {print $2; exit}' "$META_FILE")
    revision_count=$(awk -F':' '/revision_count:/ {gsub(/ /,"",$2); print $2; exit}' "$META_FILE")
  fi
  initialized_at=${initialized_at:-$timestamp}
  initialized_by=${initialized_by:-plan:init}
  revision_count=${revision_count:-0}
  revision_count=$((revision_count + 1))
  cat > "$META_FILE" <<EOF_META
initialized_at: "$initialized_at"
initialized_by: "$initialized_by"
last_updated: "$timestamp"
last_command: "$command"
revision_count: $revision_count
EOF_META
}

update_meta "$TIMESTAMP" "epic:new"
printf '%s | epic:new | Created epic %s (%s)\n' "$TIMESTAMP" "$NEW_EPIC_ID" "$NAME" >> "$LOG_FILE"

log_info "Created epic $NEW_EPIC_ID"
log_info "Location: $NEW_EPIC_DIR"

exit 0

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

EPIC_ID=""
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

if [ -z "$EPIC_ID" ] || [ -z "$NAME" ]; then
  log_fatal "--epic and --name are required"
fi

if [[ ! $EPIC_ID =~ ^E[0-9]{3}$ ]]; then
  log_fatal "--epic must look like E###"
fi

EPIC_DIR="$PLAN_DIR/epics/epic-$EPIC_ID"
FEATURES_DIR="$EPIC_DIR/features-$EPIC_ID"

if [ ! -d "$EPIC_DIR" ]; then
  log_fatal "Epic $EPIC_ID not found."
fi

mkdir -p "$FEATURES_DIR"

template_feature="$PLAN_TEMPLATE_DIR/epics/epic-E001/features-E001/feature-E001-F001/feature-E001-F001.yaml"
if [ ! -f "$template_feature" ]; then
  log_fatal "Feature template not found at $template_feature"
fi

get_next_feature_id() {
  local max=0
  while IFS= read -r dir; do
    local base
    base=$(basename "$dir")
    local suffix
    suffix=${base#feature-$EPIC_ID-}
    suffix=${suffix#F}
    if [[ $suffix =~ ^[0-9]+$ ]]; then
      if ((10#$suffix > max)); then
        max=$((10#$suffix))
      fi
    fi
  done < <(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d -name "feature-$EPIC_ID-F*" 2>/dev/null)
  local next=$((max + 1))
  printf 'F%03d' "$next"
}

FEATURE_ID=$(get_next_feature_id)
FEATURE_DIR="$FEATURES_DIR/feature-$EPIC_ID-$FEATURE_ID"
USER_STORIES_DIR="$FEATURE_DIR/user-stories-$EPIC_ID-$FEATURE_ID"

if [ -d "$FEATURE_DIR" ]; then
  log_fatal "Feature directory already exists: $FEATURE_DIR"
fi

mkdir -p "$USER_STORIES_DIR"
cp "$template_feature" "$FEATURE_DIR/feature-$EPIC_ID-$FEATURE_ID.yaml"

TIMESTAMP=$(get_chicago_timestamp)
if [ -z "$TIMESTAMP" ]; then
  log_fatal "Failed to capture current timestamp"
fi

feature_file="$FEATURE_DIR/feature-$EPIC_ID-$FEATURE_ID.yaml"
python3 - "$feature_file" "$FEATURE_ID" "$EPIC_ID" "$NAME" "$TIMESTAMP" "$PRIORITY" "$FACILITATOR" "$DESCRIPTION" "$USER_VALUE" <<'PY'
import sys
import re
from pathlib import Path

path = Path(sys.argv[1])
feature_id, epic_id, feature_name, date_value, priority, facilitator, description, user_value = sys.argv[2:10]
text = path.read_text()

def replace_field(text, key, value):
    if value == "":
        return text
    pattern = re.compile(rf'({key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

def replace_scoped(text, section, key, value):
    if value == "":
        return text
    pattern = re.compile(rf'({section}:\n(?:.*\n)*?\s{{2}}{key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

text = replace_field(text, 'feature_id', feature_id)
text = replace_field(text, 'parent_epic', epic_id)
text = replace_field(text, 'feature_name', feature_name)
text = replace_field(text, 'date', date_value)
text = replace_field(text, 'priority', priority)
text = replace_field(text, 'facilitator', facilitator)
text = replace_scoped(text, 'overview', 'description', description)
text = replace_scoped(text, 'overview', 'user_value', user_value)

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

update_meta "$TIMESTAMP" "feature:new"
printf '%s | feature:new | Created feature %s under %s (%s)\n' "$TIMESTAMP" "$FEATURE_ID" "$EPIC_ID" "$NAME" >> "$LOG_FILE"

log_info "Created feature $FEATURE_ID under epic $EPIC_ID"
log_info "Location: $FEATURE_DIR"

exit 0

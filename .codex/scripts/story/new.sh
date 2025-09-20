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
FEATURE_ID=""
NAME=""
AS_A=""
I_WANT=""
SO_THAT=""
DESCRIPTION=""
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
    --as)
      shift
      AS_A=${1:-}
      ;;
    --i-want)
      shift
      I_WANT=${1:-}
      ;;
    --so-that)
      shift
      SO_THAT=${1:-}
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

if [ -z "$EPIC_ID" ] || [ -z "$FEATURE_ID" ] || [ -z "$NAME" ] || [ -z "$AS_A" ] || [ -z "$I_WANT" ] || [ -z "$SO_THAT" ]; then
  log_fatal "--epic, --feature, --name, --as, --i-want, and --so-that are required"
fi

if [[ ! $EPIC_ID =~ ^E[0-9]{3}$ ]]; then
  log_fatal "--epic must look like E###"
fi
if [[ ! $FEATURE_ID =~ ^F[0-9]{3}$ ]]; then
  log_fatal "--feature must look like F###"
fi

FEATURE_DIR="$PLAN_DIR/epics/epic-$EPIC_ID/features-$EPIC_ID/feature-$EPIC_ID-$FEATURE_ID"
USER_STORY_DIR="$FEATURE_DIR/user-stories-$EPIC_ID-$FEATURE_ID"
if [ ! -d "$FEATURE_DIR" ]; then
  log_fatal "Feature $FEATURE_ID under epic $EPIC_ID not found."
fi

mkdir -p "$USER_STORY_DIR"

template_story="$PLAN_TEMPLATE_DIR/epics/epic-E001/features-E001/feature-E001-F001/user-stories-E001-F001/user-story-E001-F001-US0001.yaml"
if [ ! -f "$template_story" ]; then
  log_fatal "User story template not found at $template_story"
fi

get_next_story_id() {
  local max=0
  while IFS= read -r file; do
    local base
    base=$(basename "$file")
    local num
    num=${base#user-story-$EPIC_ID-$FEATURE_ID-US}
    num=${num%.yaml}
    if [[ $num =~ ^[0-9]+$ ]]; then
      if ((10#$num > max)); then
        max=$((10#$num))
      fi
    fi
  done < <(find "$USER_STORY_DIR" -maxdepth 1 -type f -name "user-story-$EPIC_ID-$FEATURE_ID-US*.yaml" 2>/dev/null)
  local next=$((max + 1))
  printf 'US%04d' "$next"
}

STORY_ID=$(get_next_story_id)
STORY_FILE="$USER_STORY_DIR/user-story-$EPIC_ID-$FEATURE_ID-$STORY_ID.yaml"

cp "$template_story" "$STORY_FILE"

TIMESTAMP=$(get_chicago_timestamp)
if [ -z "$TIMESTAMP" ]; then
  log_fatal "Failed to capture current timestamp"
fi

python3 - "$STORY_FILE" "$STORY_ID" "$FEATURE_ID" "$EPIC_ID" "$NAME" "$TIMESTAMP" "$PRIORITY" "$FACILITATOR" "$AS_A" "$I_WANT" "$SO_THAT" "$DESCRIPTION" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
story_id, feature_id, epic_id, story_name, date_value, priority, facilitator, as_a, i_want, so_that, description = sys.argv[2:13]
text = path.read_text()

def replace_field(text, key, value):
    if value == "":
        return text
    pattern = re.compile(rf'({key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

def replace_story_section(text, key, value):
    if value == "":
        return text
    pattern = re.compile(rf'(story:\n(?:.*\n)*?\s{{2}}{key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

text = replace_field(text, 'user_story_id', story_id)
text = replace_field(text, 'parent_feature', feature_id)
text = replace_field(text, 'parent_epic', epic_id)
text = replace_field(text, 'user_story_name', story_name)
text = replace_field(text, 'date', date_value)
text = replace_field(text, 'priority', priority)
text = replace_field(text, 'facilitator', facilitator)
text = replace_story_section(text, 'as_a', as_a)
text = replace_story_section(text, 'i_want', i_want)
text = replace_story_section(text, 'so_that', so_that)
text = replace_story_section(text, 'description', description)

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

update_meta "$TIMESTAMP" "story:new"
printf '%s | story:new | Created story %s under %s/%s (%s)\n' "$TIMESTAMP" "$STORY_ID" "$EPIC_ID" "$FEATURE_ID" "$NAME" >> "$LOG_FILE"

log_info "Created user story $STORY_ID under feature $FEATURE_ID (epic $EPIC_ID)"
log_info "Location: $STORY_FILE"

exit 0

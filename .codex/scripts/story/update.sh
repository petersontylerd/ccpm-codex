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
STORY_ID=""
NAME=""
AS_A=""
I_WANT=""
SO_THAT=""
DESCRIPTION=""
PRIORITY=""
FACILITATOR=""
ACCEPTANCE=()

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
    --story)
      shift
      STORY_ID=${1:-}
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
    --acceptance)
      shift
      ACCEPTANCE+=("${1:-}")
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
  shift || true
done

if [ -z "$EPIC_ID" ] || [ -z "$FEATURE_ID" ] || [ -z "$STORY_ID" ]; then
  log_fatal "--epic, --feature, and --story are required"
fi
if [[ ! $EPIC_ID =~ ^E[0-9]{3}$ ]] || [[ ! $FEATURE_ID =~ ^F[0-9]{3}$ ]] || [[ ! $STORY_ID =~ ^US[0-9]{4}$ ]]; then
  log_fatal "IDs must match E### / F### / US#### formats"
fi

STORY_FILE="$PLAN_DIR/epics/epic-$EPIC_ID/features-$EPIC_ID/feature-$EPIC_ID-$FEATURE_ID/user-stories-$EPIC_ID-$FEATURE_ID/user-story-$EPIC_ID-$FEATURE_ID-$STORY_ID.yaml"
if [ ! -f "$STORY_FILE" ]; then
  log_fatal "Story file not found: $STORY_FILE"
fi

if [ -z "$NAME$AS_A$I_WANT$SO_THAT$DESCRIPTION$PRIORITY$FACILITATOR" ] && [ ${#ACCEPTANCE[@]} -eq 0 ]; then
  log_fatal "Provide at least one field to update"
fi

TIMESTAMP=$(get_chicago_timestamp)
[ -n "$TIMESTAMP" ] || log_fatal "Failed to capture timestamp"

python3 - "$STORY_FILE" "$NAME" "$AS_A" "$I_WANT" "$SO_THAT" "$DESCRIPTION" "$PRIORITY" "$FACILITATOR" "${ACCEPTANCE[@]}" <<'PY'
import sys
import re
from pathlib import Path

path = Path(sys.argv[1])
name, as_a, i_want, so_that, description, priority, facilitator, *acceptance = sys.argv[2:]
text = path.read_text()

def replace_field(text, key, value):
    if not value:
        return text
    pattern = re.compile(rf'({key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

def replace_story(text, key, value):
    if not value:
        return text
    pattern = re.compile(rf'(story:\n(?:.*\n)*?\s{{2}}{key}:\s*")[^"]*(".*)', re.MULTILINE)
    return pattern.sub(lambda m: f"{m.group(1)}{value}{m.group(2)}", text, count=1)

text = replace_field(text, 'user_story_name', name)
text = replace_field(text, 'priority', priority)
text = replace_field(text, 'facilitator', facilitator)
text = replace_story(text, 'as_a', as_a)
text = replace_story(text, 'i_want', i_want)
text = replace_story(text, 'so_that', so_that)
text = replace_story(text, 'description', description)

entries = []
for item in acceptance:
    if not item:
        continue
    parts = item.split('|')
    if len(parts) != 4:
        continue
    id_, given, when, then = [p.strip() for p in parts]
    if not id_:
        continue
    entries.append((id_, given, when, then))

if entries:
    lines = ['acceptance_criteria:']
    for id_, given, when, then in entries:
        lines.append(f'  - id: "{id_}"')
        lines.append(f'    given: "{given}"')
        lines.append(f'    when: "{when}"')
        lines.append(f'    then: "{then}"')
    block = '\n'.join(lines) + '\n'
    pattern = re.compile(r'acceptance_criteria:\n(?:.*?)(?=linked_artifacts:)', re.S)
    if pattern.search(text):
        text = pattern.sub(block, text, count=1)
    else:
        text = text.replace('acceptance_criteria:', block.rstrip('\n'))

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

update_meta "$TIMESTAMP" "story:update"
printf '%s | story:update | Updated story %s under %s/%s\n' "$TIMESTAMP" "$STORY_ID" "$EPIC_ID" "$FEATURE_ID" >> "$LOG_FILE"

log_info "Updated story $STORY_ID under feature $FEATURE_ID (epic $EPIC_ID)"

exit 0

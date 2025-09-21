#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"

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

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan missing at $PLAN_DIR"
fi

FEATURE_DIR="$PLAN_DIR/epics/epic-$EPIC_ID/features-$EPIC_ID/feature-$EPIC_ID-$FEATURE_ID"
USER_STORY_DIR="$FEATURE_DIR/user-stories-$EPIC_ID-$FEATURE_ID"
if [ ! -d "$FEATURE_DIR" ]; then
  log_fatal "Feature $FEATURE_ID under epic $EPIC_ID not found."
fi

mkdir -p "$USER_STORY_DIR"

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

cat <<'YAML' > "$STORY_FILE"
# schema_version: 1.0.0
metadata:
  user_story_id: ""
  parent_feature: ""
  parent_epic: ""
  user_story_name: ""
  date: ""
  facilitator: ""
  based_on_artifacts:
    - "brainstorm.yaml"
    - "vision.yaml"
    - "strategy.yaml"
    - "roadmap.yaml"
    - "development-considerations.yaml"
    - "prd.yaml"
    - "personas.yaml"
    - "metrics.yaml"
  schema_version: "1.0.0"

story:
  as_a: ""
  i_want: ""
  so_that: ""
  description: ""

acceptance_criteria:
  - id: ""
    given: ""
    when: ""
    then: ""
  - id: ""
    given: ""
    when: ""
    then: ""

linked_artifacts:
  personas: []
  workflows: []
  linked_prd_frs: []
  linked_strategy_goals: []
  linked_roadmap_horizons: []
  linked_metrics: []

dependencies:
  other_user_stories: []

risks_assumptions:
  - id: ""
    description: ""
    type: ""
    mitigation: ""
    owner: ""

prioritization:
  priority: ""
  rationale: ""

github:
  issue:
  url: ""
  last_synced: ""
  last_status: ""
YAML

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
    pattern = re.compile(rf'(story:\n(?:.*\n)*?\s{2}{key}:\s*")[^"]*(".*)', re.MULTILINE)
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

SUMMARY="Created story $STORY_ID under $EPIC_ID/$FEATURE_ID ($NAME)"
REV_TS=$(plan_record_revision "story:new" "$SUMMARY")

log_info "Created user story $STORY_ID under feature $FEATURE_ID (epic $EPIC_ID)"
log_info "Location: $STORY_FILE"
log_info "Revision recorded at $REV_TS"

exit 0

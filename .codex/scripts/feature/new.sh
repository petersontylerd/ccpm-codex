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

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan missing at $PLAN_DIR"
fi

EPIC_DIR="$PLAN_DIR/epics/epic-$EPIC_ID"
FEATURES_DIR="$EPIC_DIR/features-$EPIC_ID"

if [ ! -d "$EPIC_DIR" ]; then
  log_fatal "Epic $EPIC_ID not found."
fi

mkdir -p "$FEATURES_DIR"

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

FEATURE_FILE="$FEATURE_DIR/feature-$EPIC_ID-$FEATURE_ID.yaml"
cat <<'YAML' > "$FEATURE_FILE"
# schema_version: 1.0.0
metadata:
  feature_id: ""
  parent_epic: ""
  feature_name: ""
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

overview:
  description: ""
  user_value: ""
  in_scope: []
  out_of_scope: []
  personas_served: []
  workflows_addressed: []
  linked_prd_frs: []
  linked_strategy_goals: []
  linked_roadmap_horizons: []
  linked_metrics: []
  dev_considerations_notes: ""

dependencies:
  internal_features: []
  external_dependencies: []

success_criteria:
  - id: ""
    metric: ""
    target: ""
    notes: ""

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

python3 - "$FEATURE_FILE" "$FEATURE_ID" "$EPIC_ID" "$NAME" "$TIMESTAMP" "$PRIORITY" "$FACILITATOR" "$DESCRIPTION" "$USER_VALUE" <<'PY'
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
    pattern = re.compile(rf'({section}:\n(?:.*\n)*?\s{2}{key}:\s*")[^"]*(".*)', re.MULTILINE)
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

SUMMARY="Created feature $FEATURE_ID under $EPIC_ID ($NAME)"
REV_TS=$(plan_record_revision "feature:new" "$SUMMARY")

log_info "Created feature $FEATURE_ID under epic $EPIC_ID"
log_info "Location: $FEATURE_DIR"
log_info "Revision recorded at $REV_TS"

exit 0

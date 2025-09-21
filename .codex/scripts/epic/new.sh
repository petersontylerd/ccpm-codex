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
  log_fatal "Product plan missing at $PLAN_DIR"
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

EPIC_FILE="$NEW_EPIC_DIR/epic-$NEW_EPIC_ID.yaml"
cat <<'YAML' > "$EPIC_FILE"
# schema_version: 1.0.0
metadata:
  epic_id: ""
  epic_name: ""
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
  in_scope: []
  out_of_scope: []
  personas_served: []
  workflows_addressed: []
  linked_strategy_goals: []
  linked_roadmap_horizons: []
  linked_prd_frs: []
  linked_metrics: []
  dev_considerations_notes: ""

dependencies:
  internal_epics: []
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

delivery_phases: []
notes: []
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

python3 - "$EPIC_FILE" "$NEW_EPIC_ID" "$NAME" "$TIMESTAMP" "$PRIORITY" "$FACILITATOR" "$DESCRIPTION" <<'PY'
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

SUMMARY="Created epic $NEW_EPIC_ID ($NAME)"
REV_TS=$(plan_record_revision "epic:new" "$SUMMARY")

log_info "Created epic $NEW_EPIC_ID"
log_info "Location: $NEW_EPIC_DIR"
log_info "Revision recorded at $REV_TS"

exit 0

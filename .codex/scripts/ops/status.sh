#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
PRD_FILE="$PLAN_DIR/foundation/prd.yaml"
META_FILE="$PLAN_DIR/plan-meta.yaml"
LOG_FILE="$PLAN_DIR/revisions.log"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan not found. Run plan:init first."
fi

product_name=$(awk -F'"' '/product_name:/ {print $2; exit}' "$PRD_FILE" 2>/dev/null || echo "")
product_code=$(awk -F'"' '/project_code:/ {print $2; exit}' "$PRD_FILE" 2>/dev/null || echo "")
initialized_at=$(awk -F'"' '/initialized_at:/ {print $2; exit}' "$META_FILE" 2>/dev/null || echo "")
last_updated=$(awk -F'"' '/last_updated:/ {print $2; exit}' "$META_FILE" 2>/dev/null || echo "")
last_command=$(awk -F'"' '/last_command:/ {print $2; exit}' "$META_FILE" 2>/dev/null || echo "")

readarray -t totals < <(python3 - "$PLAN_DIR" <<'PY'
from pathlib import Path
import re
import sys

plan = Path(sys.argv[1])

epics = list(plan.glob('epics/epic-*/epic-*.yaml'))
features = list(plan.glob('epics/epic-*/features-*/feature-*/feature-*.yaml'))
stories = list(plan.glob('epics/epic-*/features-*/feature-*/user-stories-*/user-story-*.yaml'))

epics_missing = 0
for path in epics:
    text = path.read_text()
    if re.search(r'epic_name:\s*"\s*"', text):
        epics_missing += 1

features_missing_desc = 0
for path in features:
    text = path.read_text()
    match = re.search(r'overview:\s*(?:#.*\n)*\s{2}description:\s*"(.*?)"', text)
    if not match or not match.group(1).strip():
        features_missing_desc += 1

stories_missing_ac = 0
for path in stories:
    text = path.read_text()
    ac_block = re.search(r'acceptance_criteria:(.*?)(?:\n\w|\Z)', text, re.S)
    if not ac_block:
        stories_missing_ac += 1
        continue
    entries = re.findall(r'given:\s*"(.*?)"\s*\n\s*when:\s*"(.*?)"\s*\n\s*then:\s*"(.*?)"', ac_block.group(1))
    if not entries or any(not g.strip() or not w.strip() or not t.strip() for g, w, t in entries):
        stories_missing_ac += 1

print(len(epics))
print(len(features))
print(len(stories))
print(epics_missing)
print(features_missing_desc)
print(stories_missing_ac)
PY
)

epic_total=${totals[0]:-0}
feature_total=${totals[1]:-0}
story_total=${totals[2]:-0}
epics_missing=${totals[3]:-0}
features_missing=${totals[4]:-0}
stories_missing=${totals[5]:-0}

latest_revision=""
if [ -f "$LOG_FILE" ]; then
  latest_revision=$(tail -n1 "$LOG_FILE")
fi
recent_revisions=""
if [ -f "$LOG_FILE" ]; then
  recent_revisions=$(tail -n3 "$LOG_FILE")
fi

printf '📊 Operational Status\n'
printf '====================\n'
printf 'Product: %s (code: %s)\n' "${product_name:-unset}" "${product_code:-unset}"
printf 'Initialized: %s\n' "${initialized_at:-unknown}"
printf 'Last update: %s via %s\n' "${last_updated:-unknown}" "${last_command:-unknown}"
printf '\nTotals\n------\n'
printf 'Epics: %s\n' "$epic_total"
printf 'Features: %s\n' "$feature_total"
printf 'User stories: %s\n' "$story_total"
printf '\nData Quality Flags\n------------------\n'
printf 'Epics needing names: %s\n' "$epics_missing"
printf 'Features needing descriptions: %s\n' "$features_missing"
printf 'Stories needing acceptance criteria: %s\n' "$stories_missing"
printf '\nLatest revision\n----------------\n%s\n' "${latest_revision:-none}"
printf '\nLast 3 revisions\n-----------------\n%s\n' "${recent_revisions:-none}"
printf '\nReference\n---------\nRun `plan:status` or `context:prime` for full detail.\n'

exit 0

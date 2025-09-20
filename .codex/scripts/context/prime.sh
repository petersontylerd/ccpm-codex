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
LOG_FILE="$PLAN_DIR/revisions.log"
META_FILE="$PLAN_DIR/plan-meta.yaml"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan not found. Run plan:init first."
fi

product_name=$(awk -F'"' '/product_name:/ {print $2; exit}' "$PRD_FILE" 2>/dev/null || echo "")
product_code=$(awk -F'"' '/project_code:/ {print $2; exit}' "$PRD_FILE" 2>/dev/null || echo "")
plan_summary=$(awk -F'"' '/summary:/ {print $2; exit}' "$PRD_FILE" 2>/dev/null || echo "")

initialized_at=$(awk -F'"' '/initialized_at:/ {print $2; exit}' "$META_FILE" 2>/dev/null || echo "")
last_updated=$(awk -F'"' '/last_updated:/ {print $2; exit}' "$META_FILE" 2>/dev/null || echo "")
last_command=$(awk -F'"' '/last_command:/ {print $2; exit}' "$META_FILE" 2>/dev/null || echo "")

printf '🧠 Codex Context Prime\n'
printf '====================\n'
printf 'Product: %s (code: %s)\n' "${product_name:-unset}" "${product_code:-unset}"
printf 'Summary: %s\n' "${plan_summary:-unset}"
printf 'Plan initialized at: %s\n' "${initialized_at:-unknown}"
printf 'Last updated: %s via %s\n' "${last_updated:-unknown}" "${last_command:-unknown}"

printf '\nStructure Overview\n------------------\n'
plan_status=$(bash "$SCRIPT_DIR/../plan/status.sh" 2>/dev/null || true)
printf '%s\n' "$plan_status"

printf '\nRecent Revisions\n----------------\n'
if [ -f "$LOG_FILE" ]; then
  tail -n5 "$LOG_FILE"
else
  printf '(no revisions recorded)\n'
fi

printf '\nEpics Snapshot\n---------------\n'
if ! find "$PLAN_DIR/epics" -mindepth 1 -maxdepth 1 -type d -name 'epic-*' | grep -q .; then
  printf '(no epics yet)\n'
else
  while IFS= read -r epic_dir; do
    epic_basename=$(basename "$epic_dir")
    epic_file="$epic_dir/${epic_basename}.yaml"
    epic_id=${epic_basename#epic-}
    epic_name=$(awk -F'"' '/epic_name:/ {print $2; exit}' "$epic_file" 2>/dev/null)
    epic_date=$(awk -F'"' '/date:/ {print $2; exit}' "$epic_file" 2>/dev/null)
    epic_priority=$(awk -F'"' '/priority:/ {print $2; exit}' "$epic_file" 2>/dev/null)
    printf '• %s — %s (priority: %s, date: %s)\n' "$epic_id" "${epic_name:-unset}" "${epic_priority:-unset}" "${epic_date:-unset}"
    feature_dir="$epic_dir/features-$epic_id"
    if [ -d "$feature_dir" ]; then
      while IFS= read -r feature_path; do
        feature_base=$(basename "$feature_path")
        feature_file="$feature_path/${feature_base}.yaml"
        feature_id=${feature_base#feature-$epic_id-}
        feature_name=$(awk -F'"' '/feature_name:/ {print $2; exit}' "$feature_file" 2>/dev/null)
        feature_priority=$(awk -F'"' '/priority:/ {print $2; exit}' "$feature_file" 2>/dev/null)
        story_count=$(find "$feature_path" -type f -name 'user-story-*.yaml' 2>/dev/null | wc -l | tr -d ' ')
        printf '    - %s — %s (stories: %s, priority: %s)\n' "$feature_id" "${feature_name:-unset}" "$story_count" "${feature_priority:-unset}"
      done < <(find "$feature_dir" -mindepth 1 -maxdepth 1 -type d -name "feature-$epic_id-*" | sort)
    fi
  done < <(find "$PLAN_DIR/epics" -mindepth 1 -maxdepth 1 -type d -name 'epic-*' | sort)
fi

printf '\nAction Items\n------------\n'
printf '%s\n' '- Update PRD foundation files under .codex/product-plan/foundation.'
printf '%s\n' '- Flesh out success criteria, dependencies, and acceptance tests for new artifacts.'
printf '%s\n' '- Use feature:new and story:new to extend decomposition.'

exit 0

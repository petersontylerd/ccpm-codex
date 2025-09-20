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
PRD_FILE="$PLAN_DIR/foundation/prd.yaml"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan not found. Run plan:init first."
fi

if [ ! -f "$META_FILE" ]; then
  log_warn "plan-meta.yaml missing; re-run plan:init if this is unexpected."
fi

get_meta_field() {
  local key=$1
  if [ -f "$META_FILE" ]; then
    awk -F'"' -v k="$key" '$1 ~ k":" { if (NF >= 2) { print $2 } else { print "" } }' "$META_FILE" | head -n1
  fi
}

initialized_at=$(get_meta_field "initialized_at")
last_updated=$(get_meta_field "last_updated")
last_command=$(get_meta_field "last_command")
revision_count=$(awk -F':' '/revision_count:/ {gsub(/ /,"",$2); print $2; exit}' "$META_FILE" 2>/dev/null || echo "")

if [ -z "$revision_count" ]; then
  revision_count=$(wc -l "$PLAN_DIR/revisions.log" 2>/dev/null | awk '{print $1}')
fi

product_name=""
product_code=""
if [ -f "$PRD_FILE" ]; then
  product_name=$(awk -F'"' '/product_name:/ {print $2; exit}' "$PRD_FILE")
  product_code=$(awk -F'"' '/project_code:/ {print $2; exit}' "$PRD_FILE")
fi

find_count() {
  local path=$1
  local type=$2
  local pattern=$3
  find "$path" -type "$type" -name "$pattern" 2>/dev/null | wc -l | tr -d ' '
}

epic_count=$(find_count "$PLAN_DIR/epics" d 'epic-*')
feature_count=$(find "$PLAN_DIR/epics" -type d -name 'feature-*' 2>/dev/null | wc -l | tr -d ' ')
story_count=$(find "$PLAN_DIR/epics" -type f -name 'user-story-*.yaml' 2>/dev/null | wc -l | tr -d ' ')

printf 'Product Plan Status\n'
printf '====================\n'
printf 'Location: %s\n' "$PLAN_DIR"
printf 'Product: %s (code: %s)\n' "${product_name:-unset}" "${product_code:-unset}"
printf 'Initialized: %s\n' "${initialized_at:-unknown}"
printf 'Last Updated: %s (command: %s)\n' "${last_updated:-unknown}" "${last_command:-unknown}"
printf 'Revisions: %s\n' "${revision_count:-0}"
printf '\nCounts:\n'
printf '  • Epics: %s\n' "$epic_count"
printf '  • Features: %s\n' "$feature_count"
printf '  • User stories: %s\n' "$story_count"

printf '\nEpics Summary:\n'
if [ "$epic_count" -eq 0 ] 2>/dev/null; then
  printf '  (no epics yet)\n'
else
  while IFS= read -r epic_dir; do
    epic_basename=$(basename "$epic_dir")
    epic_file="$epic_dir/${epic_basename}.yaml"
    epic_id=${epic_basename#epic-}
    epic_name=""
    if [ -f "$epic_file" ]; then
      epic_name=$(awk -F'"' '/epic_name:/ {print $2; exit}' "$epic_file")
    fi
    epic_name=${epic_name:-unset}
    feature_total=$(find "$epic_dir" -maxdepth 3 -type d -name 'feature-*' 2>/dev/null | wc -l | tr -d ' ')
    story_total=$(find "$epic_dir" -type f -name 'user-story-*.yaml' 2>/dev/null | wc -l | tr -d ' ')
    printf '  - %s — %s (features: %s, stories: %s)\n' "$epic_id" "$epic_name" "$feature_total" "$story_total"
  done < <(find "$PLAN_DIR/epics" -mindepth 1 -maxdepth 1 -type d -name 'epic-*' | sort)
fi

if [ -f "$PLAN_DIR/revisions.log" ]; then
  last_revision=$(tail -n1 "$PLAN_DIR/revisions.log")
  printf '\nLatest revision: %s\n' "$last_revision"
fi

exit 0

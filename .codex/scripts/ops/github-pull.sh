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

get_repo_slug() {
  local remote
  remote=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
  if [ -z "$remote" ]; then
    printf ''
    return 0
  fi
  python3 - <<'PY' "$remote"
import re
import sys
remote = sys.argv[1]
patterns = [
    r'git@github.com:(?P<owner>[^/]+)/(?P<repo>[^.]+)',
    r'https://github.com/(?P<owner>[^/]+)/(?P<repo>[^/.]+)',
]
for pattern in patterns:
    m = re.match(pattern, remote)
    if m:
        print(f"{m.group('owner')}/{m.group('repo')}")
        break
else:
    print('')
PY
}

REPO_SLUG=$(get_repo_slug)

ISSUE_FILTER=""
EPIC_FILTER=""
TYPE_FILTER=""
NOTE=""
APPLY=0
PREVIEW=1
LOCAL_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      shift
      ISSUE_FILTER=${1:-}
      ;;
    --epic)
      shift
      EPIC_FILTER=${1:-}
      ;;
    --type)
      shift
      TYPE_FILTER=${1:-}
      TYPE_FILTER=${TYPE_FILTER^^}
      ;;
    --note)
      shift
      NOTE=${1:-}
      ;;
    --apply)
      APPLY=1
      PREVIEW=0
      ;;
    --preview)
      PREVIEW=1
      APPLY=0
      ;;
    --local-only)
      LOCAL_ONLY=1
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: /ops:github-pull [--issue N] [--epic E###] [--type EPIC|FEATURE|STORY] [--preview|--apply] [--local-only] [--note "text"]

Pull the latest GitHub issue metadata into the local product plan.
USAGE
      exit 0
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
  shift || true
done

if [ $LOCAL_ONLY -eq 0 ]; then
  require_gh_cli || exit 1
fi
[ -d "$PLAN_DIR" ] || log_fatal "Product plan not found. Run plan:init first."

if [ -n "$EPIC_FILTER" ] && [[ ! $EPIC_FILTER =~ ^E[0-9]{3}$ ]]; then
  log_fatal "--epic must look like E###"
fi
if [ -n "$TYPE_FILTER" ] && [[ ! $TYPE_FILTER =~ ^(EPIC|FEATURE|STORY)$ ]]; then
  log_fatal "--type must be EPIC, FEATURE, or STORY"
fi

if [ $APPLY -eq 1 ] && [ $LOCAL_ONLY -eq 0 ] && [ -z "$REPO_SLUG" ]; then
  log_warn "No origin remote detected; forcing local-only mode."
  LOCAL_ONLY=1
fi

decode_b64() {
  local value=$1
  python3 - <<'PY' "$value"
import base64
import sys
val = sys.argv[1]
if not val:
    print('')
else:
    print(base64.b64decode(val).decode('utf-8'))
PY
}

fetch_issue() {
  local number=$1
  gh issue view "$number" --json number,state,updatedAt,closedAt,title,url >/tmp/codex_issue_pull.json 2>/dev/null || return 1
  python3 - <<'PY' /tmp/codex_issue_pull.json
import json
import sys
path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
state = data.get('state', '')
updated = data.get('updatedAt', '')
closed = data.get('closedAt', '')
url = data.get('url', '')
title = data.get('title', '')
print(f"{state}|{updated}|{closed}|{url}|{title}")
PY
}

ENTRIES=()
while IFS='|' read -r TYPE EID FID SID NAME_B64 DESC_B64 FILE ISSUE URL STATUS LAST_SYNC; do
  [ -n "$ISSUE" ] || continue
  [ -n "$ISSUE_FILTER" ] && [ "$ISSUE" != "$ISSUE_FILTER" ] && continue
  [ -n "$EPIC_FILTER" ] && [ "$EID" != "$EPIC_FILTER" ] && continue
  [ -n "$TYPE_FILTER" ] && [ "$TYPE" != "$TYPE_FILTER" ] && continue
  ENTRIES+=("$TYPE|$EID|$FID|$SID|$ISSUE|$FILE|$STATUS|$LAST_SYNC|$NAME_B64")
done < <(plan_list_artifacts "$PLAN_DIR")

if [ ${#ENTRIES[@]} -eq 0 ]; then
  log_info "No plan artifacts matched the filters."
  exit 0
fi

TIMESTAMP=$(get_chicago_timestamp)

printf 'GitHub Pull (%s mode)\n' "$([ $APPLY -eq 1 ] && echo APPLY || echo PREVIEW)"
printf '%s\n' '----------------------------------------'
printf 'Filters: issue=%s epic=%s type=%s\n' "${ISSUE_FILTER:-*}" "${EPIC_FILTER:-*}" "${TYPE_FILTER:-*}"
printf 'Origin: %s\n' "${REPO_SLUG:-unset}"
printf '%s\n' '----------------------------------------'

UPDATED=0
FAILED=0

for ENTRY in "${ENTRIES[@]}"; do
  IFS='|' read -r TYPE EID FID SID ISSUE FILE STATUS LAST_SYNC NAME_B64 <<<"$ENTRY"
  NAME=$(decode_b64 "$NAME_B64")
  if [ $LOCAL_ONLY -eq 1 ]; then
    STATE_LOWER=${STATUS:-unknown}
    UPDATED_AT=${LAST_SYNC:-unknown}
    URL=${URL:-https://github.com/${REPO_SLUG:-repository}/issues/$ISSUE}
    TITLE=${NAME:-${TYPE} ${EID}}
  else
    REMOTE=$(fetch_issue "$ISSUE") || {
      log_warn "Failed to fetch issue #$ISSUE via gh issue view"
      FAILED=$((FAILED + 1))
      continue
    }
    IFS='|' read -r STATE UPDATED_AT CLOSED_AT URL TITLE <<<"$REMOTE"
    STATE_LOWER=$(echo "$STATE" | tr '[:upper:]' '[:lower:]')
  fi
  printf '[%s] #%s %s\n' "$TYPE" "$ISSUE" "${TITLE:-$NAME}"
  printf '  Local status: %s (last synced: %s)\n' "${STATUS:-unset}" "${LAST_SYNC:-unset}"
  printf '  Remote status: %s (updated: %s)\n' "$STATE_LOWER" "${UPDATED_AT:-unset}"

  if [ $APPLY -eq 1 ]; then
    mkdir -p "$(dirname "$FILE")/updates/issue-$ISSUE"
    plan_update_github_block "$FILE" "$ISSUE" "${URL:-https://github.com/${REPO_SLUG:-repository}/issues/$ISSUE}" "$STATE_LOWER" "$TIMESTAMP"
    LOG_FILE="$(dirname "$FILE")/updates/issue-$ISSUE/log.md"
    mkdir -p "$(dirname "$LOG_FILE")"
    {
      printf '%s\n' '---'
      printf 'timestamp: %s\n' "$TIMESTAMP"
      printf 'status: %s\n' "$STATE_LOWER"
      printf 'event: pull\n'
      if [ -n "${NOTE:-}" ]; then
        printf 'note: "%s"\n' "$NOTE"
      fi
      printf 'remote_updated: "%s"\n' "${UPDATED_AT:-}"
      printf '%s\n\n' '---'
      printf 'Pulled remote status (%s) for issue %s at %s\n' "$STATE_LOWER" "$ISSUE" "$TIMESTAMP"
      if [ -n "${NOTE:-}" ]; then
        printf '\n%s\n' "$NOTE"
      fi
    } >> "$LOG_FILE"
    if [ $LOCAL_ONLY -eq 0 ] && [ -n "${NOTE:-}" ]; then
      gh issue comment "$ISSUE" --body "$NOTE" >/dev/null 2>&1 || log_warn "Failed to add GitHub comment during pull"
    fi
    UPDATED=$((UPDATED + 1))
  fi

  printf '\n'
done

if [ $APPLY -eq 1 ]; then
  plan_record_revision "ops/github-pull" "Pulled metadata for ${UPDATED} issues" >/dev/null
  log_info "GitHub pull complete (updated=$UPDATED failed=$FAILED)."
else
  log_info "Preview complete. Use --apply to update local metadata."
fi

exit 0

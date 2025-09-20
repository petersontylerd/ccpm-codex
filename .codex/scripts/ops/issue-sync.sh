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

read_github_metadata() {
  local file=$1
  python3 - <<'PY' "$file"
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text()
m = re.search(r'github:\n((?:  .+\n)+)', text)
if not m:
    print('||')
else:
    data = {}
    for line in m.group(1).splitlines():
        if ':' not in line:
            continue
        key, value = line.strip().split(':', 1)
        data[key.strip()] = value.strip().strip('"')
    print(f"{data.get('issue','')}|{data.get('url','')}|{data.get('last_status','')}|{data.get('last_synced','')}")
PY
}

REPO_SLUG=$(get_repo_slug)

ISSUE=""
NOTE=""
APPLY=0
PREVIEW=1
LOCAL_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      shift
      ISSUE=${1:-}
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
Usage: /ops:issue-sync --issue <number> [--note "text"] [--preview|--apply] [--local-only]

Options:
  --issue N         GitHub issue number (required)
  --note TEXT       Append a note to the local update log (and GitHub comment if --apply)
  --preview         Default mode; show planned actions
  --apply           Update metadata and post a GitHub comment (unless --local-only)
  --local-only      Update local plan/logs without touching GitHub
USAGE
      exit 0
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
  shift || true
done

if [ -z "$ISSUE" ]; then
  log_fatal "--issue is required"
fi

if [ $APPLY -eq 1 ] && [ $LOCAL_ONLY -eq 0 ]; then
  require_gh_sub_issue || exit 1
fi

RESULT=$(plan_find_artifact_by_issue "$ISSUE")
if [ -z "$RESULT" ]; then
  log_fatal "No artifact in the product plan references issue #$ISSUE"
fi
IFS='|' read -r TYPE EID FID SID FILE NAME <<<"$RESULT"
BASE_DIR=$(dirname "$FILE")
UPDATE_DIR="$BASE_DIR/updates/issue-$ISSUE"
LOG_FILE="$UPDATE_DIR/log.md"
IFS='|' read -r GH_ISSUE GH_URL GH_STATUS GH_LAST_SYNC <<<"$(read_github_metadata "$FILE")"
[ -z "$GH_STATUS" ] && GH_STATUS="in_progress"

TIMESTAMP=$(get_chicago_timestamp)

printf 'Issue Sync (%s mode)\n' "$([ $APPLY -eq 1 ] && echo APPLY || echo PREVIEW)"
printf '%s\n' '----------------------------------------'
printf 'Issue #: %s\n' "$ISSUE"
printf 'Artifact: %s (Epic %s' "$TYPE" "$EID"
if [ -n "$FID" ]; then
  printf ', Feature %s' "$FID"
fi
if [ -n "$SID" ]; then
  printf ', Story %s' "$SID"
fi
printf ')\n'
printf 'Name: %s\n' "${NAME:-unset}"
printf 'Plan file: %s\n' "$FILE"
printf 'Existing status: %s\n' "${GH_STATUS:-unset}"
printf 'Last synced: %s\n' "${GH_LAST_SYNC:-unset}"
printf 'Update log: %s\n' "$LOG_FILE"
if [ -n "$NOTE" ]; then
  printf 'Note: %s\n' "$NOTE"
fi

if [ $APPLY -eq 1 ]; then
  mkdir -p "$UPDATE_DIR"
  if [ -n "$NOTE" ]; then
    {
      printf '%s\n' '---'
      printf 'timestamp: %s\n' "$TIMESTAMP"
      printf 'status: %s\n' "$GH_STATUS"
      printf 'event: sync\n'
      printf 'note: "%s"\n' "$NOTE"
      printf '%s\n\n' '---'
      printf 'Synced progress for issue %s at %s\n' "$ISSUE" "$TIMESTAMP"
      printf '\n%s\n' "$NOTE"
    } >> "$LOG_FILE"
  fi
  plan_update_github_block "$FILE" "$ISSUE" "${GH_URL:-https://github.com/${REPO_SLUG:-repository}/issues/$ISSUE}" "$GH_STATUS" "$TIMESTAMP"
  if [ $LOCAL_ONLY -eq 0 ] && [ -n "$NOTE" ]; then
    gh issue comment "$ISSUE" --body "$NOTE" >/dev/null 2>&1 || log_warn "Failed to post GitHub comment; local updates still applied"
  fi
  plan_record_revision "ops/issue-sync" "Synced issue #$ISSUE ($TYPE ${EID}${FID:+/$FID}${SID:+/$SID})" >/dev/null
  log_info "Issue #$ISSUE synced locally${LOCAL_ONLY:+ (local only)}."
else
  log_info "Preview complete. Use --apply to record sync updates."
fi

exit 0

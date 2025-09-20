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

APPLY=0
TARGET_EPIC=""
TYPE_FILTER=""
PREVIEW=1
DIFF=0
ADD_LABELS=""
REMOVE_LABELS=""
LOCAL_ONLY=0
REPORT_PATH=""
SELECT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      PREVIEW=0
      ;;
    --preview|--dry-run)
      PREVIEW=1
      APPLY=0
      ;;
    --epic)
      shift
      TARGET_EPIC=${1:-}
      ;;
    --type)
      shift
      TYPE_FILTER=${1:-}
      TYPE_FILTER=${TYPE_FILTER^^}
      ;;
    --diff)
      DIFF=1
      ;;
    --add-label)
      shift
      ADD_LABELS="$ADD_LABELS ${1:-}"
      ;;
    --remove-label)
      shift
      REMOVE_LABELS="$REMOVE_LABELS ${1:-}"
      ;;
    --local-only)
      LOCAL_ONLY=1
      ;;
    --report)
      shift
      REPORT_PATH=${1:-}
      ;;
    --select)
      shift
      SELECT_FILE=${1:-}
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: /ops:github-sync [--preview|--apply] [--epic E###] [--type EPIC|FEATURE|STORY] [--diff] [--add-label NAME] [--remove-label NAME] [--local-only] [--report PATH] [--select PATH]

Options:
  --preview (default)   Show planned issue hierarchy without hitting GitHub
  --apply               Create/update GitHub issues and write metadata locally
  --epic E###           Limit sync to a single epic hierarchy
  --type TYPE           Only process a specific artifact type (EPIC|FEATURE|STORY)
  --diff                Compare local metadata with remote issue state (read-only)
  --add-label NAME      Add a label when syncing (can be repeated)
  --remove-label NAME   Remove a label when syncing (can be repeated)
  --local-only          Skip GitHub writes (plan metadata only; new issues skipped)
  --report PATH         Write a JSON summary/report after the run
  --select PATH         Process only the artifact keys listed in PATH (TYPE:EID:FID:SID)
USAGE
      exit 0
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
  shift || true
done

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan not found. Run plan:init first."
fi

if [ $APPLY -eq 1 ]; then
  require_gh_sub_issue || exit 1
fi

trim_line() {
  printf '%s' "$1" | sed 's/[[:space:]]*#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

SELECT_ENABLED=0
declare -A SELECT_KEYS
if [ -n "$SELECT_FILE" ]; then
  if [ ! -f "$SELECT_FILE" ]; then
    log_fatal "Select file not found: $SELECT_FILE"
  fi
  SELECT_ENABLED=1
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line=$(trim_line "$raw_line")
    [ -n "$line" ] || continue
    IFS=':' read -r sel_type sel_eid sel_fid sel_sid <<<"$line"
    sel_type=${sel_type^^}
    sel_eid=${sel_eid:-}
    sel_fid=${sel_fid:-}
    sel_sid=${sel_sid:-}
    key=$(printf '%s:%s:%s:%s' "$sel_type" "$sel_eid" "$sel_fid" "$sel_sid")
    SELECT_KEYS["$key"]=1
  done < "$SELECT_FILE"
  if [ ${#SELECT_KEYS[@]} -eq 0 ]; then
    log_warn "Select file contained no keys; no artifacts will be processed."
  fi
fi

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
if [ -z "$REPO_SLUG" ]; then
  log_warn "No GitHub remote detected. Preview mode only."
  APPLY=0
  PREVIEW=1
fi

if [ "$REPO_SLUG" = "automazeio/ccpm" ]; then
  log_warn "Origin points at the upstream template repository. Refusing to apply."
  APPLY=0
  PREVIEW=1
fi

if [ $PREVIEW -eq 1 ]; then
  log_info "Preview mode: no GitHub changes will be made."
fi

if [ -n "$TYPE_FILTER" ] && [[ ! $TYPE_FILTER =~ ^(EPIC|FEATURE|STORY)$ ]]; then
  log_fatal "--type must be EPIC, FEATURE, or STORY"
fi
if [ -n "$TARGET_EPIC" ] && [[ ! $TARGET_EPIC =~ ^E[0-9]{3}$ ]]; then
  log_fatal "--epic must look like E###"
fi

if [ $LOCAL_ONLY -eq 1 ]; then
  if [ $DIFF -eq 1 ]; then
    log_warn "Diff mode may report skipped results when running --local-only."
  fi
else
  if [ $DIFF -eq 1 ] || [ -n "$ADD_LABELS" ] || [ -n "$REMOVE_LABELS" ]; then
    require_gh_cli || exit 1
  fi
fi

# Associative arrays for parent lookups
declare -A EPIC_ISSUES
declare -A FEATURE_ISSUES
declare -A REMOTE_CACHE

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

encode_b64() {
  python3 - <<'PY' "$1"
import base64
import sys
print(base64.b64encode(sys.argv[1].encode('utf-8')).decode('ascii'))
PY
}

fetch_remote_state() {
  local number=$1
  gh issue view "$number" --json state,updatedAt >/tmp/codex_sync_diff.json 2>/dev/null || return 1
  python3 - <<'PY' /tmp/codex_sync_diff.json
import json
import sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
state = data.get('state', '')
updated = data.get('updatedAt', '')
print(f"{state}|{updated}")
PY
}
DIFF_CHANGES=0
DIFF_MATCH=0
DIFF_ERRORS=0
LOCAL_SKIPPED=0
LOCAL_QUEUE_FILE="$PLAN_DIR/offline-sync-queue.log"
OPERATIONS=()
while IFS='|' read -r TYPE EID FID SID NAME_B64 DESC_B64 FILE ISSUE URL STATUS LAST_SYNC; do
  [ -n "$TARGET_EPIC" ] && [ "$EID" != "$TARGET_EPIC" ] && continue
  NAME=$(decode_b64 "$NAME_B64")
  DESC=$(decode_b64 "$DESC_B64")
  case "$TYPE" in
    EPIC)
      EPIC_ISSUES["$EID"]="$ISSUE"
      ;;
    FEATURE)
      FEATURE_ISSUES["$EID:$FID"]="$ISSUE"
      ;;
  esac
  if [ -n "$TYPE_FILTER" ] && [ "$TYPE" != "$TYPE_FILTER" ]; then
    continue
  fi
  KEY=$(printf '%s:%s:%s:%s' "$TYPE" "$EID" "$FID" "$SID")
  if [ $SELECT_ENABLED -eq 1 ] && [ -z "${SELECT_KEYS[$KEY]+_}" ]; then
    continue
  fi
  OPERATIONS+=("$TYPE|$EID|$FID|$SID|$ISSUE|$NAME|$DESC|$FILE|$STATUS|$URL|$LAST_SYNC|$KEY")
done < <(plan_list_artifacts "$PLAN_DIR")

if [ ${#OPERATIONS[@]} -eq 0 ]; then
  log_info "No artifacts found for synchronization."
  exit 0
fi

if [ $DIFF -eq 1 ] && [ $LOCAL_ONLY -eq 0 ]; then
  require_gh_cli || exit 1
  printf '⏳ Pre-fetching remote issue metadata for diff...'
  unique_issues=()
  declare -A seen
  for entry in "${OPERATIONS[@]}"; do
    issue=$(echo "$entry" | cut -d'|' -f5)
    [ -n "$issue" ] || continue
    if [ -z "${seen[$issue]+_}" ]; then
      unique_issues+=("$issue")
      seen[$issue]=1
    fi
  done
  if [ ${#unique_issues[@]} -gt 0 ]; then
    for issue in "${unique_issues[@]}"; do
      REMOTE_CACHE["$issue"]=$(fetch_remote_state "$issue" || echo '')
    done
  fi
  printf ' done (%s issues).\n' "${#unique_issues[@]}"
fi

printf 'Plan → GitHub Sync (%s mode)\n' "$([ $APPLY -eq 1 ] && echo APPLY || echo PREVIEW)"
printf 'Repository: %s\n' "${REPO_SLUG:-unset}"
printf '%s\n' '------------------------------------------------------------'

CREATED=0
UPDATED=0
FAILED=0
PLANNED_CREATE=0
PLANNED_UPDATE=0
PLANNED_BLOCKED=0
REPORT_ENTRIES=()

for ENTRY in "${OPERATIONS[@]}"; do
  IFS='|' read -r TYPE EID FID SID ISSUE NAME DESC FILE STATUS URL LAST_SYNC KEY <<<"$ENTRY"
  case "$TYPE" in
    EPIC)
      PARENT_LABEL=""
      PARENT_ISSUE=""
      ;;
    FEATURE)
      PARENT_ISSUE="${EPIC_ISSUES[$EID]}"
      ;;
    STORY)
      PARENT_ISSUE="${FEATURE_ISSUES[$EID:$FID]}"
      ;;
  esac
  RESULT="preview"
  ISSUE_OUT="$ISSUE"
  STATUS_OUT="${STATUS:-}"
  URL_OUT="${URL:-}"
  PARENT_OUT="${PARENT_ISSUE:-}"
  NAME_ENC=$(encode_b64 "$NAME")
  ACTION="update"
  if [ -z "$ISSUE" ]; then
    ACTION="create"
  fi
  if [ "$ACTION" = "create" ]; then
    PLANNED_CREATE=$((PLANNED_CREATE + 1))
  else
    PLANNED_UPDATE=$((PLANNED_UPDATE + 1))
  fi
  printf '%-7s %s' "[$TYPE]" "$NAME"
  if [ "$TYPE" != "EPIC" ]; then
    printf ' (Epic %s' "$EID"
    if [ -n "$FID" ]; then
      printf ', Feature %s' "$FID"
    fi
    printf ')'
  fi
  printf '\n'
    if [ "$ACTION" = "create" ]; then
      printf '  → missing GitHub issue. '
      if [ "$TYPE" = "FEATURE" ] || [ "$TYPE" = "STORY" ]; then
        if [ -z "$PARENT_ISSUE" ]; then
          printf '[blocked: parent issue missing]\n'
          FAILED=$((FAILED + 1))
          PLANNED_BLOCKED=$((PLANNED_BLOCKED + 1))
          RESULT="blocked-parent"
          REPORT_ENTRIES+=("$TYPE|$EID|$FID|$SID|$ACTION|$RESULT|$ISSUE_OUT|$STATUS_OUT|$URL_OUT|$PARENT_OUT|$NAME_ENC|$KEY")
          continue
        fi
        printf 'will create sub-issue under #%s\n' "$PARENT_ISSUE"
      else
        printf 'will create top-level issue\n'
    fi
  else
    printf '  → linked to issue #%s (status: %s, last synced: %s)\n' "$ISSUE" "${STATUS:-unset}" "${LAST_SYNC:-unset}"
  fi

  if [ $DIFF -eq 1 ]; then
    if [ -z "$ISSUE" ]; then
      printf '  Δ status: no linked GitHub issue (skipped)\n'
      DIFF_ERRORS=$((DIFF_ERRORS + 1))
      RESULT="diff-missing"
    elif [ $LOCAL_ONLY -eq 1 ]; then
      printf '  Δ status: diff skipped (--local-only)\n'
      DIFF_ERRORS=$((DIFF_ERRORS + 1))
      RESULT="diff-skipped"
    else
      if [ ${REMOTE_CACHE[$ISSUE]+_} ]; then
        REM_DATA=${REMOTE_CACHE[$ISSUE]}
      else
        REM_DATA=$(fetch_remote_state "$ISSUE") || REM_DATA=""
        REMOTE_CACHE["$ISSUE"]="$REM_DATA"
      fi
      if [ -n "$REM_DATA" ]; then
        IFS='|' read -r REM_STATE REM_UPDATED <<<"$REM_DATA"
        REM_STATE_LOWER=$(echo "$REM_STATE" | tr '[:upper:]' '[:lower:]')
        local_diff=0
        if [ "$REM_STATE_LOWER" != "${STATUS:-}" ]; then
          printf '  Δ status: local=%s remote=%s\n' "${STATUS:-unset}" "$REM_STATE_LOWER"
          local_diff=1
        fi
        if [ "$REM_UPDATED" != "${LAST_SYNC:-}" ]; then
          printf '  Δ updated_at: local=%s remote=%s\n' "${LAST_SYNC:-unset}" "${REM_UPDATED:-unset}"
          local_diff=1
        fi
        if [ $local_diff -eq 0 ]; then
          printf '  Δ status: in sync\n'
          DIFF_MATCH=$((DIFF_MATCH + 1))
          RESULT="diff-in-sync"
        else
          DIFF_CHANGES=$((DIFF_CHANGES + 1))
          RESULT="diff-change"
        fi
      else
        printf '  Δ status: unable to fetch remote state\n'
        DIFF_ERRORS=$((DIFF_ERRORS + 1))
        RESULT="diff-error"
      fi
    fi
  fi

  if [ $APPLY -eq 1 ]; then
    TITLE="$NAME"
    LABEL_ARGS=()
    for label in $ADD_LABELS; do
      [ -n "$label" ] && LABEL_ARGS+=("--add-label" "$label")
    done
    for label in $REMOVE_LABELS; do
      [ -n "$label" ] && LABEL_ARGS+=("--remove-label" "$label")
    done
    [ -z "$TITLE" ] && TITLE="$TYPE $EID$([ -n "$FID" ] && echo "-$FID")$([ -n "$SID" ] && echo "-$SID")"
    BODY="Automated Codex sync for $TYPE $EID"
    if [ -n "$DESC" ]; then
      BODY="$BODY\n\n$DESC"
    fi
    if [ "$ACTION" = "create" ]; then
      if [ $LOCAL_ONLY -eq 1 ]; then
        log_warn "Skipping creation of issue for $TYPE $EID${FID:+/$FID}${SID:+/$SID} because --local-only was set."
        LOCAL_SKIPPED=$((LOCAL_SKIPPED + 1))
        {
          printf '%s | type=%s epic=%s feature=%s story=%s | title=%s\n' "$(get_chicago_timestamp)" "$TYPE" "$EID" "$FID" "$SID" "$TITLE"
        } >> "$LOCAL_QUEUE_FILE"
        RESULT="skipped-local"
        REPORT_ENTRIES+=("$TYPE|$EID|$FID|$SID|$ACTION|$RESULT|$ISSUE_OUT|$STATUS_OUT|$URL_OUT|$PARENT_OUT|$NAME_ENC|$KEY")
        continue
      fi
      if [ "$TYPE" = "EPIC" ]; then
        CREATE_CMD=(gh issue create --title "$TITLE" --body "$BODY" --label "epic")
        if [ ${#LABEL_ARGS[@]} -gt 0 ]; then
          CREATE_CMD+=("${LABEL_ARGS[@]}")
        fi
        RESPONSE=$("${CREATE_CMD[@]}" --json number,url 2>&1) || {
          if echo "$RESPONSE" | grep -q "unknown flag: --json"; then
            RESPONSE=$("${CREATE_CMD[@]}" 2>&1) || {
              log_error "Failed to create epic issue: $RESPONSE"
              FAILED=$((FAILED + 1))
              continue
            }
          else
            log_error "Failed to create epic issue: $RESPONSE"
            FAILED=$((FAILED + 1))
            continue
          fi
        }
      else
        RESPONSE=$(gh sub-issue create "$PARENT_ISSUE" --title "$TITLE" --body "$BODY" --json number,url 2>&1) || {
          if echo "$RESPONSE" | grep -q "unknown flag: --json"; then
            RESPONSE=$(gh sub-issue create "$PARENT_ISSUE" --title "$TITLE" --body "$BODY" 2>&1) || {
              log_error "Failed to create sub-issue: $RESPONSE"
              FAILED=$((FAILED + 1))
              continue
            }
          else
            log_error "Failed to create sub-issue: $RESPONSE"
            FAILED=$((FAILED + 1))
            continue
          fi
        }
      fi
      ISSUE=$(python3 - <<'PY' "$RESPONSE"
import json
import sys
try:
    data = json.loads(sys.argv[1])
    print(data.get('number', ''))
    print(data.get('url', ''))
except Exception:
    # Fallback for non-JSON output (gh <2.43)
    text = sys.argv[1].strip()
    num = text.rsplit('/', 1)[-1]
    print(num)
    print(text)
PY
)
      ISSUE_NUM=$(echo "$ISSUE" | sed -n '1p')
      ISSUE_URL=$(echo "$ISSUE" | sed -n '2p')
      ISSUE="$ISSUE_NUM"
      URL="$ISSUE_URL"
      STATUS="open"
      if [ ${#LABEL_ARGS[@]} -gt 0 ]; then
        gh issue edit "$ISSUE" "${LABEL_ARGS[@]}" >/dev/null 2>&1 || true
      fi
      plan_update_github_block "$FILE" "$ISSUE" "$URL" "$STATUS" "$(get_chicago_timestamp)"
      CREATED=$((CREATED + 1))
      RESULT="created"
      ISSUE_OUT="$ISSUE"
      STATUS_OUT="$STATUS"
      URL_OUT="$URL"
      if [ "$TYPE" = "EPIC" ]; then
        EPIC_ISSUES["$EID"]="$ISSUE"
      elif [ "$TYPE" = "FEATURE" ]; then
        FEATURE_ISSUES["$EID:$FID"]="$ISSUE"
      fi
    else
      if [ $LOCAL_ONLY -eq 0 ]; then
        EDIT_CMD=(gh issue edit "$ISSUE" --title "$TITLE")
        if [ ${#LABEL_ARGS[@]} -gt 0 ]; then
          EDIT_CMD+=("${LABEL_ARGS[@]}")
        fi
        "${EDIT_CMD[@]}" >/dev/null 2>&1 || true
        RESULT="updated"
      else
        log_info "Local-only sync: updated plan metadata without calling GitHub for #$ISSUE"
        RESULT="updated-local"
      fi
      plan_update_github_block "$FILE" "$ISSUE" "${URL:-https://github.com/$REPO_SLUG/issues/$ISSUE}" "${STATUS:-in_progress}" "$(get_chicago_timestamp)"
      UPDATED=$((UPDATED + 1))
      ISSUE_OUT="$ISSUE"
      STATUS_OUT="${STATUS:-in_progress}"
      URL_OUT="${URL:-https://github.com/$REPO_SLUG/issues/$ISSUE}"
    fi
  fi
  REPORT_ENTRIES+=("$TYPE|$EID|$FID|$SID|$ACTION|$RESULT|$ISSUE_OUT|$STATUS_OUT|$URL_OUT|$PARENT_OUT|$NAME_ENC|$KEY")
done

if [ $DIFF -eq 1 ]; then
  printf 'Diff summary -> changes: %s, in-sync: %s, skipped: %s\n' "$DIFF_CHANGES" "$DIFF_MATCH" "$DIFF_ERRORS"
fi

TOTAL_ITEMS=${#OPERATIONS[@]}
PLAN_SUMMARY_TEXT="create=$PLANNED_CREATE update=$PLANNED_UPDATE blocked=$PLANNED_BLOCKED total=$TOTAL_ITEMS"
printf '\nPlan summary -> %s\n' "$PLAN_SUMMARY_TEXT"

if [ $APPLY -eq 1 ]; then
  SUMMARY="created=$CREATED updated=$UPDATED failed=$FAILED skipped=$LOCAL_SKIPPED planned_create=$PLANNED_CREATE planned_update=$PLANNED_UPDATE blocked=$PLANNED_BLOCKED"
  plan_record_revision "ops/github-sync" "Synced plan with GitHub ($SUMMARY)" >/dev/null
  if [ $LOCAL_ONLY -eq 0 ]; then
    log_info "Sync complete ($SUMMARY)."
  else
    if [ $LOCAL_SKIPPED -gt 0 ]; then
      log_info "Local-only sync complete ($SUMMARY). Skipped creations queued in $LOCAL_QUEUE_FILE"
    else
      log_info "Local-only sync complete ($SUMMARY)."
    fi
  fi
else
  log_info "Preview complete ($PLAN_SUMMARY_TEXT). Use --apply to execute GitHub updates."
fi

if [ -n "$REPORT_PATH" ]; then
  REPORT_LINES=$(printf '%s\n' "${REPORT_ENTRIES[@]}")
  export REPORT_LINES
  export REPORT_MODE=$([ $APPLY -eq 1 ] && echo apply || echo preview)
  export REPORT_REPO="${REPO_SLUG:-}"
  export REPORT_SUMMARY="$PLAN_SUMMARY_TEXT"
  export REPORT_CREATED=$CREATED
  export REPORT_UPDATED=$UPDATED
  export REPORT_FAILED=$FAILED
  export REPORT_SKIPPED=$LOCAL_SKIPPED
  export REPORT_PLANNED_CREATE=$PLANNED_CREATE
  export REPORT_PLANNED_UPDATE=$PLANNED_UPDATE
  export REPORT_PLANNED_BLOCKED=$PLANNED_BLOCKED
  export REPORT_DIFF_CHANGES=$DIFF_CHANGES
  export REPORT_DIFF_MATCH=$DIFF_MATCH
  export REPORT_DIFF_ERRORS=$DIFF_ERRORS
  export REPORT_SELECT_FILE="${SELECT_FILE:-}"
  python3 - "$REPORT_PATH" <<'PY'
import base64
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = os.environ.get('REPORT_LINES', '').strip().splitlines()
ops = []
for line in lines:
    if not line:
        continue
    fields = line.split('|')
    if len(fields) < 12:
        continue
    type_, eid, fid, sid, planned, result, issue, status, url, parent, name_b64, key = fields
    if name_b64:
        name = base64.b64decode(name_b64.encode()).decode()
    else:
        name = ''
    ops.append({
        'type': type_,
        'epic': eid,
        'feature': fid,
        'story': sid,
        'planned_action': planned,
        'result': result,
        'issue': issue,
        'status': status,
        'url': url,
        'parent_issue': parent,
        'name': name,
        'key': key,
    })

report = {
    'mode': os.environ.get('REPORT_MODE'),
    'repository': os.environ.get('REPORT_REPO') or None,
    'plan_summary': os.environ.get('REPORT_SUMMARY'),
    'counts': {
        'created': int(os.environ.get('REPORT_CREATED', '0')),
        'updated': int(os.environ.get('REPORT_UPDATED', '0')),
        'failed': int(os.environ.get('REPORT_FAILED', '0')),
        'skipped': int(os.environ.get('REPORT_SKIPPED', '0')),
    },
    'planned': {
        'create': int(os.environ.get('REPORT_PLANNED_CREATE', '0')),
        'update': int(os.environ.get('REPORT_PLANNED_UPDATE', '0')),
        'blocked': int(os.environ.get('REPORT_PLANNED_BLOCKED', '0')),
    },
    'diff': {
        'changes': int(os.environ.get('REPORT_DIFF_CHANGES', '0')),
        'in_sync': int(os.environ.get('REPORT_DIFF_MATCH', '0')),
        'skipped': int(os.environ.get('REPORT_DIFF_ERRORS', '0')),
    },
    'operations': ops,
}

select_file = os.environ.get('REPORT_SELECT_FILE')
if select_file:
    report['selected_filter'] = select_file

path.write_text(json.dumps(report, indent=2))
PY
  log_info "Report written to $REPORT_PATH"
fi

exit 0

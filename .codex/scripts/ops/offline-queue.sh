#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
QUEUE_FILE="$PLAN_DIR/offline-sync-queue.log"
GITHUB_SYNC="$SCRIPT_DIR/github-sync.sh"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

CMD="list"
CLEAR=0
LIMIT=""
FORCE=0
PRUNE=0
FILTER_EPIC=""
FILTER_TYPE=""
EXPORT_FILE=""
REPORT_FILE=""

json_from_line() {
  local line="$1"
  python3 - <<'PY' "$line"
import json
import sys
line = sys.argv[1]
if not line.strip():
    print('{}')
    sys.exit(0)
parts = line.split('|')
if len(parts) < 3:
    print('{}')
    sys.exit(0)
ts = parts[0].strip()
meta = parts[1]
title = parts[2].strip()
fields = {}
for chunk in meta.strip().split():
    if '=' in chunk:
        key, value = chunk.split('=', 1)
        fields[key] = value
obj = {
    "timestamp": ts,
    "type": fields.get("type", ""),
    "epic": fields.get("epic", ""),
    "feature": fields.get("feature", ""),
    "story": fields.get("story", ""),
    "title": title
}
print(json.dumps(obj))
PY
}
EXPORT_FILE=""

usage() {
  cat <<'USAGE'
Usage: /ops:offline-queue [--list|--replay|--clear] [--limit N]

Options:
  --list               Show queued offline sync entries (default)
  --replay             Attempt to replay queued creations using ops:github-sync --apply
  --clear              Clear the queue file after confirmation
  --limit N            Show only the first N entries when listing
  --epic E###          Only replay entries for the specified epic
  --type TYPE          Only replay entries of a specific type (EPIC|FEATURE|STORY)
  --force              Replay without interactive confirmation
  --prune              Remove successfully replayed entries from the queue
  --export FILE        Export matching entries to JSON when listing
  --report FILE        Write replay summary (success/failure arrays) to JSON
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      CMD="list"
      ;;
    --replay)
      CMD="replay"
      ;;
    --clear)
      CLEAR=1
      ;;
    --limit)
      shift
      LIMIT=${1:-}
      ;;
    --epic)
      shift
      FILTER_EPIC=${1:-}
      ;;
    --type)
      shift
      FILTER_TYPE=${1:-}
      FILTER_TYPE=${FILTER_TYPE^^}
      ;;
    --force)
      FORCE=1
      ;;
    --prune)
      PRUNE=1
      ;;
    --export)
      shift
      EXPORT_FILE=${1:-}
      ;;
    --report)
      shift
      REPORT_FILE=${1:-}
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
  shift || true
done

[ -d "$PLAN_DIR" ] || log_fatal "Product plan not found. Run plan:init first."
[ -f "$QUEUE_FILE" ] || touch "$QUEUE_FILE"

list_queue() {
  if [ ! -s "$QUEUE_FILE" ]; then
    printf '📭 Offline queue is empty\n'
    if [ -n "$EXPORT_FILE" ]; then
      printf '[]\n' > "$EXPORT_FILE"
      printf '📝 Exported empty array to %s\n' "$EXPORT_FILE"
    fi
    return
  fi

  entries=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    entries+=("$line")
  done < "$QUEUE_FILE"

  filtered=()
  for line in "${entries[@]}"; do
    [[ $line =~ ^# ]] && continue
    if [ -n "$FILTER_EPIC" ] && [[ $line != *"epic=$FILTER_EPIC"* ]]; then
      continue
    fi
    if [ -n "$FILTER_TYPE" ] && [[ $line != *"type=$FILTER_TYPE"* ]]; then
      continue
    fi
    filtered+=("$line")
  done

  if [ ${#filtered[@]} -eq 0 ]; then
    printf 'ℹ️  No queued entries match the provided filters.\n'
    if [ -n "$EXPORT_FILE" ]; then
      printf '[]\n' > "$EXPORT_FILE"
      printf '📝 Exported empty array to %s\n' "$EXPORT_FILE"
    fi
    return
  fi

  if [ -n "$EXPORT_FILE" ]; then
    printf '[' > "$EXPORT_FILE"
    first=1
    for line in "${filtered[@]}"; do
      json=$(json_from_line "$line")
      if [ $first -eq 1 ]; then
        first=0
        printf '\n  %s' "$json" >> "$EXPORT_FILE"
      else
        printf ',\n  %s' "$json" >> "$EXPORT_FILE"
      fi
    done
    printf '\n]\n' >> "$EXPORT_FILE"
    printf '📝 Exported %s entr%s to %s\n' "${#filtered[@]}" "$([ ${#filtered[@]} -eq 1 ] && echo 'y' || echo 'ies')" "$EXPORT_FILE"
  fi

  output=("${filtered[@]}")
  if [ -n "$LIMIT" ]; then
    printf '📄 Showing first %s queued entries:\n' "$LIMIT"
    output=("${output[@]:0:$LIMIT}")
  else
    printf '📄 Offline queue entries:\n'
  fi
  printf '%s\n' "${output[@]}"
}

clear_queue() {
  if [ ! -s "$QUEUE_FILE" ]; then
    printf '📭 Offline queue already empty\n'
    return
  fi
  printf '⚠️  This will remove all entries from %s. Continue? [y/N]: ' "$QUEUE_FILE"
  read -r reply
  case "$reply" in
    y|Y|yes|YES)
      > "$QUEUE_FILE"
      printf '✅ Cleared offline queue.\n'
      ;;
    *)
      printf 'ℹ️  Leaving queue untouched.\n'
      ;;
  esac
}

replay_queue() {
  if [ ! -s "$QUEUE_FILE" ]; then
    printf '📭 Offline queue is empty; nothing to replay.\n'
    return
  fi
  if [ -n "$FILTER_TYPE" ] && [[ ! $FILTER_TYPE =~ ^(EPIC|FEATURE|STORY)$ ]]; then
    log_fatal "--type must be EPIC, FEATURE, or STORY"
  fi
  if [ -n "$FILTER_EPIC" ] && [[ ! $FILTER_EPIC =~ ^E[0-9]{3}$ ]]; then
    log_fatal "--epic must look like E###"
  fi
  require_gh_sub_issue || return

  tmp=$(mktemp)
  cp "$QUEUE_FILE" "$tmp"
  mapfile -t original_lines < "$tmp"

  total=0
  for line in "${original_lines[@]}"; do
    [[ $line =~ ^# ]] && continue
    [ -n "$line" ] || continue
    if [ -n "$FILTER_EPIC" ] && [[ $line != *"epic=$FILTER_EPIC"* ]]; then
      continue
    fi
    if [ -n "$FILTER_TYPE" ] && [[ $line != *"type=$FILTER_TYPE"* ]]; then
      continue
    fi
    total=$((total + 1))
  done

  if [ "$total" -eq 0 ]; then
    printf 'ℹ️  No queued entries match the provided filters.\n'
    rm -f "$tmp"
    return
  fi

  if [ $FORCE -ne 1 ]; then
    printf '🚀 Replay %s queued entr%s? [y/N]: ' "$total" "$([ "$total" -eq 1 ] && echo 'y' || echo 'ies')"
    read -r reply
    case "$reply" in
      y|Y|yes|YES) : ;;
      *)
        printf 'ℹ️  Replay cancelled.\n'
        rm -f "$tmp"
        return
        ;;
    esac
  else
    printf '🚀 Replaying %s queued entries (%s)...\n' "$total" "$QUEUE_FILE"
  fi

  successes=0
  failures=0
  kept_lines=()
  success_lines=()

  while IFS= read -r line; do
    [[ $line =~ ^# ]] && { kept_lines+=("$line"); continue; }
    [ -n "$line" ] || { kept_lines+=("$line"); continue; }

    timestamp_raw=${line%%|*}
    rest=${line#*|}
    meta_raw=${rest%%|*}
    title_raw=${rest#*|}
    meta=$(echo "$meta_raw" | xargs)
    type=$(echo "$meta" | awk '{for(i=1;i<=NF;i++){if($i~"type=") {split($i,a,"=");print a[2]}}}')
    epic=$(echo "$meta" | awk '{for(i=1;i<=NF;i++){if($i~"epic=") {split($i,a,"=");print a[2]}}}')
    feature=$(echo "$meta" | awk '{for(i=1;i<=NF;i++){if($i~"feature=") {split($i,a,"=");print a[2]}}}')

    if [ -n "$FILTER_TYPE" ] && [ "$type" != "$FILTER_TYPE" ]; then
      kept_lines+=("$line")
      continue
    fi
    if [ -n "$FILTER_EPIC" ] && [ "$epic" != "$FILTER_EPIC" ]; then
      kept_lines+=("$line")
      continue
    fi
    if [ -z "$type" ] || [ -z "$epic" ]; then
      printf '⚠️  Missing type or epic in entry: %s\n' "$meta"
      kept_lines+=("$line")
      failures=$((failures + 1))
      continue
    fi

    printf '→ Replaying %s %s%s%s\n' "$type" "$epic" "${feature:+/}" "${feature}"
    OUTPUT=$(bash "$GITHUB_SYNC" --apply --epic "$epic" --type "$type" 2>&1)
    status=$?
    printf '%s\n' "$OUTPUT"

    if [ $status -eq 0 ] && echo "$OUTPUT" | grep -q 'Sync complete' && ! echo "$OUTPUT" | grep -q 'failed=[1-9]'; then
      successes=$((successes + 1))
      success_lines+=("$line")
      if [ $PRUNE -eq 0 ]; then
        kept_lines+=("$line")
      fi
    else
      failures=$((failures + 1))
      kept_lines+=("$line")
    fi
  done < "$tmp"

  rm -f "$tmp"

  if [ $PRUNE -eq 1 ]; then
    printf '🧹 Pruning successfully replayed entries...\n'
    printf '' > "$QUEUE_FILE"
    for line in "${kept_lines[@]}"; do
      printf '%s\n' "$line" >> "$QUEUE_FILE"
    done
  elif [ ${#success_lines[@]} -gt 0 ] && [ $FORCE -ne 1 ]; then
    printf '🧹 Remove %s successful entr%s from queue? [y/N]: ' "${#success_lines[@]}" "$([ ${#success_lines[@]} -eq 1 ] && echo 'y' || echo 'ies')"
    read -r prune_reply
    if [[ $prune_reply =~ ^(y|Y|yes|YES)$ ]]; then
      printf '' > "$QUEUE_FILE"
      for line in "${original_lines[@]}"; do
        skip=0
        for done_line in "${success_lines[@]}"; do
          if [ "$line" = "$done_line" ]; then
            skip=1
            break
          fi
        done
        [ $skip -eq 1 ] && continue
        printf '%s\n' "$line" >> "$QUEUE_FILE"
      done
    else
      printf 'ℹ️  Leaving queue entries untouched.\n'
    fi
  fi

  printf '# %s replay summary: success=%s failed=%s filters=type:%s epic:%s prune=%s\n' "$(get_chicago_timestamp)" "$successes" "$failures" "${FILTER_TYPE:-*}" "${FILTER_EPIC:-*}" "$PRUNE" >> "$QUEUE_FILE"
  printf '✅ Replay summary: %s success, %s failed/residual.\n' "$successes" "$failures"

  if [ -n "$REPORT_FILE" ]; then
    {
      printf '{\n  "success": ['
      first=1
      for line in "${success_lines[@]}"; do
        json=$(json_from_line "$line")
        if [ $first -eq 1 ]; then
          first=0
          printf '\n    %s' "$json"
        else
          printf ',\n    %s' "$json"
        fi
      done
      if [ $first -eq 1 ]; then
        printf '\n  ],\n  "failed": ['
      else
        printf '\n  ],\n  "failed": ['
      fi
      first=1
      for line in "${kept_lines[@]}"; do
        # kept_lines includes successes when PRUNE=0; avoid duplicating success in failed list
        skip=0
        for sline in "${success_lines[@]}"; do
          if [ "$line" = "$sline" ]; then
            skip=1
            break
          fi
        done
        if [ $skip -eq 1 ]; then
          continue
        fi
        [[ $line =~ ^# ]] && continue
        json=$(json_from_line "$line")
        if [ $first -eq 1 ]; then
          first=0
          printf '\n    %s' "$json"
        else
          printf ',\n    %s' "$json"
        fi
      done
      if [ $first -eq 1 ]; then
        printf '\n  ],\n  "summary": {"success": %s, "failed": %s, "filters": {"type": "%s", "epic": "%s"}, "prune": %s}\n}' "$successes" "$failures" "${FILTER_TYPE:-*}" "${FILTER_EPIC:-*}" "$PRUNE"
      else
        printf '\n  ],\n  "summary": {"success": %s, "failed": %s, "filters": {"type": "%s", "epic": "%s"}, "prune": %s}\n}' "$successes" "$failures" "${FILTER_TYPE:-*}" "${FILTER_EPIC:-*}" "$PRUNE"
      fi
    } > "$REPORT_FILE"
    printf '📝 Replay report written to %s\n' "$REPORT_FILE"
  fi
}

case "$CMD" in
  list)
    list_queue
    ;;
  replay)
    replay_queue
    ;;
  *)
    list_queue
    ;;
esac

if [ $CLEAR -eq 1 ]; then
  clear_queue
fi

exit 0

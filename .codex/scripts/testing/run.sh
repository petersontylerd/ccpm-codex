#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

LOG_DIR="$REPO_ROOT/tests/logs"
LOG_NAME=""
NO_LOG=0
CMD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-name)
      shift
      LOG_NAME=${1:-}
      ;;
    --no-log)
      NO_LOG=1
      ;;
    --)
      shift
      CMD_ARGS=("$@")
      break
      ;;
    *)
      CMD_ARGS+=("$1")
      ;;
  esac
  shift || true
done

if [ ${#CMD_ARGS[@]} -eq 0 ]; then
  log_fatal "No test command provided. Use: testing:run -- <command> [args]"
fi

if [ $NO_LOG -eq 0 ]; then
  mkdir -p "$LOG_DIR"
  if [ -z "$LOG_NAME" ]; then
    base=${CMD_ARGS[0]//[^A-Za-z0-9_-]/_}
    LOG_NAME="${base:-tests}_$(date +%Y%m%d_%H%M%S).log"
  fi
  [[ $LOG_NAME != *.log ]] && LOG_NAME="${LOG_NAME}.log"
  LOG_FILE="$LOG_DIR/$LOG_NAME"
else
  LOG_FILE=""
fi

START_TS=$(get_chicago_timestamp)
log_info "Running tests at $START_TS"
log_info "Command: ${CMD_ARGS[*]}"
if [ $NO_LOG -eq 0 ]; then
  log_info "Log file: $LOG_FILE"
fi

set +e
if [ $NO_LOG -eq 0 ]; then
  "${CMD_ARGS[@]}" 2>&1 | tee "$LOG_FILE"
  CMD_EXIT=${PIPESTATUS[0]}
else
  "${CMD_ARGS[@]}"
  CMD_EXIT=$?
fi
set -e

END_TS=$(get_chicago_timestamp)
if [ $CMD_EXIT -eq 0 ]; then
  log_info "✅ Tests passed (started $START_TS, finished $END_TS)"
else
  log_error "❌ Tests failed with exit code $CMD_EXIT (started $START_TS, finished $END_TS)"
  if [ $NO_LOG -eq 0 ]; then
    log_info "Review $LOG_FILE for details."
  fi
fi

exit $CMD_EXIT

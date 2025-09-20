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

RUNNER="$SCRIPT_DIR/run.sh"
if [ ! -x "$RUNNER" ]; then
  log_fatal "testing:run helper not found at $RUNNER"
fi

LOG_NAME=""
NOTE=""
NO_LOG=0
CMD_ARGS=()

usage() {
  cat <<'USAGE'
Usage: /testing:red [options] -- <test command>

Runs the provided test command expecting a failure (red phase). Output and logs
are handled by testing:run. If the command passes, this helper fails.

Options:
  --log-name FILE.log   Override the log filename used by testing:run
  --no-log              Forward to testing:run to skip log file creation
  --note TEXT           Store an additional note in tdd-history.log
  -h, --help            Show this message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-name)
      shift
      LOG_NAME=${1:-}
      ;;
    --note)
      shift
      NOTE=${1:-}
      ;;
    --no-log)
      NO_LOG=1
      ;;
    -h|--help)
      usage
      exit 0
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
  log_fatal "No test command provided. Usage: testing:red -- <command> [args]"
fi

RUN_COMMAND=("$RUNNER")
if [ -n "$LOG_NAME" ]; then
  RUN_COMMAND+=("--log-name" "$LOG_NAME")
fi
if [ $NO_LOG -eq 1 ]; then
  RUN_COMMAND+=("--no-log")
fi
RUN_COMMAND+=("--")
RUN_COMMAND+=("${CMD_ARGS[@]}")

set +e
"${RUN_COMMAND[@]}"
RUN_EXIT=$?
set -e

CMD_STRING="${CMD_ARGS[*]}"
TDD_LOG="$REPO_ROOT/tests/logs/tdd-history.log"
mkdir -p "$(dirname "$TDD_LOG")"
TIMESTAMP=$(get_chicago_timestamp)
STATUS="expected-fail"
RETURN_CODE=$RUN_EXIT

if [ $RUN_EXIT -eq 0 ]; then
  STATUS="unexpected-pass"
  printf '%s | phase=red | status=%s | exit=%s | command=%s | note=%s\n' \
    "$TIMESTAMP" "$STATUS" "$RETURN_CODE" "$CMD_STRING" "${NOTE:-}" >> "$TDD_LOG"
  log_error "Red phase requires a failing test, but the command passed."
  exit 1
fi

printf '%s | phase=red | status=%s | exit=%s | command=%s | note=%s\n' \
  "$TIMESTAMP" "$STATUS" "$RETURN_CODE" "$CMD_STRING" "${NOTE:-}" >> "$TDD_LOG"
log_info "Red phase confirmed: tests failed as expected (exit $RUN_EXIT)."
log_info "Journal entry appended to $TDD_LOG"
exit 0

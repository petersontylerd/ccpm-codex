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
CMD_ARGS=()
NO_LOG=0

usage() {
  cat <<'USAGE'
Usage: /testing:refactor [options] -- <test command>

Runs the provided test command expecting success (green/refactor phase). Output
and logs are handled by testing:run. On failure this helper exits non-zero.

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
    --no-log)
      NO_LOG=1
      ;;
    --note)
      shift
      NOTE=${1:-}
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
  log_fatal "No test command provided. Usage: testing:refactor -- <command> [args]"
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
STATUS="green"
RETURN_CODE=$RUN_EXIT

if [ $RUN_EXIT -ne 0 ]; then
  STATUS="failed"
  printf '%s | phase=refactor | status=%s | exit=%s | command=%s | note=%s\n' \
    "$TIMESTAMP" "$STATUS" "$RETURN_CODE" "$CMD_STRING" "${NOTE:-}" >> "$TDD_LOG"
  log_error "Refactor phase expected tests to pass, but exit code was $RUN_EXIT."
  log_info "Journal entry appended to $TDD_LOG"
  exit $RUN_EXIT
fi

printf '%s | phase=refactor | status=%s | exit=%s | command=%s | note=%s\n' \
  "$TIMESTAMP" "$STATUS" "$RETURN_CODE" "$CMD_STRING" "${NOTE:-}" >> "$TDD_LOG"
log_info "Refactor phase confirmed: tests passed (exit 0)."
log_info "Journal entry appended to $TDD_LOG"
exit 0

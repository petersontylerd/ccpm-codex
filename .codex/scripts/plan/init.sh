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

log_info "Validating Codex product plan"

require_gh_sub_issue || exit 1

if [ ! -d "$PLAN_DIR" ]; then
  log_fatal "Product plan missing at $PLAN_DIR. Create it (or sync from source control) before running plan:init."
fi

mkdir -p "$PLAN_DIR"

SUMMARY="plan verified"
TIMESTAMP=$(plan_record_revision "plan:init" "$SUMMARY")
log_info "Product plan ready at $PLAN_DIR"
log_info "Revision recorded at $TIMESTAMP"

exit 0

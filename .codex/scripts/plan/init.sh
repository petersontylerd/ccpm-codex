#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_TEMPLATE_DIR="$REPO_ROOT/.codex/product-plan.template"
PLAN_DIR="$REPO_ROOT/.codex/product-plan"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

log_info "Initializing Codex product plan"

require_gh_sub_issue || exit 1

if [ ! -d "$PLAN_TEMPLATE_DIR" ]; then
  log_fatal "Template directory not found at $PLAN_TEMPLATE_DIR"
fi

if [ -d "$PLAN_DIR" ]; then
  log_error "Product plan already exists at $PLAN_DIR"
  log_info "Remove it manually if you intend to reinitialize."
  exit 1
fi

log_info "Copying template structure"
cp -R "$PLAN_TEMPLATE_DIR" "$PLAN_DIR"

TIMESTAMP=$(get_chicago_timestamp)
if [ -z "$TIMESTAMP" ]; then
  log_fatal "Failed to capture current timestamp"
fi

META_FILE="$PLAN_DIR/plan-meta.yaml"
LOG_FILE="$PLAN_DIR/revisions.log"

cat > "$META_FILE" <<EOF_META
initialized_at: "$TIMESTAMP"
initialized_by: "plan:init"
last_updated: "$TIMESTAMP"
last_command: "plan:init"
revision_count: 1
EOF_META

cat > "$LOG_FILE" <<EOF_LOG
$TIMESTAMP | plan:init | Initialized product plan from template
EOF_LOG

log_info "Product plan created at $PLAN_DIR"
log_info "Revision metadata recorded in plan-meta.yaml"

exit 0

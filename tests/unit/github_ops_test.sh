#!/bin/bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

PLAN_DIR="$ROOT/.codex/product-plan"
QUEUE_FILE="$PLAN_DIR/offline-sync-queue.log"

if [ ! -d "$PLAN_DIR" ]; then
  echo "Product plan not found. Run plan:init first." >&2
  exit 1
fi

BACKUP_DIR=$(mktemp -d)
REPORT_PATH=$(mktemp)
SELECT_FILE=$(mktemp)
cleanup() {
  rsync -a --delete "$BACKUP_DIR/" "$PLAN_DIR/"
  rm -rf "$BACKUP_DIR"
  rm -f "$REPORT_PATH" "$SELECT_FILE"
}
trap cleanup EXIT
rsync -a "$PLAN_DIR/" "$BACKUP_DIR/"

printf 'EPIC:E001::\n' > "$SELECT_FILE"

SYNC_OUTPUT=$(bash .codex/scripts/ops/github-sync.sh --preview --type EPIC --local-only --select "$SELECT_FILE" --report "$REPORT_PATH")
echo "$SYNC_OUTPUT" | grep -q 'Plan summary ->' || {
  echo "github-sync preview did not emit plan summary" >&2
  exit 1
}

python3 - "$REPORT_PATH" "$SELECT_FILE" <<'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
select_path = sys.argv[2]
data = json.loads(report_path.read_text())
if not data.get('operations'):
    raise SystemExit('Report missing operations')
if data.get('selected_filter') != select_path:
    raise SystemExit('Report missing selected_filter')
if any(op.get('type') != 'EPIC' for op in data['operations']):
    raise SystemExit('Report contains non-EPIC entries')
if 'plan_summary' not in data:
    raise SystemExit('Report missing plan summary')
PY

printf '2025-01-01 00:00:00 CT | type=EPIC epic=E999 feature=F999 story= | title=Dummy epic\n' > "$QUEUE_FILE"
EXPORT_PATH=$(mktemp)
LIST_OUTPUT=$(bash .codex/scripts/ops/offline-queue.sh --list --limit 1)
echo "$LIST_OUTPUT" | grep -q 'Dummy epic' || {
  echo "offline-queue list did not include dummy entry" >&2
  exit 1
}

bash .codex/scripts/ops/offline-queue.sh --list --export "$EXPORT_PATH" >/dev/null
python3 - "$EXPORT_PATH" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
if not data or data[0].get('title') != 'title=Dummy epic':
    raise SystemExit('Export JSON missing dummy entry')
PY

rm -f "$EXPORT_PATH"

printf 'GitHub ops unit checks passed.\n'

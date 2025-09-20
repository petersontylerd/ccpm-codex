#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
PRD_FILE="$PLAN_DIR/foundation/prd.yaml"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

usage() {
  cat <<'USAGE'
Usage: /plan:prd-update [options]

Update metadata and overview fields in .codex/product-plan/foundation/prd.yaml.
All writes stamp a Chicago timestamp and append to revisions.log.

Scalar fields:
  --project-code VALUE
  --product-name VALUE
  --date VALUE
  --facilitator VALUE
  --summary VALUE

List fields (append values). Use --reset-* to clear before adding new entries:
  --goal VALUE             (overview.goals)
  --non-goal VALUE         (overview.non_goals)
  --success-metric VALUE   (overview.success_metrics)
  --assumption VALUE       (overview.assumptions)
  --out-of-scope VALUE     (overview.out_of_scope)

Reset flags:
  --reset-goals
  --reset-non-goals
  --reset-success-metrics
  --reset-assumptions
  --reset-out-of-scope

Other:
  --note TEXT              Optional note stored in the revision log message
  -h, --help               Show this help message
USAGE
}

[ -d "$PLAN_DIR" ] || log_fatal "Product plan not found. Run plan:init first."
[ -f "$PRD_FILE" ] || log_fatal "PRD file missing at $PRD_FILE"

PROJECT_CODE_SET=0
PRODUCT_NAME_SET=0
DATE_SET=0
FACILITATOR_SET=0
SUMMARY_SET=0
NOTE=""

RESET_GOALS=0
RESET_NON_GOALS=0
RESET_SUCCESS=0
RESET_ASSUMPTIONS=0
RESET_OUT=0

GOALS=()
NON_GOALS=()
SUCCESS_METRICS=()
ASSUMPTIONS=()
OUT_OF_SCOPE=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-code)
      PROJECT_CODE_SET=1
      shift
      PROJECT_CODE=${1:-}
      ;;
    --product-name)
      PRODUCT_NAME_SET=1
      shift
      PRODUCT_NAME=${1:-}
      ;;
    --date)
      DATE_SET=1
      shift
      DATE_VALUE=${1:-}
      ;;
    --facilitator)
      FACILITATOR_SET=1
      shift
      FACILITATOR=${1:-}
      ;;
    --summary)
      SUMMARY_SET=1
      shift
      SUMMARY=${1:-}
      ;;
    --goal)
      shift
      GOALS+=("${1:-}")
      ;;
    --non-goal)
      shift
      NON_GOALS+=("${1:-}")
      ;;
    --success-metric)
      shift
      SUCCESS_METRICS+=("${1:-}")
      ;;
    --assumption)
      shift
      ASSUMPTIONS+=("${1:-}")
      ;;
    --out-of-scope)
      shift
      OUT_OF_SCOPE+=("${1:-}")
      ;;
    --reset-goals)
      RESET_GOALS=1
      ;;
    --reset-non-goals)
      RESET_NON_GOALS=1
      ;;
    --reset-success-metrics)
      RESET_SUCCESS=1
      ;;
    --reset-assumptions)
      RESET_ASSUMPTIONS=1
      ;;
    --reset-out-of-scope)
      RESET_OUT=1
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
      shift || true
      break
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
  shift || true
done

MOD_COUNT=0
if [ $PROJECT_CODE_SET -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ $PRODUCT_NAME_SET -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ $DATE_SET -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ $FACILITATOR_SET -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ $SUMMARY_SET -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ ${#GOALS[@]} -gt 0 ] || [ $RESET_GOALS -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ ${#NON_GOALS[@]} -gt 0 ] || [ $RESET_NON_GOALS -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ ${#SUCCESS_METRICS[@]} -gt 0 ] || [ $RESET_SUCCESS -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ ${#ASSUMPTIONS[@]} -gt 0 ] || [ $RESET_ASSUMPTIONS -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi
if [ ${#OUT_OF_SCOPE[@]} -gt 0 ] || [ $RESET_OUT -eq 1 ]; then
  MOD_COUNT=$((MOD_COUNT + 1))
fi

if [ $MOD_COUNT -eq 0 ]; then
  log_fatal "No updates provided. Pass at least one field to modify."
fi

if command -v python3 >/dev/null 2>&1; then
  :
else
  log_fatal "python3 is required to update YAML."
fi

export CODEX_PRD_FILE="$PRD_FILE"
export CODEX_PRD_NOTE="$NOTE"

if [ $PROJECT_CODE_SET -eq 1 ]; then
  export CODEX_PRD_PROJECT_CODE_SET=1
  export CODEX_PRD_PROJECT_CODE="$PROJECT_CODE"
fi
if [ $PRODUCT_NAME_SET -eq 1 ]; then
  export CODEX_PRD_PRODUCT_NAME_SET=1
  export CODEX_PRD_PRODUCT_NAME="$PRODUCT_NAME"
fi
if [ $DATE_SET -eq 1 ]; then
  export CODEX_PRD_DATE_SET=1
  export CODEX_PRD_DATE_VALUE="$DATE_VALUE"
fi
if [ $FACILITATOR_SET -eq 1 ]; then
  export CODEX_PRD_FACILITATOR_SET=1
  export CODEX_PRD_FACILITATOR="$FACILITATOR"
fi
if [ $SUMMARY_SET -eq 1 ]; then
  export CODEX_PRD_SUMMARY_SET=1
  export CODEX_PRD_SUMMARY="$SUMMARY"
fi

if [ ${#GOALS[@]} -gt 0 ]; then
  export CODEX_PRD_GOALS_VALUES="$(printf '%s
' "${GOALS[@]}")"
fi
if [ $RESET_GOALS -eq 1 ]; then
  export CODEX_PRD_GOALS_RESET=1
fi

if [ ${#NON_GOALS[@]} -gt 0 ]; then
  export CODEX_PRD_NON_GOALS_VALUES="$(printf '%s
' "${NON_GOALS[@]}")"
fi
if [ $RESET_NON_GOALS -eq 1 ]; then
  export CODEX_PRD_NON_GOALS_RESET=1
fi

if [ ${#SUCCESS_METRICS[@]} -gt 0 ]; then
  export CODEX_PRD_SUCCESS_VALUES="$(printf '%s
' "${SUCCESS_METRICS[@]}")"
fi
if [ $RESET_SUCCESS -eq 1 ]; then
  export CODEX_PRD_SUCCESS_RESET=1
fi

if [ ${#ASSUMPTIONS[@]} -gt 0 ]; then
  export CODEX_PRD_ASSUMPTION_VALUES="$(printf '%s
' "${ASSUMPTIONS[@]}")"
fi
if [ $RESET_ASSUMPTIONS -eq 1 ]; then
  export CODEX_PRD_ASSUMPTIONS_RESET=1
fi

if [ ${#OUT_OF_SCOPE[@]} -gt 0 ]; then
  export CODEX_PRD_OUT_VALUES="$(printf '%s
' "${OUT_OF_SCOPE[@]}")"
fi
if [ $RESET_OUT -eq 1 ]; then
  export CODEX_PRD_OUT_RESET=1
fi

python3 - "$PRD_FILE" <<'PY'
import os
import sys
from pathlib import Path

FILE_PATH = Path(sys.argv[1])
lines = FILE_PATH.read_text().splitlines()

scalars = []
if os.environ.get("CODEX_PRD_PROJECT_CODE_SET") == "1":
    scalars.append((("metadata", "project_code"), os.environ.get("CODEX_PRD_PROJECT_CODE", "")))
if os.environ.get("CODEX_PRD_PRODUCT_NAME_SET") == "1":
    scalars.append((("metadata", "product_name"), os.environ.get("CODEX_PRD_PRODUCT_NAME", "")))
if os.environ.get("CODEX_PRD_DATE_SET") == "1":
    scalars.append((("metadata", "date"), os.environ.get("CODEX_PRD_DATE_VALUE", "")))
if os.environ.get("CODEX_PRD_FACILITATOR_SET") == "1":
    scalars.append((("metadata", "facilitator"), os.environ.get("CODEX_PRD_FACILITATOR", "")))
if os.environ.get("CODEX_PRD_SUMMARY_SET") == "1":
    scalars.append((("overview", "summary"), os.environ.get("CODEX_PRD_SUMMARY", "")))

list_mods = {}
if os.environ.get("CODEX_PRD_GOALS_RESET") == "1" or os.environ.get("CODEX_PRD_GOALS_VALUES"):
    values = [v for v in os.environ.get("CODEX_PRD_GOALS_VALUES", "").splitlines() if v != ""]
    list_mods[("overview", "goals")] = {"reset": os.environ.get("CODEX_PRD_GOALS_RESET") == "1", "items": values}
if os.environ.get("CODEX_PRD_NON_GOALS_RESET") == "1" or os.environ.get("CODEX_PRD_NON_GOALS_VALUES"):
    values = [v for v in os.environ.get("CODEX_PRD_NON_GOALS_VALUES", "").splitlines() if v != ""]
    list_mods[("overview", "non_goals")] = {"reset": os.environ.get("CODEX_PRD_NON_GOALS_RESET") == "1", "items": values}
if os.environ.get("CODEX_PRD_SUCCESS_RESET") == "1" or os.environ.get("CODEX_PRD_SUCCESS_VALUES"):
    values = [v for v in os.environ.get("CODEX_PRD_SUCCESS_VALUES", "").splitlines() if v != ""]
    list_mods[("overview", "success_metrics")] = {"reset": os.environ.get("CODEX_PRD_SUCCESS_RESET") == "1", "items": values}
if os.environ.get("CODEX_PRD_ASSUMPTIONS_RESET") == "1" or os.environ.get("CODEX_PRD_ASSUMPTION_VALUES"):
    values = [v for v in os.environ.get("CODEX_PRD_ASSUMPTION_VALUES", "").splitlines() if v != ""]
    list_mods[("overview", "assumptions")] = {"reset": os.environ.get("CODEX_PRD_ASSUMPTIONS_RESET") == "1", "items": values}
if os.environ.get("CODEX_PRD_OUT_RESET") == "1" or os.environ.get("CODEX_PRD_OUT_VALUES"):
    values = [v for v in os.environ.get("CODEX_PRD_OUT_VALUES", "").splitlines() if v != ""]
    list_mods[("overview", "out_of_scope")] = {"reset": os.environ.get("CODEX_PRD_OUT_RESET") == "1", "items": values}

if not scalars and not list_mods:
    sys.exit(0)

class Locator:
    def __init__(self, lines):
        self.lines = lines

    def locate(self, target_path):
        stack = []  # list of (key, indent)
        for idx, line in enumerate(self.lines):
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            indent = len(line) - len(line.lstrip())
            if stripped.startswith('- '):
                continue
            while stack and stack[-1][1] >= indent:
                stack.pop()
            if ':' not in stripped:
                continue
            key, rest = stripped.split(':', 1)
            key = key.strip()
            path = tuple([item[0] for item in stack] + [key])
            if path == target_path:
                return idx, indent, rest
            tail = rest.strip()
            if tail == '' or tail == '[]':
                stack.append((key, indent))
        raise KeyError(f"Could not locate path {target_path}")

locator = Locator(lines)

modified = False

def set_scalar(path, value):
    global modified
    idx, indent, _ = locator.locate(path)
    key = path[-1]
    indent_str = ' ' * indent
    new_line = f"{indent_str}{key}: \"{value}\""
    if lines[idx] != new_line:
        lines[idx] = new_line
        modified = True

for path, value in scalars:
    set_scalar(path, value)

def parse_list(start_idx, indent, rest):
    if rest.strip() == '[]':
        return [], start_idx + 1
    items = []
    idx = start_idx + 1
    item_indent = indent + 2
    while idx < len(lines):
        line = lines[idx]
        stripped = line.strip()
        if stripped == '' or stripped.startswith('#'):
            idx += 1
            continue
        current_indent = len(line) - len(line.lstrip())
        if current_indent < item_indent or not stripped.startswith('- '):
            break
        value = stripped[2:].strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        items.append(value)
        idx += 1
    return items, idx

def write_list(path, reset, new_items):
    global modified
    start_idx, indent, rest = locator.locate(path)
    key = path[-1]
    existing, end_idx = parse_list(start_idx, indent, rest)
    if reset:
        existing = []
    for item in new_items:
        if item not in existing:
            existing.append(item)
    indent_str = ' ' * indent
    item_indent = ' ' * (indent + 2)
    if not existing:
        replacement = [f"{indent_str}{key}: []"]
    else:
        replacement = [f"{indent_str}{key}:"]
        for item in existing:
            replacement.append(f"{item_indent}- \"{item}\"")
    if lines[start_idx:end_idx] != replacement:
        lines[start_idx:end_idx] = replacement
        modified = True

for path, payload in list_mods.items():
    write_list(path, payload.get('reset', False), payload.get('items', []))

if modified:
    FILE_PATH.write_text('\n'.join(lines) + '\n')
PY

log_lines=()

if [ $PROJECT_CODE_SET -eq 1 ]; then
  log_lines+=("project_code")
fi
if [ $PRODUCT_NAME_SET -eq 1 ]; then
  log_lines+=("product_name")
fi
if [ $DATE_SET -eq 1 ]; then
  log_lines+=("date")
fi
if [ $FACILITATOR_SET -eq 1 ]; then
  log_lines+=("facilitator")
fi
if [ $SUMMARY_SET -eq 1 ]; then
  log_lines+=("summary")
fi
if [ ${#GOALS[@]} -gt 0 ] || [ $RESET_GOALS -eq 1 ]; then
  if [ $RESET_GOALS -eq 1 ]; then
    log_lines+=("goals(reset+${#GOALS[@]})")
  else
    log_lines+=("goals(+${#GOALS[@]})")
  fi
fi
if [ ${#NON_GOALS[@]} -gt 0 ] || [ $RESET_NON_GOALS -eq 1 ]; then
  if [ $RESET_NON_GOALS -eq 1 ]; then
    log_lines+=("non_goals(reset+${#NON_GOALS[@]})")
  else
    log_lines+=("non_goals(+${#NON_GOALS[@]})")
  fi
fi
if [ ${#SUCCESS_METRICS[@]} -gt 0 ] || [ $RESET_SUCCESS -eq 1 ]; then
  if [ $RESET_SUCCESS -eq 1 ]; then
    log_lines+=("success_metrics(reset+${#SUCCESS_METRICS[@]})")
  else
    log_lines+=("success_metrics(+${#SUCCESS_METRICS[@]})")
  fi
fi
if [ ${#ASSUMPTIONS[@]} -gt 0 ] || [ $RESET_ASSUMPTIONS -eq 1 ]; then
  if [ $RESET_ASSUMPTIONS -eq 1 ]; then
    log_lines+=("assumptions(reset+${#ASSUMPTIONS[@]})")
  else
    log_lines+=("assumptions(+${#ASSUMPTIONS[@]})")
  fi
fi
if [ ${#OUT_OF_SCOPE[@]} -gt 0 ] || [ $RESET_OUT -eq 1 ]; then
  if [ $RESET_OUT -eq 1 ]; then
    log_lines+=("out_of_scope(reset+${#OUT_OF_SCOPE[@]})")
  else
    log_lines+=("out_of_scope(+${#OUT_OF_SCOPE[@]})")
  fi
fi

change_summary=$(IFS=','; echo "${log_lines[*]}")
[ -z "$change_summary" ] && change_summary="PRD fields updated"
if [ -n "$NOTE" ]; then
  change_summary="$change_summary — $NOTE"
fi

ts=$(plan_record_revision "plan:prd-update" "$change_summary")
log_info "Updated PRD at $ts"
log_info "Changes: $change_summary"

exit 0

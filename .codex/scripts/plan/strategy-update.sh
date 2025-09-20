#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
STRATEGY_FILE="$PLAN_DIR/foundation/strategy.yaml"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

usage() {
  cat <<'USAGE'
Usage: /plan:strategy-update --input path.yaml [options]

Merge strategy updates into .codex/product-plan/foundation/strategy.yaml.
The payload can include metadata, strategic_goals, strategic_choices, strategic_themes,
commercialization_approach, risks_assumptions, and open_questions.

Options:
  --input PATH              YAML payload to merge (required)
  --replace-section NAME    Replace an entire list (e.g., strategic_goals, strategic_choices.do)
                            Can be repeated for multiple sections.
  --remove SECTION:ID       Remove an entry by id (supports strategic_goals, strategic_choices.do,
                            strategic_choices.do_not, strategic_themes, risks_assumptions, open_questions)
  --note TEXT               Append a note to the revision log entry
  -h, --help                Show this message

Merging rules:
- strategic_goals/themes/risks/open_questions merge by `id`.
- strategic_choices.do / strategic_choices.do_not merge by `id`.
- commercialization_approach and metadata are deep-merged dictionaries.
- --replace-section accepts dotted notation for strategic choices (e.g., strategic_choices.do).
USAGE
}

INPUT_PATH=""
NOTE=""
REPLACE_SECTIONS=()
REMOVALS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      shift
      INPUT_PATH=${1:-}
      ;;
    --replace-section)
      shift
      REPLACE_SECTIONS+=("${1:-}")
      ;;
    --remove)
      shift
      REMOVALS+=("${1:-}")
      ;;
    --note)
      shift
      NOTE=${1:-}
      ;;
    -h|--help)
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
[ -f "$STRATEGY_FILE" ] || log_fatal "Strategy file missing at $STRATEGY_FILE"
[ -n "$INPUT_PATH" ] || log_fatal "--input is required"
[ -f "$INPUT_PATH" ] || log_fatal "Input payload not found: $INPUT_PATH"

REPLACE_CSV="$(IFS=','; echo "${REPLACE_SECTIONS[*]}")"
REMOVALS_CSV="$(IFS=','; echo "${REMOVALS[*]}")"

set +e
PYTHON_OUTPUT=$(python3 - "$STRATEGY_FILE" "$INPUT_PATH" "$REPLACE_CSV" "$REMOVALS_CSV" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload_path = Path(sys.argv[2])
replace_csv = sys.argv[3]
removals_csv = sys.argv[4]

try:
    import yaml
except ImportError as exc:  # pragma: no cover - dependency missing
    print("PyYAML is required. Install it with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

if payload_path.stat().st_size == 0:
    print("NO_CHANGES")
    sys.exit(0)

payload = yaml.safe_load(payload_path.read_text())
if payload is None:
    print("NO_CHANGES")
    sys.exit(0)

doc = yaml.safe_load(path.read_text()) if path.exists() else None
if doc is None:
    doc = {}

replace_sections = set(filter(None, replace_csv.split(',')))
removals = []
if removals_csv:
    for token in removals_csv.split(','):
        token = token.strip()
        if not token:
            continue
        if ':' not in token:
            print(f"Invalid --remove value: {token}", file=sys.stderr)
            sys.exit(1)
        section, key = token.split(':', 1)
        removals.append((section.strip(), key.strip()))

LIST_CONFIG = {
    'strategic_goals': ('strategic_goals', 'id'),
    'strategic_themes': ('strategic_themes', 'id'),
    'risks_assumptions': ('risks_assumptions', 'id'),
    'open_questions': ('open_questions', 'id'),
    'strategic_choices.do': ('strategic_choices', 'do'),
    'strategic_choices.do_not': ('strategic_choices', 'do_not'),
}

changes = []
modified = False

# Ensure nested structures exist
if 'strategic_choices' not in doc or doc['strategic_choices'] is None:
    doc['strategic_choices'] = {'do': [], 'do_not': []}
else:
    doc['strategic_choices'].setdefault('do', [])
    doc['strategic_choices'].setdefault('do_not', [])

# Removals first
for section, key in removals:
    if section not in LIST_CONFIG:
        print(f"Unsupported section for removal: {section}", file=sys.stderr)
        sys.exit(1)
    base_key, sub_key = LIST_CONFIG[section]
    if section.startswith('strategic_choices.'):
        target_list = doc[base_key][sub_key]
        key_field = 'id'
        filtered = [entry for entry in target_list if entry.get(key_field) != key]
        if len(filtered) != len(target_list):
            doc[base_key][sub_key] = filtered
            modified = True
            changes.append(f"removed {section}[{key}]")
        else:
            changes.append(f"no-op {section}[{key}] (not found)")
    else:
        target_list = doc.get(base_key, [])
        key_field = LIST_CONFIG[section][1]
        filtered = [entry for entry in target_list if entry.get(key_field) != key]
        if len(filtered) != len(target_list):
            doc[base_key] = filtered
            modified = True
            changes.append(f"removed {section}[{key}]")
        else:
            changes.append(f"no-op {section}[{key}] (not found)")

metadata_updates = []
if 'metadata' in payload and isinstance(payload['metadata'], dict):
    doc.setdefault('metadata', {})
    for key, value in payload['metadata'].items():
        current = doc['metadata'].get(key)
        if current != value:
            doc['metadata'][key] = value
            metadata_updates.append(key)
            modified = True
if metadata_updates:
    changes.append("metadata:" + ','.join(metadata_updates))

if 'commercialization_approach' in payload and isinstance(payload['commercialization_approach'], dict):
    doc.setdefault('commercialization_approach', {})
    before = yaml.safe_dump(doc['commercialization_approach'], sort_keys=True)
    for k, v in payload['commercialization_approach'].items():
        if isinstance(v, dict) and isinstance(doc['commercialization_approach'].get(k), dict):
            doc['commercialization_approach'][k].update(v)
        else:
            doc['commercialization_approach'][k] = v
    after = yaml.safe_dump(doc['commercialization_approach'], sort_keys=True)
    if before != after:
        modified = True
        changes.append("commercialization_approach")

# Helper for list merges

def ensure_list(container, key):
    if key not in container or container[key] is None:
        container[key] = []


def process_list(section_name, entries, replace=False):
    global modified
    if section_name.startswith('strategic_choices.'):
        base_key, sub_key = LIST_CONFIG[section_name]
        ensure_list(doc['strategic_choices'], sub_key)
        target_list = doc['strategic_choices'][sub_key]
        key_field = 'id'
    else:
        base_key, key_field = LIST_CONFIG[section_name]
        ensure_list(doc, base_key)
        target_list = doc[base_key]

    if replace:
        if section_name.startswith('strategic_choices.'):
            doc['strategic_choices'][sub_key] = entries
        else:
            doc[base_key] = entries
        modified = True
        changes.append(f"replaced {section_name}")
        target_list = entries
    else:
        for entry in entries:
            if not isinstance(entry, dict):
                print(f"Entries in {section_name} must be mappings", file=sys.stderr)
                sys.exit(1)
            identifier = entry.get('id')
            if not identifier:
                print(f"Entries in {section_name} require 'id'", file=sys.stderr)
                sys.exit(1)
            match = None
            for existing in target_list:
                if existing.get('id') == identifier:
                    match = existing
                    break
            if match is None:
                target_list.append(entry)
                modified = True
                changes.append(f"added {section_name}[{identifier}]")
            else:
                before = yaml.safe_dump(match, sort_keys=True)
                for k, v in entry.items():
                    if isinstance(v, dict) and isinstance(match.get(k), dict):
                        match[k].update(v)
                    else:
                        match[k] = v
                after = yaml.safe_dump(match, sort_keys=True)
                if before != after:
                    modified = True
                    changes.append(f"updated {section_name}[{identifier}]")

    # Remove placeholder entries lacking ids
    cleaned = [entry for entry in target_list if entry.get('id')]
    if section_name.startswith('strategic_choices.'):
        doc['strategic_choices'][sub_key] = cleaned
    else:
        doc[base_key] = cleaned

list_sections = {
    'strategic_goals': 'strategic_goals',
    'strategic_themes': 'strategic_themes',
    'risks_assumptions': 'risks_assumptions',
    'open_questions': 'open_questions',
}

for section, payload_entries in list_sections.items():
    if section not in payload:
        continue
    entries = payload[section]
    if entries is None:
        continue
    if not isinstance(entries, list):
        print(f"Section {section} must be a list", file=sys.stderr)
        sys.exit(1)
    process_list(section, entries, replace=(section in replace_sections))

if 'strategic_choices' in payload and isinstance(payload['strategic_choices'], dict):
    for choice_key in ('do', 'do_not'):
        if choice_key in payload['strategic_choices']:
            entries = payload['strategic_choices'][choice_key]
            if entries is None:
                continue
            if not isinstance(entries, list):
                print(f"strategic_choices.{choice_key} must be a list", file=sys.stderr)
                sys.exit(1)
            section_name = f"strategic_choices.{choice_key}"
            replace = section_name in replace_sections
            process_list(section_name, entries, replace=replace)

if not modified:
    print("NO_CHANGES")
    sys.exit(0)

yaml_dump = yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)
path.write_text(yaml_dump)

summary = '; '.join(dict.fromkeys(changes))
print(summary or 'updated strategy')
PY
)
STATUS=$?
set -e

if [ $STATUS -ne 0 ]; then
  log_error "$PYTHON_OUTPUT"
  exit $STATUS
fi

if [ "$PYTHON_OUTPUT" = "NO_CHANGES" ]; then
  log_info "No strategy updates applied."
  exit 0
fi

SUMMARY="$PYTHON_OUTPUT"
if [ -n "$NOTE" ]; then
  SUMMARY="$SUMMARY — $NOTE"
fi

TIMESTAMP=$(plan_record_revision "plan:strategy-update" "$SUMMARY")
log_info "Updated strategy at $TIMESTAMP"
log_info "Changes: $SUMMARY"

exit 0

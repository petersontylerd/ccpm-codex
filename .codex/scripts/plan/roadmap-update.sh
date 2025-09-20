#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
ROADMAP_FILE="$PLAN_DIR/foundation/roadmap.yaml"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

usage() {
  cat <<'USAGE'
Usage: /plan:roadmap-update --input path.yaml [options]

Merge roadmap updates into .codex/product-plan/foundation/roadmap.yaml.
The payload can include metadata, time_horizons (short_term|mid_term|long_term),
risks_assumptions, and open_questions.

Options:
  --input PATH             YAML payload to merge (required)
  --replace-section NAME   Replace a list instead of merging. Supports:
                           short_term.goals, short_term.themes, short_term.milestones,
                           mid_term.goals, mid_term.themes, mid_term.milestones,
                           long_term.goals, long_term.themes, long_term.milestones,
                           risks_assumptions, open_questions
  --remove SECTION:KEY     Remove an entry by value/id. Examples:
                           short_term.goals:SG-01, short_term.milestones:M-01,
                           risks_assumptions:RM-R-01, open_questions:Q-RM-01
  --note TEXT              Append a note to the revision log entry
  -h, --help               Show this message

All writes stamp a Chicago timestamp and append to revisions.log.
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
[ -f "$ROADMAP_FILE" ] || log_fatal "Roadmap file missing at $ROADMAP_FILE"
[ -n "$INPUT_PATH" ] || log_fatal "--input is required"
[ -f "$INPUT_PATH" ] || log_fatal "Input payload not found: $INPUT_PATH"

REPLACE_CSV="$(IFS=','; echo "${REPLACE_SECTIONS[*]}")"
REMOVALS_CSV="$(IFS=','; echo "${REMOVALS[*]}")"

set +e
PYTHON_OUTPUT=$(python3 - "$ROADMAP_FILE" "$INPUT_PATH" "$REPLACE_CSV" "$REMOVALS_CSV" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload_path = Path(sys.argv[2])
replace_csv = sys.argv[3]
removals_csv = sys.argv[4]

try:
    import yaml
except ImportError:  # pragma: no cover - dependency missing
    print("PyYAML is required. Install it with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

def load_yaml(p: Path):
    text = p.read_text()
    if text.strip() == "":
        return None
    return yaml.safe_load(text)

payload = load_yaml(payload_path)
if payload is None:
    print("NO_CHANGES")
    sys.exit(0)

doc = load_yaml(path) or {}

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

changes = []
modified = False

TIME_HORIZON_SECTIONS = {
    'goals',
    'themes',
    'milestones',
}

KEYED_LISTS = {
    'risks_assumptions': 'id',
    'open_questions': 'id',
}

def validate_replace(section: str) -> None:
    if not section:
        return
    if section in KEYED_LISTS:
        return
    if '.' in section:
        horizon_name, sub = section.split('.', 1)
        if not horizon_name:
            print(f"Unsupported --replace-section value: {section}", file=sys.stderr)
            sys.exit(1)
        if sub not in TIME_HORIZON_SECTIONS:
            print(f"Unsupported --replace-section value: {section}", file=sys.stderr)
            sys.exit(1)
        return
    print(f"Unsupported --replace-section value: {section}", file=sys.stderr)
    sys.exit(1)

for section in replace_sections:
    validate_replace(section)

HORIZON_ORDER = ['short_term', 'mid_term', 'long_term']

def deep_merge(dest, src):
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dest.get(key), dict):
            deep_merge(dest[key], value)
        else:
            dest[key] = value

def ensure_horizon(name: str):
    doc.setdefault('time_horizons', {})
    horizon = doc['time_horizons'].setdefault(name, {})
    horizon.setdefault('goals', [])
    horizon.setdefault('themes', [])
    horizon.setdefault('milestones', [])
    return horizon

for horizon_name in HORIZON_ORDER:
    ensure_horizon(horizon_name)

for section, key in removals:
    if section in KEYED_LISTS:
        key_field = KEYED_LISTS[section]
        doc.setdefault(section, [])
        original = doc[section]
        kept = [entry for entry in original if entry.get(key_field) != key]
        if len(kept) != len(original):
            doc[section] = kept
            modified = True
            changes.append(f"removed {section}[{key}]")
        else:
            changes.append(f"no-op {section}[{key}] (not found)")
        continue

    if '.' in section:
        horizon_name, sub = section.split('.', 1)
        if sub not in TIME_HORIZON_SECTIONS:
            print(f"Unsupported section for removal: {section}", file=sys.stderr)
            sys.exit(1)
        horizon = ensure_horizon(horizon_name)
        if sub in ('goals', 'themes'):
            before = list(horizon[sub])
            horizon[sub] = [item for item in horizon[sub] if item != key]
            if horizon[sub] != before:
                modified = True
                changes.append(f"removed {section}({key})")
            else:
                changes.append(f"no-op {section}({key}) (not found)")
        elif sub == 'milestones':
            original = horizon[sub]
            kept = [entry for entry in original if entry.get('id') != key]
            if len(kept) != len(original):
                horizon[sub] = kept
                modified = True
                changes.append(f"removed {section}[{key}]")
            else:
                changes.append(f"no-op {section}[{key}] (not found)")
        continue

    print(f"Unsupported section for removal: {section}", file=sys.stderr)
    sys.exit(1)

if 'metadata' in payload and isinstance(payload['metadata'], dict):
    doc.setdefault('metadata', {})
    meta_changes = []
    for key, value in payload['metadata'].items():
        if doc['metadata'].get(key) != value:
            doc['metadata'][key] = value
            meta_changes.append(key)
            modified = True
    if meta_changes:
        changes.append("metadata:" + ','.join(meta_changes))

if 'time_horizons' in payload:
    th_payload = payload['time_horizons']
    if not isinstance(th_payload, dict):
        print('time_horizons must be a mapping', file=sys.stderr)
        sys.exit(1)
    for horizon_name, data in th_payload.items():
        if not isinstance(data, dict):
            print(f"time_horizons.{horizon_name} must be a mapping", file=sys.stderr)
            sys.exit(1)
        horizon = ensure_horizon(horizon_name)

        # goals
        if 'goals' in data:
            goals = data['goals']
            if goals is None:
                goals = []
            if not isinstance(goals, list):
                print(f"{horizon_name}.goals must be a list", file=sys.stderr)
                sys.exit(1)
            replace_key = f"{horizon_name}.goals"
            if replace_key in replace_sections:
                cleaned = [str(item) for item in goals if item]
                if horizon['goals'] != cleaned:
                    horizon['goals'] = cleaned
                    modified = True
                    changes.append(f"replaced {replace_key}")
            else:
                for item in goals:
                    if not isinstance(item, str):
                        print(f"Entries in {horizon_name}.goals must be strings", file=sys.stderr)
                        sys.exit(1)
                    if item and item not in horizon['goals']:
                        horizon['goals'].append(item)
                        modified = True
                        changes.append(f"added {horizon_name}.goals({item})")

        # themes
        if 'themes' in data:
            themes = data['themes']
            if themes is None:
                themes = []
            if not isinstance(themes, list):
                print(f"{horizon_name}.themes must be a list", file=sys.stderr)
                sys.exit(1)
            replace_key = f"{horizon_name}.themes"
            if replace_key in replace_sections:
                cleaned = [str(item) for item in themes if item]
                if horizon['themes'] != cleaned:
                    horizon['themes'] = cleaned
                    modified = True
                    changes.append(f"replaced {replace_key}")
            else:
                for item in themes:
                    if not isinstance(item, str):
                        print(f"Entries in {horizon_name}.themes must be strings", file=sys.stderr)
                        sys.exit(1)
                    if item and item not in horizon['themes']:
                        horizon['themes'].append(item)
                        modified = True
                        changes.append(f"added {horizon_name}.themes({item})")

        # milestones
        if 'milestones' in data:
            milestones = data['milestones']
            if milestones is None:
                milestones = []
            if not isinstance(milestones, list):
                print(f"{horizon_name}.milestones must be a list", file=sys.stderr)
                sys.exit(1)
            replace_key = f"{horizon_name}.milestones"

            clean_list = []
            for entry in milestones:
                if not isinstance(entry, dict):
                    print(f"Milestones in {horizon_name} must be mappings", file=sys.stderr)
                    sys.exit(1)
                identifier = entry.get('id')
                if not identifier:
                    print(f"Milestones in {horizon_name} require 'id'", file=sys.stderr)
                    sys.exit(1)
                clean_list.append(entry)

            if replace_key in replace_sections:
                if horizon['milestones'] != clean_list:
                    horizon['milestones'] = clean_list
                    modified = True
                    changes.append(f"replaced {replace_key}")
            else:
                target = horizon['milestones']
                for entry in clean_list:
                    identifier = entry['id']
                    match = None
                    for existing in target:
                        if existing.get('id') == identifier:
                            match = existing
                            break
                    if match is None:
                        target.append(entry)
                        modified = True
                        changes.append(f"added {horizon_name}.milestones[{identifier}]")
                    else:
                        before = yaml.safe_dump(match, sort_keys=True)
                        deep_merge(match, entry)
                        after = yaml.safe_dump(match, sort_keys=True)
                        if before != after:
                            modified = True
                            changes.append(f"updated {horizon_name}.milestones[{identifier}]")
                horizon['milestones'] = [m for m in target if m.get('id')]

if 'risks_assumptions' in payload:
    ra = payload['risks_assumptions']
    if ra is None:
        ra = []
    if not isinstance(ra, list):
        print('risks_assumptions must be a list', file=sys.stderr)
        sys.exit(1)
    doc.setdefault('risks_assumptions', [])
    replace_key = 'risks_assumptions'
    clean_list = []
    for entry in ra:
        if not isinstance(entry, dict) or not entry.get('id'):
            print('risks_assumptions entries must include id', file=sys.stderr)
            sys.exit(1)
        clean_list.append(entry)
    if replace_key in replace_sections:
        if doc['risks_assumptions'] != clean_list:
            doc['risks_assumptions'] = clean_list
            modified = True
            changes.append('replaced risks_assumptions')
    else:
        target = doc['risks_assumptions']
        for entry in clean_list:
            identifier = entry['id']
            match = next((item for item in target if item.get('id') == identifier), None)
            if match is None:
                target.append(entry)
                modified = True
                changes.append(f"added risks_assumptions[{identifier}]")
            else:
                before = yaml.safe_dump(match, sort_keys=True)
                deep_merge(match, entry)
                after = yaml.safe_dump(match, sort_keys=True)
                if before != after:
                    modified = True
                    changes.append(f"updated risks_assumptions[{identifier}]")
        doc['risks_assumptions'] = [item for item in target if item.get('id')]

if 'open_questions' in payload:
    oq = payload['open_questions']
    if oq is None:
        oq = []
    if not isinstance(oq, list):
        print('open_questions must be a list', file=sys.stderr)
        sys.exit(1)
    doc.setdefault('open_questions', [])
    replace_key = 'open_questions'
    clean_list = []
    for entry in oq:
        if not isinstance(entry, dict) or not entry.get('id'):
            print('open_questions entries must include id', file=sys.stderr)
            sys.exit(1)
        clean_list.append(entry)
    if replace_key in replace_sections:
        if doc['open_questions'] != clean_list:
            doc['open_questions'] = clean_list
            modified = True
            changes.append('replaced open_questions')
    else:
        target = doc['open_questions']
        for entry in clean_list:
            identifier = entry['id']
            match = next((item for item in target if item.get('id') == identifier), None)
            if match is None:
                target.append(entry)
                modified = True
                changes.append(f"added open_questions[{identifier}]")
            else:
                before = yaml.safe_dump(match, sort_keys=True)
                deep_merge(match, entry)
                after = yaml.safe_dump(match, sort_keys=True)
                if before != after:
                    modified = True
                    changes.append(f"updated open_questions[{identifier}]")
        doc['open_questions'] = [item for item in target if item.get('id')]

if not modified:
    print('NO_CHANGES')
    sys.exit(0)

def unique(seq):
    seen = set()
    result = []
    for item in seq:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result

changes = unique(changes)

yaml_dump = yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)
original_text = path.read_text() if path.exists() else ''
preamble_lines = []
for line in original_text.splitlines():
    if line.startswith('#'):
        preamble_lines.append(line)
    else:
        break
if preamble_lines:
    yaml_dump = '\n'.join(preamble_lines) + '\n' + yaml_dump

path.write_text(yaml_dump)

summary = '; '.join(changes)
print(summary or 'updated roadmap')
PY
)
STATUS=$?
set -e

if [ $STATUS -ne 0 ]; then
  log_error "$PYTHON_OUTPUT"
  exit $STATUS
fi

if [ "$PYTHON_OUTPUT" = "NO_CHANGES" ]; then
  log_info "No roadmap updates applied."
  exit 0
fi

SUMMARY="$PYTHON_OUTPUT"
if [ -n "$NOTE" ]; then
  SUMMARY="$SUMMARY — $NOTE"
fi

TIMESTAMP=$(plan_record_revision "plan:roadmap-update" "$SUMMARY")
log_info "Updated roadmap at $TIMESTAMP"
log_info "Changes: $SUMMARY"

exit 0

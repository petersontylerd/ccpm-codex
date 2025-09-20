#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PLAN_DIR="$REPO_ROOT/.codex/product-plan"
PERSONAS_FILE="$PLAN_DIR/foundation/personas.yaml"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

usage() {
  cat <<'USAGE'
Usage: /plan:personas-update --input path.yaml [options]

Merge persona/buyer/influencer updates into .codex/product-plan/foundation/personas.yaml.
The payload should be YAML containing any combination of:
  metadata, primary_personas, secondary_personas, buyers, influencers, open_questions

Options:
  --input PATH            YAML payload to merge (required)
  --replace-section NAME  Replace the entire section (can be repeated)
                          Examples: primary_personas, secondary_personas, buyers, influencers
  --remove SECTION:KEY    Remove an entry by id/role (can be repeated)
                          Examples: primary_personas:P-001, buyers:CFO
  --note TEXT             Append a note to the revision log entry
  -h, --help              Show this message

Merging rules:
- primary/secondary personas merge by `id`.
- buyers/influencers merge by `role`.
- open_questions merge by `id`.
- With --replace-section the section is overwritten by the payload list.
- Placeholder entries with blank ids/roles are removed automatically after updates.
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
[ -f "$PERSONAS_FILE" ] || log_fatal "Personas file missing at $PERSONAS_FILE"
[ -n "$INPUT_PATH" ] || log_fatal "--input is required"
[ -f "$INPUT_PATH" ] || log_fatal "Input payload not found: $INPUT_PATH"

REPLACE_CSV="$(IFS=','; echo "${REPLACE_SECTIONS[*]}")"
REMOVALS_CSV="$(IFS=','; echo "${REMOVALS[*]}")"

set +e
PYTHON_OUTPUT=$(python3 - "$PERSONAS_FILE" "$INPUT_PATH" "$REPLACE_CSV" "$REMOVALS_CSV" <<'PY'
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

def ensure_list(key):
    if key not in doc or doc[key] is None:
        doc[key] = []

def deep_merge(dest, src):
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dest.get(key), dict):
            deep_merge(dest[key], value)
        else:
            dest[key] = value

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

KEY_FIELDS = {
    'primary_personas': 'id',
    'secondary_personas': 'id',
    'buyers': 'role',
    'influencers': 'role',
    'open_questions': 'id',
}

changes = []
modified = False

# handle removals first
for section, key in removals:
    if section not in KEY_FIELDS:
        print(f"Unsupported section for removal: {section}", file=sys.stderr)
        sys.exit(1)
    ensure_list(section)
    key_field = KEY_FIELDS[section]
    original = doc[section]
    kept = [entry for entry in original if entry.get(key_field) != key]
    if len(kept) != len(original):
        doc[section] = kept
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

persona_sections = ['primary_personas', 'secondary_personas', 'buyers', 'influencers', 'open_questions']

for section in persona_sections:
    if section not in payload:
        continue
    data = payload[section]
    if data is None:
        continue
    if not isinstance(data, list):
        print(f"Section {section} must be a list", file=sys.stderr)
        sys.exit(1)
    ensure_list(section)
    key_field = KEY_FIELDS[section]
    if section in replace_sections:
        doc[section] = data
        modified = True
        changes.append(f"replaced {section}")
    else:
        for entry in data:
            if not isinstance(entry, dict):
                print(f"Entries in {section} must be mappings", file=sys.stderr)
                sys.exit(1)
            identifier = entry.get(key_field)
            if not identifier:
                print(f"Entries in {section} require '{key_field}'", file=sys.stderr)
                sys.exit(1)
            target_list = doc[section]
            match = None
            for existing in target_list:
                if existing.get(key_field) == identifier:
                    match = existing
                    break
            if match is None:
                target_list.append(entry)
                modified = True
                changes.append(f"added {section}[{identifier}]")
            else:
                before = yaml.safe_dump(match, sort_keys=True)
                deep_merge(match, entry)
                after = yaml.safe_dump(match, sort_keys=True)
                if before != after:
                    modified = True
                    changes.append(f"updated {section}[{identifier}]")
    # remove placeholder empties
    doc[section] = [entry for entry in doc[section] if entry.get(key_field)]

if not modified:
    print("NO_CHANGES")
    sys.exit(0)

yaml_dump = yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)
path.write_text(yaml_dump)

summary = '; '.join(dict.fromkeys(changes))
print(summary or 'updated personas')
PY
)
STATUS=$?
set -e

if [ $STATUS -ne 0 ]; then
  log_error "$PYTHON_OUTPUT"
  exit $STATUS
fi

if [ "$PYTHON_OUTPUT" = "NO_CHANGES" ]; then
  log_info "No persona updates applied."
  exit 0
fi

SUMMARY="$PYTHON_OUTPUT"
if [ -n "$NOTE" ]; then
  SUMMARY="$SUMMARY — $NOTE"
fi

TIMESTAMP=$(plan_record_revision "plan:personas-update" "$SUMMARY")
log_info "Updated personas at $TIMESTAMP"
log_info "Changes: $SUMMARY"

exit 0

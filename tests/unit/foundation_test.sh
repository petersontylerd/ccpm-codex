#!/bin/bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "PyYAML is required. Install with: pip install pyyaml" >&2
  exit 1
fi

python3 .codex/scripts/tests/run_foundation_unit.py

#!/bin/bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

printf '\n== TDD helper smoke ==\n'

printf 'Running testing:red (expected failure)...\n'
bash .codex/scripts/testing/red.sh --no-log --note "smoke" -- bash -lc 'exit 1'

printf 'Running testing:refactor (expected success)...\n'
bash .codex/scripts/testing/refactor.sh --no-log --note "smoke" -- bash -lc 'exit 0'

printf '\nTDD helper smoke complete.\n'

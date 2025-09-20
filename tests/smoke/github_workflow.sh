#!/bin/bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

printf '\n== GitHub workflow smoke ==\n'

# Ensure plan exists
if [ ! -d .codex/product-plan ]; then
  bash .codex/scripts/plan/init.sh >/dev/null
fi

printf 'Running plan status...\n'
bash .codex/scripts/plan/status.sh >/dev/null

printf 'Previewing github sync diff...\n'
bash .codex/scripts/ops/github-sync.sh --preview --epic E004 --type STORY --diff --local-only >/dev/null

printf 'Listing offline queue...\n'
bash .codex/scripts/ops/offline-queue.sh --list >/dev/null

printf '\nSmoke run complete.\n'

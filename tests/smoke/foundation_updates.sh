#!/bin/bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

PLAN_DIR=".codex/product-plan"
if [ ! -d "$PLAN_DIR" ]; then
  echo "Product plan missing. Run plan:init first." >&2
  exit 1
fi

BACKUP_DIR=$(mktemp -d)
TMP_DIR=$(mktemp -d)

cleanup() {
  rsync -a --delete "$BACKUP_DIR/" "$PLAN_DIR/"
  rm -rf "$BACKUP_DIR" "$TMP_DIR"
}
trap cleanup EXIT

rsync -a "$PLAN_DIR/" "$BACKUP_DIR/"

printf '\n== Foundation updates smoke ==\n'

PRD_LOG="$(mktemp --tmpdir="$TMP_DIR" prd.XXXX.yaml)"
# PRD update executed inline via CLI (no payload file needed)

printf 'Running plan:prd-update...\n'
bash .codex/scripts/plan/prd-update.sh \
  --product-name "Codex PM" \
  --project-code CPM-001 \
  --summary "Spec-driven workflow for Codex CLI (smoke)" \
  --goal "Smoke goal" \
  --note "foundation smoke"

PERSONAS_PAYLOAD="$TMP_DIR/personas.yaml"
cat > "$PERSONAS_PAYLOAD" <<'YAML'
metadata:
  project_code: CPM-001
  product_name: Codex PM
primary_personas:
  - id: P-SMOKE-01
    name: Smoke Persona
    role: QA Lead
    goals:
      - Validate workflows stay deterministic
YAML

printf 'Running plan:personas-update...\n'
bash .codex/scripts/plan/personas-update.sh \
  --input "$PERSONAS_PAYLOAD" \
  --note "foundation smoke"

STRATEGY_PAYLOAD="$TMP_DIR/strategy.yaml"
cat > "$STRATEGY_PAYLOAD" <<'YAML'
strategic_goals:
  - id: SG-SMOKE-01
    description: Ensure smoke tests exercise plan commands
    time_horizon: short-term
YAML

printf 'Running plan:strategy-update...\n'
bash .codex/scripts/plan/strategy-update.sh \
  --input "$STRATEGY_PAYLOAD" \
  --note "foundation smoke"

ROADMAP_PAYLOAD="$TMP_DIR/roadmap.yaml"
cat > "$ROADMAP_PAYLOAD" <<'YAML'
time_horizons:
  short_term:
    goals:
      - SG-SMOKE-01
    milestones:
      - id: M-SMOKE-01
        description: Deliver roadmap smoke milestone
        key_outcome: Ensure roadmap updates are scripted
risks_assumptions:
  - id: RM-SMOKE-01
    description: Roadmap automation gap
    mitigation: Cover with scripted checks
open_questions:
  - id: Q-SMOKE-01
    question: Do milestones sync cleanly with GitHub planning?
    blocking: false
YAML

printf 'Running plan:roadmap-update...\n'
bash .codex/scripts/plan/roadmap-update.sh \
  --input "$ROADMAP_PAYLOAD" \
  --note "foundation smoke"

printf '\nFoundation updates smoke complete.\n'

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

printf 'Running epic:new...\n'
EPIC_OUTPUT=$(bash .codex/scripts/epic/new.sh \
  --name "Smoke Epic" \
  --description "Smoke ensures epic creation works" \
  --priority "Should" \
  --facilitator "Smoke Facilitator")
printf '%s\n' "$EPIC_OUTPUT"
NEW_EPIC_ID=$(printf '%s\n' "$EPIC_OUTPUT" | awk '/Created epic/ {print $4; exit}')

printf 'Running feature:new...\n'
FEATURE_OUTPUT=$(bash .codex/scripts/feature/new.sh \
  --epic "$NEW_EPIC_ID" \
  --name "Smoke Feature" \
  --description "Smoke ensures feature creation works" \
  --user-value "Enable smoke coverage" \
  --priority "Could" \
  --facilitator "Smoke Facilitator")
printf '%s\n' "$FEATURE_OUTPUT"
NEW_FEATURE_ID=$(printf '%s\n' "$FEATURE_OUTPUT" | awk '/Created feature/ {print $4; exit}')

printf 'Running story:new...\n'
STORY_OUTPUT=$(bash .codex/scripts/story/new.sh \
  --epic "$NEW_EPIC_ID" \
  --feature "$NEW_FEATURE_ID" \
  --name "Smoke Story" \
  --as "Smoke user" \
  --i-want "exercise story scaffolding" \
  --so-that "new commands stay covered" \
  --description "Smoke ensures story creation works" \
  --priority "Could" \
  --facilitator "Smoke Facilitator")
printf '%s\n' "$STORY_OUTPUT"
NEW_STORY_ID=$(printf '%s\n' "$STORY_OUTPUT" | awk '/Created user story/ {print $5; exit}')

EPIC_FILE="$PLAN_DIR/epics/epic-$NEW_EPIC_ID/epic-$NEW_EPIC_ID.yaml"
FEATURE_FILE="$PLAN_DIR/epics/epic-$NEW_EPIC_ID/features-$NEW_EPIC_ID/feature-$NEW_EPIC_ID-$NEW_FEATURE_ID/feature-$NEW_EPIC_ID-$NEW_FEATURE_ID.yaml"
STORY_FILE="$PLAN_DIR/epics/epic-$NEW_EPIC_ID/features-$NEW_EPIC_ID/feature-$NEW_EPIC_ID-$NEW_FEATURE_ID/user-stories-$NEW_EPIC_ID-$NEW_FEATURE_ID/user-story-$NEW_EPIC_ID-$NEW_FEATURE_ID-$NEW_STORY_ID.yaml"

grep -q "epic_id: \"$NEW_EPIC_ID\"" "$EPIC_FILE"
grep -q "feature_id: \"$NEW_FEATURE_ID\"" "$FEATURE_FILE"
grep -q "user_story_id: \"$NEW_STORY_ID\"" "$STORY_FILE"

printf '\nFoundation updates smoke complete.\n'

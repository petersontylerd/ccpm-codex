# `.claude/` Removal Checklist

Use this checklist before deleting the legacy Claude assets. Each item should be ✅ before running the removal script (to be written once all gates are closed).

## Functional Parity
- [x] Persona editor command (`/plan:personas-update`) lives under `.codex/` and updates `foundation/personas.yaml` with revision logging.
- [x] Strategy editor command (`/plan:strategy-update`) exists under `.codex/product-plan/foundation/`.
- [x] Roadmap editor command (`/plan:roadmap-update`) implemented under `.codex/product-plan/foundation/`.
- [x] All active prompts point exclusively to `.codex` scripts (audit `rg "\.claude/"`).
- [x] `docs/archive/codex-migration.md` “Outstanding Parity Items” section is empty or archived.

## Testing & Automation
- [x] Smoke tests cover plan CRUD (`tests/smoke/*`) and GitHub sync diff/apply paths (see `tests/smoke/foundation_updates.sh`, `tests/smoke/github_workflow.sh`).
- [x] Additional automated coverage (unit/integration) exists for `plan_record_revision`, `plan_list_artifacts`, and offline queue replays (e.g., `tests/unit/foundation_test.sh`, `tests/unit/github_ops_test.sh`).
- [x] CI/automation (if applicable) references `.codex/` paths only (no workflows currently defined).

## Documentation & Guidance
- [x] README, COMMANDS, AGENTS, and onboarding docs now reference only the Codex workflow (legacy notes reside in migration docs).
- [x] Migration plan updated to mark the legacy directory removal as complete.
- [x] A short “Removing the legacy Claude tree” section exists in README with the workflow used.

## Final Validation
- [x] Search for legacy references (e.g., `rg "dot-claude"`) returns only archival docs.
- [x] `tests/smoke/github_workflow.sh` and `tests/smoke/tdd_helpers.sh` pass from a clean clone (verified 2025-09-19).
- [x] Git history notes the removal (commit message and release notes).

Once all boxes are checked, remove the entire `.claude/` directory and update `.gitignore`, docs, and any scripts that referenced it.

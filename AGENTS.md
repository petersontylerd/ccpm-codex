# Codex Agent & Command Patterns

This repository now orients all guided workflows around Codex CLI prompts and shell scripts that live under `.codex/`. Legacy Claude assets have been removed after migration; the history is documented in `docs/archive/codex-migration.md`.

## Where Things Live

- `.codex/prompts/` – Codex-facing prompts. Each prompt mirrors a shell script with the same path/name.
- `.codex/scripts/` – Executable helpers the prompts invoke. Shared utilities live in `.codex/scripts/lib/`.
- `.codex/rules/` – Global rules applied to Codex sessions (Central Time timestamps, TDD expectations, etc.).
- `.codex/product-plan/` – Source of truth for the PRD, epics, features, and user stories.
- `tests/logs/` – Output from `/testing:*` commands, plus the TDD journal (`tdd-history.log`).

Legacy Claude assets have been removed; refer to `docs/archive/claude-removal-checklist.md` for the process we followed.

## Recommended Agent Invocations

| Goal | Prompt / Script | What It Does |
| --- | --- | --- |
| Prime context | `/context:prime` → `.codex/scripts/context/prime.sh` | Summarises PRD metadata, recent revisions, and epic/feature snapshots so Codex starts grounded. |
| Inspect plan | `/plan:status` → `.codex/scripts/plan/status.sh` | Counts epics/features/stories and reports latest revision info. |
| Update PRD | `/plan:prd-update` → `.codex/scripts/plan/prd-update.sh` | Edits PRD metadata, summary, and goal lists with full revision logging. |
| Maintain personas | `/plan:personas-update` → `.codex/scripts/plan/personas-update.sh` | Merges persona/buyer/influencer records by id/role and removes placeholders. |
| Maintain strategy | `/plan:strategy-update` → `.codex/scripts/plan/strategy-update.sh` | Updates strategic goals/choices/themes and commercialization notes. |
| Grow hierarchy | `/epic:new`, `/feature:new`, `/story:new` | Scaffolds new YAML, stamps Central Time, and logs changes. |
| Edit hierarchy | `/epic:update`, `/feature:update`, `/story:update` | In-place YAML edits that keep revision history aligned. |
| Enforce TDD | `/testing:red`, `/testing:run`, `/testing:refactor` | Confirm red/green cycles, capture execution windows, and append entries to the TDD journal. |
| GitHub sync | `/ops:github-sync` | Preview/apply hierarchy updates; outputs diff + plan summaries and records results in the plan. |
| GitHub pull | `/ops:github-pull` | Refresh local metadata with remote issue state while obeying Central Time logging. |
| Offline queue | `/ops:offline-queue` | Inspect/export queued creations, replay them once connectivity returns, or clear the queue. |

## Working With Agents

1. **Keep heavy work in sub-agents.** Invocations like `/testing:red` or `/ops:github-sync --diff` keep verbose output out of the main conversation.
2. **Respect the rules.** Source `.codex/scripts/lib/init.sh` in bespoke helpers so you inherit logging, timestamp, and GitHub checks.
3. **Close the loop.** After significant changes, update the product plan (PRD, personas, strategy, epics, features, stories) so downstream agents read canonical data. See `docs/foundation-updates.md` for payload patterns.
4. **Journal the cycle.** Use the TDD helpers to document red → green → refactor impact in `tests/logs/tdd-history.log`.

When in doubt, run `docs/archive/codex-migration.md` for the latest status and roadmap updates.

# Codex Migration Plan

This document tracks the transition from the Claude Code PM workflow to the Codex CLI-focused `ccpm-codex` workflow. It captures the baseline snapshot, intended architecture, and execution phases so we retire `.claude/` only after the Codex equivalents are live and validated.

## Baseline Snapshot

- **Repository heritage:** Fork of `automazeio/ccpm`; no local modifications besides `AGENTS.md`.
- **Legacy assets:**
  - `.claude/commands/pm/*.md` prompts that shell out to `.claude/scripts/pm/*.sh` for PRD/epic/issue orchestration.
  - `.claude/commands/context/*.md` for context priming and updates that generate markdown artifacts such as `product-context.md`, `product-brief.md`, and `product-vision.md`.
  - `.claude/rules/*.md` including a UTC-specific datetime requirement, GitHub/worktree safety rules, and testing guidance.
  - `.claude/agents/*.md` providing task-specific instruction sets (code analyzer, test runner, parallel worker, etc.).
  - `.claude/scripts/test-and-log.sh` utility for redirecting test output to `tests/logs/`.
- **Product planning:** `.codex/product-plan/` is committed as the source of truth with PRD → epics → features → user stories captured in YAML (no separate template directory required).

## Target Architecture (Codex)

- **Prompts & scripts:**
  - Each Codex command lives as `.codex/prompts/ccpm-<verb>-<noun>.md` paired 1:1 with an executable `.codex/scripts/<group>/<command>.sh` (e.g., `ccpm-update-prd.md` ↔ `plan/prd-update.sh`).
  - `.codex/scripts/ops/prompts-sync.sh` copies those prompts into `~/.codex/prompts/` so Codex CLI sessions pick them up; onboarding flows (e.g., `plan:init`) should run it automatically.
  - Prompts call their script counterparts using the exact CLI invocation users would run manually, passing through arguments verbatim.
- **Product plan operations:**
  - Core commands focus on updating/extending the structured artifacts committed in `.codex/product-plan/`, rather than regenerating PRDs/epics/features from scratch in markdown.
  - Hierarchy management supports: updating PRD metadata, adding new epics/features/user stories, and appending to existing structures with audit logging.
- **Rules & context:**
  - Move rule files to `.codex/rules/`, including a new datetime rule that captures real `America/Chicago` timestamps with second precision.
  - Replace legacy context prompts with ones that read from the product plan artifacts and any curated `.codex/context/*.md` files; do not instruct generation of deprecated markdown briefs.
- **TDD guidance:**
  - Provide a Codex-native rule plus supporting prompts/scripts to encourage red→green→refactor loops, surfaced through `testing:*` commands.
  - Adapt or replace `.claude/scripts/test-and-log.sh` with Codex-branded equivalents housed under `.codex/scripts/testing/`.
- **GitHub integration:**
  - Scripts rely on `gh sub-issue` by default and fail fast with installation instructions if the extension is missing (`gh extension install yahsan2/gh-sub-issue`).
  - Sync commands translate product-plan hierarchy into GitHub issues/sub-issues while recording real-time updates back into the plan.
- **Agent presets & helpers:**
  - Introduce Codex-focused agent profiles (planner, executor, test-runner) and optional command palette helpers to streamline local usage.

## Execution Phases

1. **Phase 0 – Baseline & design (✅ complete):**
   - Recorded this document and captured legacy behaviours for reference.
   - Logged the inventory of assets that must migrate before `.claude/` deletion.

2. **Phase 1 – Codex scaffolding (✅ complete):**
   - Created the `.codex/` directory structure with shared logging, time, GitHub, and plan helpers.
   - Authored the Central Time datetime rule and Codex-centric TDD rule.

3. **Phase 2 – Product-plan command suite (✅ complete):**
   - Implemented the `plan:*`, `epic:*`, `feature:*`, and `story:*` prompts/scripts aligned with the YAML hierarchy.
   - Added revision logging (`plan-meta.yaml`, `revisions.log`) and embedded scaffolding for new artifacts (no external templates).
   - Confirmed `.codex/product-plan/` as the live source of truth checked into the repo.

4. **Phase 3 – Context & operational tooling (✅ complete with follow-ups):**
   - Rebuilt context priming and operational status commands backed by the structured plan data.
   - Replaced the Claude test helper with `/testing:run`, added `/testing:red` + `/testing:refactor`, and ensured GitHub checks fail fast when prerequisites are missing.
   - Remaining tasks: expand foundation editors beyond the PRD (personas, strategy) and keep enhancing automated validation.

5. **Phase 4 – GitHub automation & Codex enhancements (🚧 in progress):**
   - `/ops:github-sync`, `/ops:github-pull`, `/ops:issue-*`, and `/ops:offline-queue` now align with the Codex hierarchy and timestamp rules.
   - Next steps: richer diff summaries, batch reporting, option cleanup, and optional agent/palette integrations.

6. **Phase 5 – Documentation & cleanup (✅ complete):**
   - README, COMMANDS, and migration notes now describe the Codex workflow.
   - Added foundation/GitHub reporting docs, codified removal steps, and removed the legacy Claude tree.

## Dependencies & Guardrails

- No deletion of `.claude/` until after Phases 1–4 are complete and validated.
- Gh-sub-issue dependency must be enforced uniformly before exposing sync commands.
- All new prompts/scripts must include explicit logging of real datetime stamps in Central Time when modifying artifacts.
- TDD guidance should integrate with existing test directories (e.g., `tests/logs/`) and remain language-agnostic.
- Any new automation must avoid interactive auth unless the user explicitly requests it.

## Next Steps

- Grow automated coverage (shell smoke + unit tests) around plan updates, GitHub sync diffing, and queue replay flows.
- Finalise the `.claude/` removal checklist, audit references in docs/prompts, and stage a regression test plan for deletion.
- Design multi-issue batching/report exports for `/ops:github-sync` once label management stabilises.

## Outstanding Parity Items

None. (Updated 2025-09-19 after verifying plan editors, GitHub sync reporting, and removal docs.)

## Upcoming GitHub Command Design

To replace the Claude `/pm:*` GitHub orchestration, Codex will introduce an `ops/github-*` suite that operates on the structured product plan:

- `ops/github-sync` (push mode)
  - Reads `.codex/product-plan/` hierarchy.
  - Creates/updates GitHub issues with `gh issue create` / `gh issue edit` and nests sub-issues via `gh sub-issue`.
  - Updates each epic/feature/story file with a `github:` block containing the issue number, last sync timestamp (Chicago time), and URL.
  - Writes audit entries to `.codex/product-plan/revisions.log` and `plan-meta.yaml` (`last_command = ops/github-sync`).
  - Requires `require_gh_sub_issue` before any network call.

- `ops/github-pull`
  - Fetches issue metadata (state, labels, assignees) for linked items.
  - Logs commentary deltas into `updates/` folders (mirroring the old Claude workflow but under `.codex/product-plan/epics/.../updates/`).
  - Updates story status fields so the plan reflects current progress.

- `ops/issue-start`
  - Given an issue ID, locates the linked plan artifact and records a start event.
  - Assigns the issue with `gh issue edit --add-assignee @me --add-label in-progress`.
  - Generates a work log under `.codex/product-plan/.../updates/issue-<id>/` with Central Time timestamps and notes for multi-agent coordination.

- `ops/issue-sync`
  - Posts progress comments from local update logs back to GitHub using `gh issue comment`.
  - Updates the plan artifact’s `progress` or `last_synced` fields to the current timestamp.

- `ops/issue-close`
  - Marks the story/feature as complete (frontmatter status = done, `date_closed` added).
  - Runs `gh issue close` and, if relevant, closes child sub-issues.

### Data model additions
- Each epic/feature/story YAML will gain optional keys:
  ```yaml
  github:
    issue: 1234
    url: "https://github.com/org/repo/issues/1234"
    last_synced: "2025-09-19 16:20:11 CT"
    last_status: "in_progress"
  ```
- Update commands will use the shared timestamp helper and append revision lines for traceability.

### Safety & sequencing
- All commands source `.codex/scripts/lib/init.sh` and bail early if `gh` or `gh-sub-issue` are unavailable.
- Before creating issues, scripts verify the repository remote differs from the upstream template (avoid polluting automaze repo).
- Sync commands operate in dry-run mode when `--preview` is passed, printing the planned issue hierarchy without executing `gh` calls.
- The product plan remains the source of truth; GitHub commands never mutate artifacts without also updating the corresponding YAML.

This design replaces the legacy `.claude/commands/pm/*` set while aligning with Codex CLI expectations and the structured product plan.

### Issue lifecycle commands (completed)
  - Added /ops:github-sync with preview-first behaviour (`--apply` drives GitHub writes), type filters, cached `--diff` comparisons against live issues, label management (`--add-label/--remove-label`), `--select` scoping, `--report` JSON exports, and `--local-only` plan-only updates (skipped creations recorded in `.codex/product-plan/offline-sync-queue.log`).
- Added /ops:offline-queue to inspect/export, replay (filters: `--epic`, `--type`, `--force`, `--prune`, `--report`), or clear the offline sync queue once connectivity returns.
- Added /ops:github-pull with preview/apply and `--local-only` support to refresh `github` metadata and append pull logs.
- Added /ops:issue-start, /ops:issue-sync, and /ops:issue-close to manage timestamps, logs, and per-issue status in `.codex/product-plan/`.
- All scripts share the new plan utilities (`plan_list_artifacts`, `plan_update_github_block`, `plan_record_revision`, `plan_find_artifact_by_issue`) to keep revision tracking consistent.
- Every GitHub interaction checks for `gh` and `gh-sub-issue`; `--local-only` flags allow offline operation during testing.
- Added unit coverage for offline GitHub preview/queue flows (`tests/unit/github_ops_test.sh`) to complement smoke coverage.

### Editing Commands (completed)
- Added `epic:update`, `feature:update`, and `story:update` to modify plan artifacts in place.
- Each update command increments `plan-meta.yaml.revision_count`, stamps Central Time, and appends to `revisions.log`.
- `story:update` rewrites the `acceptance_criteria` block using `--acceptance "ID|Given|When|Then"` arguments so empty placeholder rows are removed.
- `ops/status.sh` now inspects specific YAML fields (overview description, acceptance criteria) instead of string-matching generic `""` patterns, reducing false positives in data-quality flags.
- Added `/plan:personas-update` and `/plan:strategy-update` plus smoke (`tests/smoke/foundation_updates.sh`) and unit coverage (`tests/unit/foundation_test.sh`) to validate foundation merges.

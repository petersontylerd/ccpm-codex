# ccpm-codex

Spec-driven product management for Codex CLI. This fork evolves the original Claude Code PM workflow so Codex agents can plan, decompose, and ship features with full traceability while staying anchored to GitHub Issues.

- Structured product plan artifacts live under `.codex/product-plan/` with a 1:1 mapping of prompts to shell scripts.
- `gh` and the `gh-sub-issue` extension are first-class dependencies; every GitHub command checks for them before running.
- Real timestamps follow Central Time (America/Chicago) via the shared helpers in `.codex/scripts/lib/`.
- Test-driven development is enforced through rules, prompts, and the Codex test runner.


## Quick Start

```bash
# 1. Verify the product plan is ready (fails if `.codex/product-plan/` is missing)
/plan:init

# 2. Get a summary of the current plan state
/plan:status

# 2b. Update PRD metadata and goals as the plan evolves
/plan:prd-update --product-name "Codex PM" --project-code CPM-001 --summary "Spec-driven workflow for Codex CLI"

# 2c. Refresh personas and strategy from curated payloads
/plan:personas-update --input payloads/personas.yaml --note "Workshop sync"
/plan:strategy-update --input payloads/strategy.yaml
/plan:roadmap-update --input payloads/roadmap.yaml

# 3. Prime context for a new coding session
/context:prime

# 4. Inspect operational health and data-quality flags
/ops:status

# 5. Create new work items
/epic:new --name "Workflow Automation"
/feature:new --epic E004 --name "Agent Scheduler"
/story:new --epic E004 --feature F001 --name "Schedule parallel agents" --as "Project manager" --i-want "to assign agent workloads" --so-that "parallel tracks stay balanced"

# 6. Update acceptance criteria and metadata as work evolves
/story:update --epic E004 --feature F001 --story US0001 --acceptance "AC01|Agents assigned evenly|Scheduler distributes tasks|All agents get balanced workloads"

# 7. Run targeted tests while logging output
/testing:run -- pytest tests/unit --maxfail=1

# 8. Preview GitHub sync before creating issues
/ops:github-sync --preview

# 9. Kick off an issue locally
/ops:issue-start --issue 12345 --preview

# 10. Sync and close the issue when ready
/ops:issue-sync --issue 12345 --note "Ready for review" --preview
/ops:issue-close --issue 12345 --preview

# 11. Pull the latest GitHub metadata into the plan
/ops:github-pull --issue 12345 --preview --local-only

# 12. Review any offline sync queue entries (created when `--local-only` skips issue creation)
sed -n '1,5p' .codex/product-plan/offline-sync-queue.log
```

> **Tip:** `/ops:github-sync` runs in preview mode by default. Use `--diff` to compare local vs remote status, add/remove labels with the corresponding flags, and pass `--apply` when you're ready to create/update issues. Stick with preview (optionally `--local-only`) while testing offline.

## Directory Layout

```
.codex/
├── prompts/                 # Each prompt mirrors a shell script (plan/, epic/, feature/, story/, context/, ops/, testing/)
├── scripts/
│   ├── lib/                 # Shared helpers (logging, timestamps, gh checks)
│   ├── plan/                # plan:init, plan:status
│   ├── epic/                # epic:new, epic:update
│   ├── feature/             # feature:new, feature:update
│   ├── story/               # story:new, story:update
│   ├── context/             # context:prime
│   ├── ops/                 # ops:status (GitHub sync coming next)
│   └── testing/             # testing:run (TDD helper suite)
├── product-plan/            # Active plan state committed to the repo (plan:init validates it)
│   ├── foundation/          # PRD, personas, strategy, roadmap, etc.
│   └── epics/               # Epics → features → user stories + updates/
└── rules/                   # datetime.md, tdd.md, and future Codex rules
```

Every `.md` prompt calls its paired `.sh` script so Codex conversations and command-line usage stay aligned. Scripts source `.codex/scripts/lib/init.sh` to pick up logging, timestamp, and GitHub helpers.

## Product Plan Model

The plan is decomposed into three layers:

1. **Epics** (`.codex/product-plan/epics/epic-E###/epic-E###.yaml`)
   - Metadata (name, priority, facilitator)
   - Overview (description, personas, linked strategy IDs)
   - Dependencies and success criteria
2. **Features** (`.../feature-E###-F###/feature-E###-F###.yaml`)
   - Overview (description, user value, scope)
   - Dependencies and success criteria
3. **User Stories** (`.../user-story-E###-F###-US####.yaml`)
   - Story framing (`as_a`, `i_want`, `so_that`)
   - Acceptance criteria in Gherkin structure

When you run `epic:new`, `feature:new`, or `story:new`, the commands scaffold fresh YAML in place, stamp real timestamps, and log the change in `plan-meta.yaml` and `revisions.log`. Update commands (e.g., `story:update`) edit existing YAML fields and rewrite acceptance criteria blocks to eliminate the placeholder values in the generated skeleton.

Use `/plan:prd-update` to keep the foundation PRD aligned with the latest planning decisions—metadata, summary, and goal lists are all managed from that script with automatic revision logging.

Use `/plan:personas-update`, `/plan:strategy-update`, and `/plan:roadmap-update` to merge persona, strategy, and roadmap payloads into the plan. They support targeted replacements, removals by id, and journal every change so downstream automation stays in sync.
See `docs/foundation-updates.md` for payload patterns, command examples, and collaboration guardrails across the PRD, personas, strategy, and roadmap artifacts.

## Operational Status & Data Quality

Use `/ops:status` to surface progress indicators before you drop into code:

- Totals for epics, features, and user stories.
- Flags for missing epic names, blank feature descriptions, or stories without acceptance criteria.
- Latest revision entries so you can trace who changed what and when.

Behind the scenes, `ops/status.sh` parses the YAML structures and relies on the same timestamp helpers and revision log used by creation/update commands.

## Context Priming

`/context:prime` reads the product plan, revision log, and status summaries to produce a concise brief for Codex sessions. This replaces the legacy Claude prompts that generated `product-context.md`, `product-brief.md`, or `product-vision.md`; the authoritative context now lives in `.codex/product-plan/`.

## Testing & TDD

TDD is enforced via `.codex/rules/tdd.md` and the testing helper suite:

- `/testing:red` runs a targeted command expecting failure, confirming the red phase and journaling the result in `tests/logs/tdd-history.log`.
- `/testing:run` executes tests on demand, storing logs under `tests/logs/` with Central Time stamps (use `--no-log` to skip file output).
- `/testing:refactor` re-runs the suite expecting success, ensuring green/refactor phases are logged alongside any notes.

### Smoke Tests

Run these scripts to exercise the workflow end-to-end:

- `tests/smoke/github_workflow.sh` — plan status, diff preview, and offline queue inspection without touching GitHub (uses `--local-only`).
- `tests/smoke/tdd_helpers.sh` — sanity-check the red/green helpers with trivial commands.
- `tests/smoke/foundation_updates.sh` — exercises PRD, personas, strategy, and roadmap update commands against a temporary copy of the plan.

### Unit Tests

- `tests/unit/foundation_test.sh` — runs targeted assertions against the PRD, personas, strategy, and roadmap merge scripts using temporary backups. Requires `PyYAML` (install with `pip install pyyaml`).
- `tests/unit/github_ops_test.sh` — verifies `/ops:github-sync` preview output and offline queue JSON export without hitting GitHub.

## GitHub Integration

Codex now includes an initial GitHub workflow:

- `ops/github-sync` inspects the plan hierarchy and, by default, previews the GitHub issue tree. Pass `--apply` to create/update issues and sub-issues (requires `gh` + `gh-sub-issue`). Metadata is written back to each YAML artifact so `github.issue`, `last_synced`, and `last_status` stay current. Use `--diff` (now prefetches remote metadata for efficiency) to compare local status with the remote issue, and the label flags (`--add-label`, `--remove-label`). `--local-only` keeps changes to plan metadata only (new issues are skipped and recorded in `.codex/product-plan/offline-sync-queue.log`). Every run ends with diff + plan summaries so you can see create/update/blocked counts at a glance. Use `--select path` to scope the run to specific artifact keys (TYPE:EID:FID:SID) and `--report path` to emit a JSON summary for downstream automation (see `docs/github-reporting.md`).
- `ops/github-pull` refreshes local metadata from existing GitHub issues and appends structured log entries (`--local-only` keeps the operation offline).
- Manage the offline queue: `/ops:offline-queue --list` (view/export with `--export path`), `--replay` (with optional `--epic`, `--type`, `--force`, `--prune`, `--report path`), `--clear` (purge entries).
- `ops/issue-start` stamps a Central Time timestamp, writes to the local update log, updates the `github` block, and (optionally) assigns the issue with `gh issue edit`.
- `ops/issue-sync` appends progress notes, updates timestamps, and can post GitHub comments.
- `ops/issue-close` marks work as done, closes the issue (unless `--local-only`), and records the closure in the product plan.

Up next: richer sync options for `/ops/github-sync` (dry-run diffs across the whole plan, label management) and automation around multi-issue batching.

## Migration Status

| Area | Legacy Claude PM (archived) | Codex Status |
| --- | --- | --- |
| Product plan creation | PRD prompts under Claude PM package | Replaced by `plan:init`, `plan:status`, and YAML hierarchy under `.codex/product-plan/` |
| Context priming | Claude context primers generated markdown briefs | Replaced by `context:prime` reading plan artifacts |
| TDD guidance | Minimal guardrails | `.codex/rules/tdd.md` + `testing:*` helpers |
| GitHub sync | `/pm:epic-sync`, `/pm:issue-start` coordination | `ops/github-sync` (preview/diff/select/report), `ops/github-pull`, and `ops/issue-*` lifecycle commands implemented |
| Directory structure | Legacy Claude tree (removed) | `.codex/*` with 1:1 prompts/scripts |

The legacy Claude assets are removed from this repository; the migration history lives in `docs/archive/codex-migration.md`, and the removal steps are captured in `docs/archive/claude-removal-checklist.md`.

## Requirements

- Bash-compatible shell (Codex CLI default)
- `git`
- `gh` (GitHub CLI)
- `gh-sub-issue` extension (`gh extension install yahsan2/gh-sub-issue`)
- Python 3 (for YAML helpers) plus `PyYAML` (`pip install pyyaml`)

If any dependency is missing, the scripts surface actionable guidance and exit non-zero rather than attempting partial work.

## Contributing

1. Use `/context:prime` before starting new work to ground Codex in the current state.
2. Follow the TDD loop; capture logs with `/testing:run` and store them under `tests/logs/`.
3. Update the product plan via the provided `new`/`update` commands so data quality remains high.
4. Run `/ops:status` and `/plan:status` before syncing with GitHub to identify missing fields.
5. Document notable changes in `docs/archive/codex-migration.md` as we phase out `.claude/`.

## Removing the Legacy Claude Tree

We kept the original Claude assets checked in for historical reference until the migration checklist in `docs/archive/claude-removal-checklist.md` was complete. With parity reached, follow this workflow whenever you prune a downstream fork:

1. Confirm a search for `dot-claude` references only returns archival docs (no active prompts/scripts).
2. Take note of outstanding Claude artifacts to archive elsewhere if desired.
3. Delete the entire legacy Claude directory and update `.gitignore`, README, and any onboarding docs.
4. Run the full test suite (`tests/unit/*.sh`, `tests/smoke/*.sh`) to validate the removal.
5. Record the change in `docs/archive/codex-migration.md` and reference it in the commit message.

This section satisfies the checklist requirement so we have a single documented workflow when the final parity tasks are done.

---

Codex PM keeps multi-agent work grounded in specifications, enabling reliable handoffs between humans and Codex CLI while maintaining a clear audit trail in GitHub. Dive in, extend the command suite, and help us finish the GitHub integration phase.

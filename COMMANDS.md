# Codex Command Reference

Every Codex prompt in `.codex/prompts/` has a matching shell script in `.codex/scripts/`. This keeps conversations, local CLI usage, and automation in sync.

| Command | Prompt | Script | Purpose |
| --- | --- | --- | --- |
| `/ops:offline-queue` | `.codex/prompts/ops/offline-queue.md` | `.codex/scripts/ops/offline-queue.sh` | Inspect/export (`--export`), replay (filters: `--epic`, `--type`, `--force`, `--prune`, `--report`), or clear `.codex/product-plan/offline-sync-queue.log`. |
| `/plan:init` | `.codex/prompts/plan/init.md` | `.codex/scripts/plan/init.sh` | Validate the existing product plan, enforce `gh` + `gh-sub-issue`, and record a revision entry. |
| `/plan:status` | `.codex/prompts/plan/status.md` | `.codex/scripts/plan/status.sh` | Summarize product stats (epics, features, stories) plus revision data. |
| `/plan:prd-update` | `.codex/prompts/plan/prd-update.md` | `.codex/scripts/plan/prd-update.sh` | Update PRD metadata/overview fields, manage goal lists, and append revision entries. |
| `/plan:personas-update` | `.codex/prompts/plan/personas-update.md` | `.codex/scripts/plan/personas-update.sh` | Merge persona/buyer/influencer data by id/role and record revisions. |
| `/plan:strategy-update` | `.codex/prompts/plan/strategy-update.md` | `.codex/scripts/plan/strategy-update.sh` | Update strategic goals/choices/themes, commercialization notes, and log revisions. |
| `/plan:roadmap-update` | `.codex/prompts/plan/roadmap-update.md` | `.codex/scripts/plan/roadmap-update.sh` | Merge roadmap metadata, horizons, risks, and questions with revision logging. |
| `/context:prime` | `.codex/prompts/context/prime.md` | `.codex/scripts/context/prime.sh` | Prime a Codex session with plan highlights, revisions, and epics/feature snapshots. |
| `/ops:status` | `.codex/prompts/ops/status.md` | `.codex/scripts/ops/status.sh` | Show operational metrics and data-quality flags. |
| `/epic:new` | `.codex/prompts/epic/new.md` | `.codex/scripts/epic/new.sh` | Scaffold a new epic YAML with sequential IDs and revision logging. |
| `/epic:update` | `.codex/prompts/epic/update.md` | `.codex/scripts/epic/update.sh` | Edit existing epic metadata/overview fields. |
| `/feature:new` | `.codex/prompts/feature/new.md` | `.codex/scripts/feature/new.sh` | Add a feature under an epic (auto IDs, timestamping). |
| `/feature:update` | `.codex/prompts/feature/update.md` | `.codex/scripts/feature/update.sh` | Update feature overview metadata (description, user value, priority, facilitator). |
| `/story:new` | `.codex/prompts/story/new.md` | `.codex/scripts/story/new.sh` | Create a user story with full metadata and log the change. |
| `/story:update` | `.codex/prompts/story/update.md` | `.codex/scripts/story/update.sh` | Update story metadata and rewrite acceptance criteria using `--acceptance "ID|Given|When|Then"`. |
| `/testing:red` | `.codex/prompts/testing/red.md` | `.codex/scripts/testing/red.sh` | Run a targeted command expecting failure, confirm red phase, and journal the result. |
| `/testing:run` | `.codex/prompts/testing/run.md` | `.codex/scripts/testing/run.sh` | Execute tests, log output under `tests/logs/`, and stamp execution windows in Central Time. |
| `/testing:refactor` | `.codex/prompts/testing/refactor.md` | `.codex/scripts/testing/refactor.sh` | Verify the suite stays green during refactor/cleanup and journal the success. |
| `/ops:github-sync` | `.codex/prompts/ops/github-sync.md` | `.codex/scripts/ops/github-sync.sh` | Preview/apply GitHub updates with type filters, cached `--diff`, label add/remove flags, `--select` filtering, JSON `--report`, and `--local-only` plan-only updates (skips logged to `offline-sync-queue.log`). |
| `/ops:github-pull` | `.codex/prompts/ops/github-pull.md` | `.codex/scripts/ops/github-pull.sh` | Refresh plan metadata from existing GitHub issues (`--apply`, `--local-only`, `--note`, `--type`, `--epic`). |
| `/ops:issue-start` | `.codex/prompts/ops/issue-start.md` | `.codex/scripts/ops/issue-start.sh` | Mark an issue in progress, append to the local log, and optionally assign via GitHub. |
| `/ops:issue-sync` | `.codex/prompts/ops/issue-sync.md` | `.codex/scripts/ops/issue-sync.sh` | Record progress notes, refresh timestamps, and optionally comment on the GitHub issue. |
| `/ops:issue-close` | `.codex/prompts/ops/issue-close.md` | `.codex/scripts/ops/issue-close.sh` | Close the issue, set local status to `done`, and log completion details. |

## Upcoming GitHub Enhancements

- Richer sync options for `/ops:github-sync` (plan-level diffs, label management) and automation around multi-issue batching.

See [docs/archive/codex-migration.md](docs/archive/codex-migration.md#upcoming-github-command-design) for ongoing roadmap notes.

## Usage Notes

- Each script sources `.codex/scripts/lib/init.sh` to pick up logging, timestamp, and GitHub helpers.
- All timestamps are Central Time (`America/Chicago`) via `get_chicago_timestamp`.
- GitHub commands fail fast if `gh` or `gh-sub-issue` are missing and provide installation guidance.
- Running commands via the CLI or Codex prompt produce identical output, making it easy to script workflows or share logs in PRs/issues.

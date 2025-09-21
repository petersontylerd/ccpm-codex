# Repository Guidelines

## Project Structure & Module Organization
- `.codex/prompts/` mirrors `.codex/scripts/` using hyphenated filenames (e.g., `ccpm-init-plan.md` ↔ `plan/init.sh`); each script sources `.codex/scripts/lib/init.sh` for logging, timestamps, and GitHub checks.
- `.codex/scripts/ops/prompts-sync.sh` copies the repo prompts into `~/.codex/prompts/ccpm-*` so the Codex CLI can see them; run it after changing prompts (or rerun `/plan:init`).
- `.codex/product-plan/` stores the YAML hierarchy (`epic-E###/feature-E###-F###/user-story-E###-F###-US####.yaml`) plus `foundation/` PRD assets.
- `.codex/rules/` enforces Central Time logging and TDD expectations; `docs/` captures migration notes and process history.
- `tests/` splits into `unit/` (bash wrappers around Python helpers) and `smoke/` end-to-end suites; command output lands in `tests/logs/`.

## Build, Test, and Development Commands
- `/plan:init` validates the product-plan footprint and halts when required files are missing.
- `/context:prime` summarizes product metadata before you begin coding.
- `/testing:red -- pytest tests/unit --maxfail=1`, `/testing:run -- pytest tests/unit --maxfail=1`, and `/testing:refactor` keep the red → green → refactor journal current.
- `bash tests/smoke/github_workflow.sh` exercises GitHub-sync paths offline; `bash tests/smoke/tdd_helpers.sh` sanity-checks the testing prompts.

## Coding Style & Naming Conventions
- Bash scripts start with `#!/bin/bash` and `set -euo pipefail`, use two-space indentation, and prefer lowercase `snake_case` helpers; keep comments focused on intent.
- YAML stays two-space indented with stable keys; directory prefixes (`epic-`, `feature-`, `user-story-`) must remain for automation to resolve artifacts.
- Prompt and script filenames stay paired (`.codex/prompts/ccpm-verb-noun.md` ↔ `.codex/scripts/group/command.sh`) so CLI and agent workflows mirror each other.

## Testing Guidelines
- Unit runners (e.g., `tests/unit/foundation_test.sh`) require `python3` plus `PyYAML`; install via `pip install pyyaml` when needed.
- Run smoke suites after touching plan sync or TDD helpers and archive their output under `tests/logs/`.
- Document every red/green/refactor cycle with the `/testing:*` prompts so `tests/logs/tdd-history.log` remains authoritative.

## Commit & Pull Request Guidelines
- Follow the existing short, sentence-case subject style (`Overhaul with Codex CLI`); add scoped prefixes only when they clarify impact.
- Reference related issue IDs, list the `/testing:*` flows executed, and attach relevant log snippets or screenshots for behavioral changes.
- PRs should summarize impact on the product plan or CLI surface area and confirm updates were applied via the correct `.codex` prompts.

## Agent-Specific Practices
- Source `.codex/scripts/lib/init.sh` in new helpers to inherit logging, Central Time stamping, and GitHub guards.
- Prefer sub-agent prompts for verbose operations and close the loop by updating the product plan so downstream sessions stay in sync.
- Lean on MCP servers when it sharpens the workflow: use `sequential-thinking` for complex planning, `context7` to fetch external docs, and `memory` to persist observations other agents should reuse.

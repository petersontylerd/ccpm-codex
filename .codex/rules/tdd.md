# Test-Driven Development Rule

Codex workflows must follow a disciplined Red → Green → Refactor loop for all feature work. The goal is to keep changes focused, covered, and easy to review.

## Core Expectations
1. **Write a failing test first** that captures the desired behaviour or regression.
2. **Run the targeted test** (or suite) and confirm it fails for the expected reason.
3. **Implement the minimum code** needed to make the new test pass.
4. **Re-run relevant tests** until the suite is green.
5. **Refactor** to improve structure while keeping tests green.
6. **Log results** to `tests/logs/` when running larger suites so teammates can inspect outcomes without rerunning locally.

## Recommended Commands
These commands will land in upcoming phases:
- `/testing:red` – scaffold a failing test case.
- `/testing:run` – execute a targeted test or suite (wraps `.codex/scripts/testing/run.sh`).
- `/testing:refactor` – summarize refactor steps and confirm all tests stay green.

## Implementation Guidelines
- Keep tests deterministic and isolated; avoid external dependencies where possible.
- Prefer the smallest executable test target (`pytest` node, Jest test name, etc.).
- When a bug is found, reproduce it with a test before changing production code.
- Capture logs via `tests/logs/<test_name>.log` using the shared helper script (to be added under `.codex/scripts/testing/`).
- Document notable test additions or behavioural changes in the associated product plan entry.

## Tooling Requirements
- If the project lacks a testing framework, note it in status updates and propose how to add one before writing production code.
- Testing helpers must exit non-zero when tests fail so calling commands can stop the workflow.
- All scripts should source `.codex/scripts/lib/init.sh` to access logging and timestamp utilities when reporting test results.

## Exceptions
- Hotfixes without a failing test are strongly discouraged. If unavoidable, record the reason in the product plan and schedule follow-up tests.
- Exploratory spikes may skip TDD temporarily but must include a clean-up issue that restores full coverage.

Adhering to this rule keeps Codex work predictable, reviewable, and safe to parallelise.

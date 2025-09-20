# Foundation Artifact Updates

Codex commands manage the structured product-plan foundations (PRD, personas, strategy, roadmap) by merging curated YAML payloads into the live plan and recording audit logs. This guide outlines recommended workflows and payload shapes so multiple contributors can collaborate safely.

## Workflow Overview

1. Create a payload file (keep it under `payloads/` or `tmp/`) with only the fields you intend to change.
2. Run the corresponding `/plan:*` command, passing `--input` and any optional flags.
3. Review stdout for the summary string and confirm a revision entry was added to `.codex/product-plan/revisions.log`.
4. Commit both the payload (if it belongs in version control) and the updated plan artifacts.

Each command enforces Central Time timestamping via `plan_record_revision`, so you automatically capture `last_updated` and an audit trail.

## PRD Updates

Use `/plan:prd-update` for metadata and top-level goal lists. Example payload (inline via CLI):

```bash
/plan:prd-update \
  --product-name "Codex PM" \
  --project-code CPM-001 \
  --summary "Spec-driven workflow for Codex CLI" \
  --goal "Codex agents stay anchored to an audited plan" \
  --success-metric "Plan/GitHub parity verified on every sync"
```

Flags support appending values (`--goal`, `--success-metric`, etc.), clearing lists before writing (`--reset-goals`), and annotating revisions (`--note "planning session"`).

## Personas Updates

`/plan:personas-update` merges persona, buyer, influencer, and open-question data. Payload snippet:

```yaml
metadata:
  project_code: CCPM-CODEX
  product_name: Codex PM for CLI
primary_personas:
  - id: P-01
    name: AI Project Manager
    role: Product Lead
    goals:
      - Coordinate Codex & human workflows
buyers:
  - role: CTO
    decision_criteria:
      - Integration effort
      - Security posture
```

Command usage:

```bash
/plan:personas-update --input payloads/personas.yaml --note "Persona workshop"
```

Options support:
- `--replace-section primary_personas` to overwrite a list entirely.
- `--remove secondary_personas:P-LEGACY` to drop a persona by id.
- Automatic cleanup of placeholder rows with blank ids/roles.

## Strategy Updates

`/plan:strategy-update` covers strategic goals, choices, themes, commercialization notes, risks, and open questions.

Example payload:

```yaml
strategic_goals:
  - id: SG-01
    description: Maintain spec-driven parity between plan and GitHub
    time_horizon: short-term
strategic_choices:
  do:
    - id: C-DO-02
      description: Batch GitHub sync reports
      rationale: Reduce manual comparisons
```

Command usage:

```bash
/plan:strategy-update --input payloads/strategy.yaml --replace-section strategic_choices.do
```

Supported flags:
- `--replace-section strategic_choices.do` or `strategic_goals` for full overwrite.
- `--remove strategic_themes:THEME-OLD` to drop items by id.

## Roadmap Updates

`/plan:roadmap-update` curates time horizons (goals, themes, milestones) alongside roadmap risks and open questions.

Example payload:

```yaml
time_horizons:
  short_term:
    goals:
      - SG-01
    milestones:
      - id: M-01
        description: Validate Codex PM MVP roll-out
        key_outcome: Internal stakeholders using Codex PM
risks_assumptions:
  - id: RM-01
    description: GitHub automation gaps slow delivery
    mitigation: Expand smoke coverage
open_questions:
  - id: Q-01
    question: Do we need a roadmap horizon for partner integrations?
    blocking: false
```

Command usage:

```bash
/plan:roadmap-update --input payloads/roadmap.yaml --replace-section short_term.milestones
```

Supported flags:
- `--replace-section short_term.milestones` (or `mid_term.*`, `long_term.*`) to overwrite list data.
- `--remove short_term.milestones:M-OLD` or `risks_assumptions:RM-LEGACY` to prune by id.
- `--note` to attach planning context to the revision log.

## Tips & Guardrails

- Keep payloads small and focused; only include fields that should change.
- Store reusable payloads under version control; temporary experiments can stay in `tmp/` and be gitignored.
- Use `--note` to describe the workshop/meeting driving the update—this appears in `revisions.log`.
- PyYAML (`pip install pyyaml`) must be available for the merge scripts. Install it once per environment.
- Run `tests/smoke/github_workflow.sh` after significant updates to confirm there are no downstream regressions.
- Use `tests/smoke/foundation_updates.sh` to exercise PRD/persona/strategy/roadmap commands against a temporary copy of the plan; it restores the original state automatically.
- Run `tests/unit/foundation_test.sh` for fast assertions that each merge command behaves correctly (requires `PyYAML`).

By standardising payload formats and commands, Codex CLI users can iterate on foundational artifacts without clobbering each other’s work.

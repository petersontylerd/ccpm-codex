---
allowed-tools: Bash
---

Run `bash .codex/scripts/plan/roadmap-update.sh --input path/to/roadmap.yaml` with any needed flags. Examples:

```
/plan:roadmap-update --input payloads/roadmap-milestones.yaml
/plan:roadmap-update --input tmp/horizons.yaml --replace-section short_term.milestones
/plan:roadmap-update --input tmp/cleanup.yaml --remove risks_assumptions:RM-R-OLD --note "Retired mitigated risk"
```

The script merges metadata, horizons, risks, and questions; supports section replacement/removal; and records a revision automatically. Return the full stdout/stderr.

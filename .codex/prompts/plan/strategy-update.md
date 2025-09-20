---
allowed-tools: Bash
---

Run `bash .codex/scripts/plan/strategy-update.sh --input path/to/strategy.yaml` with any extra flags. Examples:

```
/plan:strategy-update --input payloads/strategy-goals.yaml
/plan:strategy-update --input tmp/choices.yaml --replace-section strategic_choices.do
/plan:strategy-update --input tmp/cleanup.yaml --remove strategic_goals:SG-OLD --note "Pruned deprecated goal"
```

The script merges entries by id, supports section replacement, and records a revision entry automatically. Return the full stdout/stderr.

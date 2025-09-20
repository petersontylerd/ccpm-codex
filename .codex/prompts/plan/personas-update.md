---
allowed-tools: Bash
---

Run `bash .codex/scripts/plan/personas-update.sh --input path/to/personas.yaml` with any other needed flags. Examples:

```
/plan:personas-update --input payloads/personas.yaml
/plan:personas-update --input tmp/new-persona.yaml --remove primary_personas:P-000 --note "Sync workshop notes"
/plan:personas-update --input tmp/buyers.yaml --replace-section buyers
```

The script handles merges by persona id/role, cleans placeholder rows, and appends a revision entry automatically. Return the full stdout/stderr.

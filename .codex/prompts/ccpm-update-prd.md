---
allowed-tools: Bash
---

Run `bash .codex/scripts/plan/prd-update.sh` with the desired flags. Examples:

```
/plan:prd-update --product-name "Codex PM" --project-code CPM-001 --summary "Workflow orchestration for Codex CLI"
/plan:prd-update --goal "Codex agents stay in sync via product plan" --success-metric "Zero drift between plan and GitHub" --note "Initial planning pass"
/plan:prd-update --reset-goals --goal "Ship Codex-centric workflow" --goal "Document PRD revisions"
```

The script appends a revision entry automatically, so return its full stdout/stderr.

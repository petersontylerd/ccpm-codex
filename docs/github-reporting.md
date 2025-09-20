# GitHub Sync Reporting & Filtering

`/ops:github-sync` produces a clear preview/apply log by default, but complex workflows often need machine-readable summaries. This guide explains how to scope sync runs and capture structured output.

## Select Mode (`--select`)

Supply a plaintext file where each line identifies an artifact key:

```
TYPE:EID:FID:SID
```

Examples:

```
EPIC:E004::
FEATURE:E004:F001:
STORY:E004:F001:US0001
```

Any combination of empty segments is allowed; use `::` when the artifact has no feature/user story. Lines may include inline comments (`# ...`) or blank spacing—they are ignored during parsing.

Run the command with:

```bash
/ops:github-sync --preview --select tmp/scope.txt --local-only
```

Only artifacts matching the listed keys are processed. When a select file is present, the JSON report includes a `selected_filter` field pointing to the file.

## Report Mode (`--report`)

Pass a destination path to store a JSON summary:

```bash
/ops:github-sync --preview --type STORY --select tmp/scope.txt --report tmp/report.json
```

The JSON schema:

```json
{
  "mode": "preview",
  "repository": "owner/repo" | null,
  "plan_summary": "create=1 update=0 blocked=0 total=1",
  "counts": {"created":0,"updated":0,"failed":0,"skipped":0},
  "planned": {"create":1,"update":0,"blocked":0},
  "diff": {"changes":0,"in_sync":1,"skipped":0},
  "selected_filter": "tmp/scope.txt", // optional
  "operations": [
    {
      "type": "STORY",
      "epic": "E004",
      "feature": "F001",
      "story": "US0001",
      "planned_action": "update",
      "result": "diff-in-sync",
      "issue": "12345",
      "status": "in_progress",
      "url": "https://github.com/org/repo/issues/12345",
      "parent_issue": "6789",
      "name": "Schedule parallel agents",
      "key": "STORY:E004:F001:US0001"
    }
  ]
}
```

`result` values reflect the branch taken (`created`, `updated`, `skipped-local`, `blocked-parent`, `diff-*`). Each run includes aggregated counts for quick dashboards. Combine the report with `jq` or custom tooling to generate status pages or Slack digests.

## Tips

- Use `--local-only` during dry runs to avoid GitHub writes while still generating reports.
- Select files and reports are regular text; store them under `tmp/` (gitignored) during experimentation.
- Pair the report with automated unit checks (`tests/unit/github_ops_test.sh`) when extending the sync command.

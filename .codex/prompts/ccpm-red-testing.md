---
allowed-tools: Bash
---

Run `bash .codex/scripts/testing/red.sh` with the red-phase test command. Example:

```
/testing:red -- pytest tests/unit/test_api.py::test_returns_error
```

Return the command's full stdout/stderr so the journal entry is visible.

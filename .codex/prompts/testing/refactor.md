---
allowed-tools: Bash
---

Run `bash .codex/scripts/testing/refactor.sh` with the green/refactor test command. Example:

```
/testing:refactor -- pytest tests/unit/test_api.py::test_returns_error
```

Return the full stdout/stderr so TDD journal updates are captured.

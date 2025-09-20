# Real-Time Timestamp Rule (Chicago)

All Codex commands that write to the product plan, logs, or context files **must use the actual current time in Chicago (America/Chicago)** with second precision. Placeholder values or estimates are not allowed.

## Required Format
- Pattern: `YYYY-MM-DD HH:MM:SS CT`
- Example: `2024-03-21 14:05:33 CT`
- The trailing `CT` explicitly marks Central Time.

## How to Get the Timestamp
Use the shared helper in `.codex/scripts/lib/time.sh`:

```bash
# Load common helpers (recommended at the top of scripts)
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/init.sh
source "${SCRIPT_ROOT}/../lib/init.sh"

now="$(get_chicago_timestamp)"  # e.g., 2024-03-21 14:05:33 CT
```

If you only need the helper directly:

```bash
# shellcheck source=.codex/scripts/lib/time.sh
source "$(git rev-parse --show-toplevel)/.codex/scripts/lib/time.sh"
now="$(get_chicago_timestamp)"
```

## Implementation Guidelines
1. Fetch the timestamp immediately before writing any file so it reflects the real write time.
2. Preserve existing `created` values; only update `updated`/`last_modified` fields when modifying records.
3. Record all audit log entries (e.g., plan revisions, sync operations) with this Chicago timestamp.
4. When commands output status to the user, include the timestamp so humans can correlate changes.

## Fallback Expectations
- The helper first uses the system `date` command with `TZ="America/Chicago"`.
- If `date` is unavailable, it falls back to Python (`python3` or `python`).
- If none of these tools exist, the script must stop and inform the user that real timestamps cannot be generated.

## Priority
This is a **must-follow rule**. Any command that cannot capture the real timestamp must abort with a clear error message instead of continuing with placeholders.

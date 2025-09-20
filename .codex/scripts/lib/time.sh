#!/bin/bash

# Provide minimal logging fallback if not already sourced.
if ! command -v log_error >/dev/null 2>&1; then
  log_error() {
    printf '[ERROR] %s\n' "$1" 1>&2
  }
fi

# Returns current timestamp in America/Chicago with second precision.
get_chicago_timestamp() {
  local ts
  if command -v date >/dev/null 2>&1; then
    ts=$(TZ="America/Chicago" date '+%Y-%m-%d %H:%M:%S')
  else
    if command -v python3 >/dev/null 2>&1; then
      ts=$(python3 - <<'PYTHON'
from datetime import datetime
from zoneinfo import ZoneInfo
print(datetime.now(ZoneInfo('America/Chicago')).strftime('%Y-%m-%d %H:%M:%S'))
PYTHON
)
    elif command -v python >/dev/null 2>&1; then
      ts=$(python - <<'PYTHON'
from datetime import datetime
try:
    from zoneinfo import ZoneInfo
    tz = ZoneInfo('America/Chicago')
except Exception:
    from datetime import timezone, timedelta
    tz = timezone(timedelta(hours=-6))
print(datetime.now(tz).strftime('%Y-%m-%d %H:%M:%S'))
PYTHON
)
    else
      log_error 'No suitable time provider available (date or python).' 
      return 1
    fi
  fi
  printf '%s CT' "$ts"
}

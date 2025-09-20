#!/bin/bash

# Ensure logging helpers exist when sourced directly.
if ! command -v log_info >/dev/null 2>&1; then
  log_info() { printf '[INFO] %s\n' "$1"; }
fi
if ! command -v log_error >/dev/null 2>&1; then
  log_error() { printf '[ERROR] %s\n' "$1" 1>&2; }
fi

require_gh_cli() {
  if ! command -v gh >/dev/null 2>&1; then
    log_error 'GitHub CLI (gh) is required for this command.'
    log_info 'Install instructions: https://cli.github.com/'
    return 1
  fi
}

require_gh_sub_issue() {
  require_gh_cli || return 1
  if ! gh extension list 2>/dev/null | grep -q 'yahsan2/gh-sub-issue'; then
    log_error 'gh-sub-issue extension is required but not installed.'
    log_info 'Install with: gh extension install yahsan2/gh-sub-issue'
    return 1
  fi
}

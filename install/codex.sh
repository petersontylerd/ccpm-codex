#!/bin/bash
set -euo pipefail

REPO_URL="${CCPM_CODEX_REPO_URL:-https://github.com/automazeio/ccpm-codex.git}"
REPO_REF="${CCPM_CODEX_REPO_REF:-main}"
include_docs=false
include_tests=false
force_overwrite=false
show_help=false

usage() {
  cat <<'USAGE'
Usage: bash codex.sh [options]

Options:
  --repo URL          Source repository URL (default: https://github.com/automazeio/ccpm-codex.git)
  --ref REF           Git ref to check out (default: main)
  --include-docs      Copy the docs/ directory in addition to .codex assets
  --include-tests     Copy the tests/ directory in addition to .codex assets
  --force             Overwrite existing files instead of stopping
  -h, --help          Show this help message

Environment variables:
  CCPM_CODEX_REPO_URL Override the repository URL
  CCPM_CODEX_REPO_REF Override the git ref
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      if [[ $# -lt 2 ]]; then
        printf 'Error: --repo requires a value.\n' >&2
        exit 1
      fi
      REPO_URL="$2"
      shift 2
      ;;
    --ref)
      if [[ $# -lt 2 ]]; then
        printf 'Error: --ref requires a value.\n' >&2
        exit 1
      fi
      REPO_REF="$2"
      shift 2
      ;;
    --include-docs)
      include_docs=true
      shift
      ;;
    --include-tests)
      include_tests=true
      shift
      ;;
    --force)
      force_overwrite=true
      shift
      ;;
    -h|--help)
      show_help=true
      shift
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac

done

if [[ "$show_help" == true ]]; then
  usage
  exit 0
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Error: %s is required but is not available in PATH.\n' "$1" >&2
    exit 1
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ -e "$dest" && "$force_overwrite" == false ]]; then
    printf 'Skipping %s (%s already exists). Use --force to overwrite.\n' "$label" "$dest"
    return
  fi

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  printf 'Installed %s -> %s\n' "$label" "$dest"
}

copy_dir() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [[ -e "$dest" && "$force_overwrite" == false ]]; then
    printf 'Error: %s already exists at %s. Move it aside or run with --force.\n' "$label" "$dest" >&2
    exit 1
  fi

  rm -rf "$dest"
  cp -R "$src" "$dest"
  printf 'Installed %s -> %s\n' "$label" "$dest"
}

require_command git
require_command mktemp

if [[ "$OSTYPE" == darwin* ]]; then
  tmp_dir="$(mktemp -d -t ccpm-codex)"
else
  tmp_dir="$(mktemp -d)"
fi

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

printf 'Fetching ccpm-codex assets from %s (%s) ...\n' "$REPO_URL" "$REPO_REF"

git clone --depth=1 --branch "$REPO_REF" "$REPO_URL" "$tmp_dir/repo" >/dev/null 2>&1

repo_root="$tmp_dir/repo"
rm -rf "$repo_root/.git"

copy_dir "$repo_root/.codex" ".codex" ".codex"
copy_file "$repo_root/COMMANDS.md" "COMMANDS.md" "COMMANDS.md"
copy_file "$repo_root/AGENTS.md" "AGENTS.md" "AGENTS.md"

if [[ "$include_docs" == true ]]; then
  copy_dir "$repo_root/docs" "docs" "docs"
fi

if [[ "$include_tests" == true ]]; then
  copy_dir "$repo_root/tests" "tests" "tests"
fi

cat <<'NEXT'

✅ Codex PM assets installed.

Next steps:
  • Run /plan:init to validate the product plan footprint.
  • Run /context:prime to generate the current project brief.
  • Use /ops:status to confirm data quality before coding.
NEXT


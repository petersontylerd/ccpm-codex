#!/bin/bash
set -euo pipefail

shopt -s nullglob

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
fi

PROMPT_SOURCE="$REPO_ROOT/.codex/prompts"
DEST_DIR="$HOME/.codex/prompts"

# shellcheck source=../lib/init.sh
source "$SCRIPT_DIR/../lib/init.sh"

log_info "Syncing Codex prompts to $DEST_DIR"

mkdir -p "$DEST_DIR"

source_files=("$PROMPT_SOURCE"/ccpm-*.md)
if [ ${#source_files[@]} -eq 0 ]; then
  log_warn "No ccpm-*.md prompts found in $PROMPT_SOURCE; nothing to sync."
  exit 0
fi

declare -A source_map
for src_path in "${source_files[@]}"; do
  base_name=$(basename "$src_path")
  source_map["$base_name"]=1
done

existing_dest=("$DEST_DIR"/ccpm-*.md)
for dest_path in "${existing_dest[@]}"; do
  dest_base=$(basename "$dest_path")
  if [[ -z "${source_map[$dest_base]+x}" ]]; then
    log_info "Removing stale prompt $dest_base"
    rm -f "$dest_path"
  fi
done

for src_path in "${source_files[@]}"; do
  base_name=$(basename "$src_path")
  log_info "Copying $base_name"
  cp "$src_path" "$DEST_DIR/$base_name"
  chmod 644 "$DEST_DIR/$base_name"
done

log_info "Prompt sync complete"

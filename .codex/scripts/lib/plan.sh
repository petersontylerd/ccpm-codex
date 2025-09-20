#!/bin/bash

plan_dir_default() {
  if [ -n "${REPO_ROOT:-}" ]; then
    printf '%s/.codex/product-plan' "$REPO_ROOT"
  else
    git rev-parse --show-toplevel 2>/dev/null | sed 's;$;/.codex/product-plan;'
  fi
}

plan_list_artifacts() {
  local plan_dir
  plan_dir=$(plan_dir_default)
  [ -n "$1" ] && plan_dir="$1"
  python3 - "$plan_dir" <<'PY'
from pathlib import Path
import base64
import re
import sys

plan_dir = Path(sys.argv[1])

def b64(s):
    return base64.b64encode(s.encode('utf-8')).decode('ascii') if s else ''

def parse_block(text, key):
    m = re.search(rf'{key}:\s*"([^"]*)"', text)
    return m.group(1).strip() if m else ''

def parse_github(text):
    block = {'issue': '', 'url': '', 'last_synced': '', 'last_status': ''}
    m = re.search(r'github:\n((?:  .+\n)+)', text)
    if not m:
        return block
    for line in m.group(1).splitlines():
        if ':' not in line:
            continue
        key, value = line.strip().split(':', 1)
        block[key.strip()] = value.strip().strip('"')
    return block

def emit(type_, epic_id, feature_id, story_id, name, description, path, github):
    line = [
        type_,
        epic_id or '',
        feature_id or '',
        story_id or '',
        b64(name or ''),
        b64(description or ''),
        str(path),
        github.get('issue', ''),
        github.get('url', ''),
        github.get('last_status', ''),
        github.get('last_synced', ''),
    ]
    print('|'.join(line))

for epic_dir in sorted(plan_dir.glob('epics/epic-*')):
    epic_file = epic_dir / f"{epic_dir.name}.yaml"
    if not epic_file.exists():
        continue
    text = epic_file.read_text()
    epic_id = parse_block(text, 'epic_id') or epic_dir.name.split('-', 1)[-1]
    epic_name = parse_block(text, 'epic_name')
    overview_desc = parse_block(text, 'description')
    github = parse_github(text)
    emit('EPIC', epic_id, '', '', epic_name, overview_desc, epic_file, github)

    features_root = epic_dir / f"features-{epic_id}"
    if not features_root.exists():
        continue
    for feature_dir in sorted(features_root.glob(f'feature-{epic_id}-*')):
        feature_file = feature_dir / f"{feature_dir.name}.yaml"
        if not feature_file.exists():
            continue
        text = feature_file.read_text()
        feature_id = parse_block(text, 'feature_id') or feature_dir.name.split('-')[-1]
        feature_name = parse_block(text, 'feature_name')
        feature_desc = parse_block(text, 'description')
        github = parse_github(text)
        emit('FEATURE', epic_id, feature_id, '', feature_name, feature_desc, feature_file, github)

        stories_root = feature_dir / f"user-stories-{epic_id}-{feature_id}"
        if not stories_root.exists():
            continue
        for story_file in sorted(stories_root.glob(f'user-story-{epic_id}-{feature_id}-US*.yaml')):
            text = story_file.read_text()
            story_id = parse_block(text, 'user_story_id') or story_file.stem.split('-')[-1]
            story_name = parse_block(text, 'user_story_name')
            story_desc = parse_block(text, 'description')
            github = parse_github(text)
            emit('STORY', epic_id, feature_id, story_id, story_name, story_desc, story_file, github)
PY
}

plan_update_github_block() {
  local file=$1
  local issue=$2
  local url=$3
  local status=$4
  local timestamp=$5
  python3 - "$file" "$issue" "$url" "$status" "$timestamp" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
issue, url, status, timestamp = sys.argv[2:6]
text = path.read_text()
block = [
    'github:',
    f'  issue: {issue}',
    f'  url: "{url}"',
    f'  last_synced: "{timestamp}"',
    f'  last_status: "{status}"',
]
block_text = '\n'.join(block) + '\n'
pattern = re.compile(r'^github:\n(?:  .+\n)+', re.MULTILINE)
if pattern.search(text):
    text = pattern.sub(block_text, text, count=1)
else:
    metadata_match = re.search(r'^\s*$', text, re.MULTILINE)
    if metadata_match:
        pos = metadata_match.start()
        text = text[:pos] + block_text + '\n' + text[pos:]
    else:
        text = text.rstrip() + '\n\n' + block_text
path.write_text(text)
PY
}

plan_record_revision() {
  local command=$1
  local message=$2
  local plan_dir
  plan_dir=$(plan_dir_default)
  local meta_file="$plan_dir/plan-meta.yaml"
  local log_file="$plan_dir/revisions.log"
  local ts
  ts=$(get_chicago_timestamp)
  local initialized_at initialized_by revision_count
  if [ -f "$meta_file" ]; then
    initialized_at=$(awk -F'"' '/initialized_at:/ {print $2; exit}' "$meta_file")
    initialized_by=$(awk -F'"' '/initialized_by:/ {print $2; exit}' "$meta_file")
    revision_count=$(awk -F':' '/revision_count:/ {gsub(/ /,"",$2); print $2; exit}' "$meta_file")
  fi
  initialized_at=${initialized_at:-$ts}
  initialized_by=${initialized_by:-plan:init}
  revision_count=${revision_count:-0}
  revision_count=$((revision_count + 1))
  cat > "$meta_file" <<EOF_META
initialized_at: "$initialized_at"
initialized_by: "$initialized_by"
last_updated: "$ts"
last_command: "$command"
revision_count: $revision_count
EOF_META
  printf '%s | %s | %s\n' "$ts" "$command" "$message" >> "$log_file"
  printf '%s' "$ts"
}

plan_find_artifact_by_issue() {
  local issue=$1
  local plan_dir
  plan_dir=$(plan_dir_default)
  python3 - "$plan_dir" "$issue" <<'PY'
from pathlib import Path
import re
import sys

plan_dir = Path(sys.argv[1])
target = sys.argv[2]

def parse_block(text, key):
    m = re.search(rf'{key}:\s*"([^"]*)"', text)
    return m.group(1).strip() if m else ''

def parse_github(text):
    m = re.search(r'github:\n((?:  .+\n)+)', text)
    if not m:
        return None
    info = {}
    for line in m.group(1).splitlines():
        if ':' not in line:
            continue
        key, value = line.strip().split(':', 1)
        info[key.strip()] = value.strip().strip('"')
    return info

def emit(type_, epic, feature, story, path, name):
    print('|'.join([
        type_,
        epic or '',
        feature or '',
        story or '',
        str(path),
        name or '',
    ]))

for epic_dir in plan_dir.glob('epics/epic-*'):
    epic_file = epic_dir / f"{epic_dir.name}.yaml"
    if not epic_file.exists():
        continue
    text = epic_file.read_text()
    github = parse_github(text)
    epic_id = parse_block(text, 'epic_id') or epic_dir.name.split('-', 1)[-1]
    epic_name = parse_block(text, 'epic_name')
    if github and github.get('issue') == target:
        emit('EPIC', epic_id, '', '', epic_file, epic_name)
        raise SystemExit
    features_root = epic_dir / f"features-{epic_id}"
    if not features_root.exists():
        continue
    for feature_dir in features_root.glob(f'feature-{epic_id}-*'):
        feature_file = feature_dir / f"{feature_dir.name}.yaml"
        if not feature_file.exists():
            continue
        text = feature_file.read_text()
        github = parse_github(text)
        feature_id = parse_block(text, 'feature_id') or feature_dir.name.split('-')[-1]
        feature_name = parse_block(text, 'feature_name')
        if github and github.get('issue') == target:
            emit('FEATURE', epic_id, feature_id, '', feature_file, feature_name)
            raise SystemExit
        stories_root = feature_dir / f"user-stories-{epic_id}-{feature_id}"
        if not stories_root.exists():
            continue
        for story_file in stories_root.glob(f'user-story-{epic_id}-{feature_id}-US*.yaml'):
            text = story_file.read_text()
            github = parse_github(text)
            story_id = parse_block(text, 'user_story_id') or story_file.stem.split('-')[-1]
            story_name = parse_block(text, 'user_story_name')
            if github and github.get('issue') == target:
                emit('STORY', epic_id, feature_id, story_id, story_file, story_name)
                raise SystemExit
PY
}

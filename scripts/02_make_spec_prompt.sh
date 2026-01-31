#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: 02_make_spec_prompt.sh <task-dir>\n' >&2
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

if [ "$#" -gt 1 ]; then
  usage
  exit 2
fi

task_dir="${1%/}"

if [ ! -d "$task_dir" ]; then
  printf 'Error: directory not found: %s\n' "$task_dir" >&2
  exit 2
fi

goal_path="$task_dir/GOAL.md"

if [ ! -f "$goal_path" ]; then
  printf 'Error: GOAL.md not found in %s\n' "$task_dir" >&2
  exit 2
fi

if [ ! -r "$goal_path" ]; then
  printf 'Error: failed to read GOAL.md\n' >&2
  exit 2
fi

cat <<'PROMPT'
あなたは仕様策定者です。GOAL.md を読み取り、実装者向けの SPEC.md を作成してください。

出力ルール:
- 実装は禁止
- 出力は SPEC.md の本文のみ（前後の説明・コードブロック外の文章は禁止）
- 見出しはこの順序で固定: Scope / Acceptance Criteria / Interfaces / Error Handling / Security/Safety Constraints / Test Plan
- 各見出しには具体的かつ検証可能な内容を書く
- 余計な説明や挨拶は書かない

GOAL.md:
```
PROMPT
cat "$goal_path"
cat <<'PROMPT'
```
PROMPT

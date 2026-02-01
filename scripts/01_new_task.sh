#!/usr/bin/env bash
set -euo pipefail

ID="${1:-}"
if [[ -z "$ID" ]]; then
  TS="$(date +%Y-%m-%d-%H%M)"
  ID="$TS-0001"
fi

TASK_DIR="tasks/$ID"
mkdir -p "$TASK_DIR"

cat > "$TASK_DIR/GOAL.md" <<'TPL'
# Goal

## Purpose
- （何を達成したいかを1〜2行）

## Deliverable
- （何ができたら完了か：画面/機能/CLI/APIなど）

## Constraints
- Must: （絶対条件）
- Must not: （やってはいけないこと）
- Out of scope: （今回はやらないこと）
TPL

cat > "$TASK_DIR/SPEC.md" <<'TPL'
# SPEC
TPL

echo "$TASK_DIR"

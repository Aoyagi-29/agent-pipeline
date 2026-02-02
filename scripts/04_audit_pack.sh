#!/usr/bin/env bash
set -euo pipefail

usage() { echo "Usage: $0 <task-dir>" >&2; }

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

TASK_DIR="$1"
if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: task-dir is not a directory: $TASK_DIR" >&2
  usage
  exit 2
fi

SPEC_PATH="$TASK_DIR/SPEC.md"
if [[ ! -f "$SPEC_PATH" ]]; then
  echo "Error: missing SPEC.md: $SPEC_PATH" >&2
  exit 2
fi

OUT_PATH="$TASK_DIR/AUDIT_PACK.md"
GATE_REPORT_PATH="$TASK_DIR/GATE_REPORT.md"

NOW="$(date -Iseconds 2>/dev/null || date)"

{
  echo "# AUDIT PACK"
  echo
  echo "- task_dir: $TASK_DIR"
  echo "- generated_at: $NOW"
  echo
  echo "## SPEC"
  echo
  cat "$SPEC_PATH"
  echo
  echo "## GATE_REPORT"
  echo
  if [[ -f "$GATE_REPORT_PATH" ]]; then
    cat "$GATE_REPORT_PATH"
  else
    echo "missing"
  fi
  echo
  echo "## DIFF_STAT"
  echo
  echo '```'
  git diff --stat HEAD~1..HEAD || true
  echo '```'
  echo
  echo "## DIFF"
  echo
  echo '```'
  git diff HEAD~1..HEAD || true
  echo '```'
} > "$OUT_PATH"

echo "Wrote: $OUT_PATH"

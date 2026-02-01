#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/04_audit_pack.sh [--help] <task-dir>"
}

if [[ $# -eq 1 && "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -eq 0 || $# -ge 2 ]]; then
  usage >&2
  exit 2
fi

if [[ "${1:-}" == --* ]]; then
  usage >&2
  exit 2
fi

TASK_DIR="$1"
if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Error: not inside a git repository: $(pwd -P)" >&2
  exit 2
fi

GOAL_FILE="$TASK_DIR/GOAL.md"
SPEC_FILE="$TASK_DIR/SPEC.md"
if [[ ! -f "$GOAL_FILE" ]]; then
  echo "Error: GOAL.md not found in $TASK_DIR" >&2
  exit 1
fi

if [[ ! -f "$SPEC_FILE" ]]; then
  echo "Error: SPEC.md not found in $TASK_DIR" >&2
  exit 1
fi

TASK_ID="$(basename "$TASK_DIR")"
TIMESTAMP="$(date -Iseconds)"
PACK_FILE="$TASK_DIR/AUDIT_PACK.md"

stat_output="$(git --no-pager diff --stat HEAD)"
diff_output="$(git --no-pager diff HEAD)"

{
  echo "# AUDIT_PACK: $TASK_ID"
  echo "Generated: $TIMESTAMP"
  echo ""
  echo "## GOAL.md"
  cat "$GOAL_FILE"
  echo ""
  echo "## SPEC.md"
  cat "$SPEC_FILE"
  echo ""
  echo "## GATE_REPORT.md"
  if [[ -f "$TASK_DIR/GATE_REPORT.md" ]]; then
    cat "$TASK_DIR/GATE_REPORT.md"
  else
    echo "MISSING: GATE_REPORT.md"
  fi
  echo ""
  echo "## git diff --stat"
  echo '```'
  if [[ -n "$stat_output" ]]; then
    echo "$stat_output"
  else
    echo "(no uncommitted changes)"
  fi
  echo '```'
  echo ""
  echo "## git diff"
  echo '```'
  if [[ -n "$diff_output" ]]; then
    echo "$diff_output"
  else
    echo "(no uncommitted changes)"
  fi
  echo '```'
} > "$PACK_FILE"

echo "Wrote: $PACK_FILE"

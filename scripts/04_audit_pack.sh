#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/04_audit_pack.sh [--help] <task-dir>"
}

if [[ $# -eq 1 && "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -eq 0 || $# -ge 2 ]]; then
  usage >&2
  exit 2
fi

TASK_DIR="$1"
if [[ "${TASK_DIR:-}" == --* ]]; then
  usage >&2
  exit 2
fi

if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  usage >&2
  exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Error: not inside a git repository: $(pwd -P)" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GOAL_PATH="$TASK_DIR/GOAL.md"
SPEC_PATH="$TASK_DIR/SPEC.md"
if [[ ! -f "$GOAL_PATH" ]]; then
  echo "Error: GOAL.md not found in $TASK_DIR" >&2
  exit 1
fi
if [[ ! -f "$SPEC_PATH" ]]; then
  echo "Error: SPEC.md not found in $TASK_DIR" >&2
  exit 1
fi

OUT_PATH="$TASK_DIR/AUDIT_PACK.md"
GATE_REPORT_PATH="$TASK_DIR/GATE_REPORT.md"
BUILD_REPORT_PATH="$TASK_DIR/BUILD_REPORT.md"
CHANGE_SUMMARY_PATH="$TASK_DIR/CHANGE_SUMMARY.md"
CHANGE_SUMMARY_SCRIPT="$SCRIPT_DIR/04_generate_change_summary.py"
TASK_ID="$(basename "$TASK_DIR")"

NOW="$(date -Iseconds 2>/dev/null || date)"

summary_status=0
summary_output=""
if [[ -f "$CHANGE_SUMMARY_SCRIPT" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    set +e
    summary_output="$(python3 "$CHANGE_SUMMARY_SCRIPT" "$TASK_DIR" 2>&1)"
    summary_status=$?
    set -e
  else
    summary_status=2
    summary_output="Missing: python3 (required to run $CHANGE_SUMMARY_SCRIPT)"
  fi
else
  summary_status=2
  summary_output="Missing: $CHANGE_SUMMARY_SCRIPT"
fi
{
  if [[ $summary_status -eq 0 ]]; then
    printf "%s\n" "$summary_output"
  else
    echo "Error: change summary generation failed (exit=$summary_status)"
    printf "%s\n" "$summary_output"
  fi
} > "$CHANGE_SUMMARY_PATH"

{
  echo "# AUDIT_PACK: $TASK_ID"
  echo
  echo "- generated_at: $NOW"
  echo
  echo "## GOAL.md"
  echo
  cat "$GOAL_PATH"
  echo
  echo "## SPEC.md"
  echo
  cat "$SPEC_PATH"
  echo
  echo "## GATE_REPORT.md"
  echo
  if [[ -f "$GATE_REPORT_PATH" ]]; then
    cat "$GATE_REPORT_PATH"
  else
    echo "MISSING: GATE_REPORT.md"
  fi
  echo
  echo "## BUILD_REPORT.md"
  echo
  if [[ -f "$BUILD_REPORT_PATH" ]]; then
    cat "$BUILD_REPORT_PATH"
  else
    echo "MISSING: BUILD_REPORT.md"
  fi
  echo
  echo "## CHANGE_SUMMARY.md"
  echo
  if [[ -f "$CHANGE_SUMMARY_PATH" ]]; then
    cat "$CHANGE_SUMMARY_PATH"
  else
    echo "MISSING: CHANGE_SUMMARY.md"
  fi
  echo
  echo "## git diff --stat"
  echo
  echo '```'
  diff_stat="$(git diff --stat HEAD || true)"
  if [[ -n "$diff_stat" ]]; then
    printf "%s\n" "$diff_stat"
  else
    echo "(no uncommitted changes)"
  fi
  echo '```'
  echo
  echo "## git diff"
  echo
  echo '```'
  diff_body="$(git diff HEAD || true)"
  if [[ -n "$diff_body" ]]; then
    printf "%s\n" "$diff_body"
  else
    echo "(no uncommitted changes)"
  fi
  echo '```'
} > "$OUT_PATH"

echo "Wrote: $OUT_PATH"

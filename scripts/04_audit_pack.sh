#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/04_audit_pack.sh tasks/<id>" >&2
  exit 2
}

fail() {
  echo "error: $*" >&2
  exit 2
}

if [[ $# -ne 1 ]]; then
  usage
fi

TASK_DIR="$1"
if [[ -z "$TASK_DIR" ]]; then
  usage
fi

if [[ ! -d "$TASK_DIR" ]]; then
  fail "task dir not found: $TASK_DIR"
fi

SPEC_FILE="$TASK_DIR/SPEC.md"
if [[ ! -r "$SPEC_FILE" ]]; then
  fail "SPEC.md not found or not readable: $SPEC_FILE"
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  fail "not a git repository"
fi

if [[ ! -x "scripts/03_gate.sh" ]]; then
  fail "gate script not found or not executable: scripts/03_gate.sh"
fi

GATE_EXIT=0
if ./scripts/03_gate.sh "$TASK_DIR"; then
  GATE_EXIT=0
else
  GATE_EXIT=$?
fi

GATE_REPORT="$TASK_DIR/GATE_REPORT.md"
if [[ ! -f "$GATE_REPORT" ]]; then
  fail "gate report not found: $GATE_REPORT"
fi

AUDIT_PACK="$TASK_DIR/AUDIT_PACK.md"
: > "$AUDIT_PACK"

{
  echo "## AUDIT PACK"
  echo '````'
  echo "Generated: $(date)"
  echo "Task Dir: $TASK_DIR"
  echo "Git Top: $(git rev-parse --show-toplevel)"
  echo "Git HEAD: $(git rev-parse HEAD)"
  echo "Gate Exit Code: $GATE_EXIT"
  echo '````'
  echo ""

  echo "## SPEC (SSOT)"
  echo '````'
  cat "$SPEC_FILE"
  echo '````'
  echo ""

  echo "## GATE REPORT"
  echo '````'
  echo "Gate Exit Code: $GATE_EXIT"
  cat "$GATE_REPORT"
  echo '````'
  echo ""

  echo "## GIT DIFF --STAT"
  echo '````'
  git --no-pager diff --stat
  echo '````'
  echo ""

  echo "## GIT DIFF"
  echo '````'
  git --no-pager diff
  echo '````'
  echo ""

  echo "## GIT DIFF --CACHED --STAT"
  echo '````'
  git --no-pager diff --cached --stat
  echo '````'
  echo ""

  echo "## GIT DIFF --CACHED"
  echo '````'
  git --no-pager diff --cached
  echo '````'
  echo ""
} >> "$AUDIT_PACK"

echo "wrote $AUDIT_PACK"

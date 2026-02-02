#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: scripts/05_run_audit.sh [-h|--help] <task-dir>"
  echo "example: scripts/05_run_audit.sh tasks/2026-02-02-0239-0001"
}

if [[ $# -eq 1 && ("${1:-}" == "-h" || "${1:-}" == "--help") ]]; then
  usage
  exit 0
fi

if [[ $# -eq 0 || $# -ge 2 ]]; then
  usage >&2
  exit 2
fi

if [[ "${1:-}" == -* ]]; then
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Step 1/3: Gate (--clean) ==="
set +e
"${SCRIPT_DIR}/03_gate.sh" "$TASK_DIR"
gate_exit=$?
set -e

# exit=2 は運用違反（dirty/usage等）として即停止
if [[ $gate_exit -eq 2 ]]; then
  echo "Error: gate failed (exit=$gate_exit)" >&2
  exit 2
fi

echo "=== Step 2/3: Audit Pack ==="
set +e
"${SCRIPT_DIR}/04_audit_pack.sh" "$TASK_DIR"
pack_exit=$?
set -e
if [[ $pack_exit -ne 0 ]]; then
  echo "Error: audit_pack failed (exit=$pack_exit)" >&2
  exit "$pack_exit"
fi

echo "=== Step 3/3: Working Tree Status ==="
git status --porcelain

# Gateの結果（0=PASS, 1=FAIL）を最終結果として返す
exit "$gate_exit"

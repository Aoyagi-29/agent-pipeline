#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: 00_run_task.sh <task-dir>"
  echo ""
  echo "Run the full task pipeline (Gate → AuditPack → Status)."
  echo ""
  echo "Example:"
  echo "  ./scripts/00_run_task.sh tasks/2026-02-02-0337-0001"
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== 00_run_task: $TASK_DIR ==="
set +e
"${SCRIPT_DIR}/05_run_audit.sh" "$TASK_DIR"
exit_code=$?
set -e
if [[ $exit_code -ne 0 ]]; then
  echo "Error: run_audit failed (exit=$exit_code)" >&2
  exit "$exit_code"
fi
echo "=== 00_run_task: done ==="
exit 0

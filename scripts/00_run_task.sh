#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: 00_run_task.sh [--auto] <task-dir>"
  echo ""
  echo "Default mode: run Gate → AuditPack → Status."
  echo "Auto mode (--auto): Plan(Claude API) → Build/Run(Codex) → Gate → AuditPack."
  echo ""
  echo "Example:"
  echo "  ./scripts/00_run_task.sh tasks/2026-02-02-0337-0001"
  echo "  ./scripts/00_run_task.sh --auto tasks/2026-02-02-0337-0001"
}

if [[ $# -eq 1 && ("${1:-}" == "-h" || "${1:-}" == "--help") ]]; then
  usage
  exit 0
fi

MODE="default"
TASK_DIR=""
if [[ $# -eq 1 ]]; then
  if [[ "${1:-}" == -* ]]; then
    usage >&2
    exit 2
  fi
  TASK_DIR="$1"
elif [[ $# -eq 2 && "${1:-}" == "--auto" ]]; then
  MODE="auto"
  TASK_DIR="$2"
else
  usage >&2
  exit 2
fi

if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

load_env_file_if_present() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi
}

echo "=== 00_run_task: $TASK_DIR ==="

if [[ "$MODE" == "default" ]]; then
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
fi

if [[ -z "${CLAUDE_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  load_env_file_if_present "${ROOT_DIR}/.env"
fi

echo "=== Auto A/3: Plan (Claude API) ==="
set +e
"${SCRIPT_DIR}/02_build_self_context.sh" "$TASK_DIR"
context_exit=$?
set -e
if [[ $context_exit -ne 0 ]]; then
  echo "Warning: failed to build SELF_CONTEXT.md (exit=$context_exit); planning with GOAL.md only" >&2
fi

set +e
python3 "${SCRIPT_DIR}/02_make_spec_api.py" "$TASK_DIR"
plan_exit=$?
set -e
if [[ $plan_exit -ne 0 ]]; then
  echo "Error: plan failed (exit=$plan_exit)" >&2
  exit 2
fi

echo "=== Auto B/3: Build/Run (Codex) ==="
set +e
"${SCRIPT_DIR}/06_build_run_codex.sh" "$TASK_DIR"
build_exit=$?
set -e
if [[ $build_exit -eq 2 ]]; then
  echo "Error: build/run failed (exit=$build_exit)" >&2
  exit 2
fi

echo "=== Auto C/3: Gate + AuditPack ==="
set +e
"${SCRIPT_DIR}/03_gate.sh" "$TASK_DIR"
gate_exit=$?
set -e

set +e
"${SCRIPT_DIR}/04_audit_pack.sh" "$TASK_DIR"
audit_exit=$?
set -e
if [[ $audit_exit -ne 0 ]]; then
  echo "Error: audit_pack failed (exit=$audit_exit)" >&2
  exit "$audit_exit"
fi

if [[ $gate_exit -eq 0 || $gate_exit -eq 1 ]]; then
  echo "=== 00_run_task: done (auto, gate_exit=$gate_exit, build_exit=$build_exit) ==="
  exit "$gate_exit"
fi
echo "Error: gate failed (exit=$gate_exit)" >&2
exit 2

echo "=== 00_run_task: done ==="
exit 0

#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: 00_run_task.sh [--auto] <task-dir>"
  echo "       00_run_task.sh --resume <task-dir>"
  echo ""
  echo "Default mode: run Gate -> AuditPack -> Status."
  echo "Auto mode (--auto): Plan(Claude API) -> Implement(Codex) -> Build/Run -> Gate -> AuditPack."
  echo "Resume mode (--resume): continue auto from the failed phase based on RUN_SUMMARY.md."
  echo ""
  echo "Example:"
  echo "  ./scripts/00_run_task.sh tasks/2026-02-02-0337-0001"
  echo "  ./scripts/00_run_task.sh --auto tasks/2026-02-02-0337-0001"
  echo "  ./scripts/00_run_task.sh --resume tasks/2026-02-02-0337-0001"
}

if [[ $# -eq 1 && ("${1:-}" == "-h" || "${1:-}" == "--help") ]]; then
  usage
  exit 0
fi

if [[ -z "${RUN_TASK_SELF_COPY:-}" ]]; then
  tmp_run_task="$(mktemp)"
  cp "$0" "$tmp_run_task"
  chmod +x "$tmp_run_task"
  export RUN_TASK_SELF_COPY=1
  export RUN_TASK_TMP_SELF="$tmp_run_task"
  export RUN_TASK_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  export RUN_TASK_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  exec "$tmp_run_task" "$@"
fi

cleanup_tmp_self() {
  if [[ -n "${RUN_TASK_TMP_SELF:-}" && -f "$RUN_TASK_TMP_SELF" ]]; then
    rm -f "$RUN_TASK_TMP_SELF"
  fi
}
trap cleanup_tmp_self EXIT

MODE="default"
TASK_DIR=""
if [[ $# -eq 1 ]]; then
  if [[ "${1:-}" == -* ]]; then
    usage >&2
    exit 2
  fi
  TASK_DIR="$1"
elif [[ $# -eq 2 && ("${1:-}" == "--auto" || "${1:-}" == "--resume") ]]; then
  if [[ "${1:-}" == "--auto" ]]; then
    MODE="auto"
  else
    MODE="resume"
  fi
  TASK_DIR="$2"
else
  usage >&2
  exit 2
fi

if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  exit 2
fi

if [[ -n "${RUN_TASK_SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$RUN_TASK_SCRIPT_DIR"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
if [[ -n "${RUN_TASK_ROOT_DIR:-}" ]]; then
  ROOT_DIR="$RUN_TASK_ROOT_DIR"
else
  ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
SUMMARY_REPORT="$TASK_DIR/RUN_SUMMARY.md"

summary_init() {
  {
    echo "# RUN SUMMARY"
    echo ""
    echo "- task_dir: $TASK_DIR"
    echo "- mode: $MODE"
    echo "- started_at: $(date -Is)"
    echo ""
    echo "## Phases"
  } > "$SUMMARY_REPORT"
}

summary_phase() {
  local name="$1"
  local exit_code="$2"
  local note="${3:-}"
  if [[ -n "$note" ]]; then
    printf -- "- %s: exit=%s (%s)\n" "$name" "$exit_code" "$note" >> "$SUMMARY_REPORT"
  else
    printf -- "- %s: exit=%s\n" "$name" "$exit_code" >> "$SUMMARY_REPORT"
  fi
}

summary_skip() {
  local name="$1"
  summary_phase "$name" 127 "skipped"
}

summary_debug() {
  local name="$1"
  local exit_code="$2"
  summary_phase "$name" "$exit_code" "debug"
}

summary_finalize() {
  local final_exit="$1"
  {
    echo ""
    echo "## Outputs"
    echo "- IMPLEMENT_REPORT.md: $TASK_DIR/IMPLEMENT_REPORT.md"
    echo "- BUILD_REPORT.md: $TASK_DIR/BUILD_REPORT.md"
    echo "- GATE_REPORT.md: $TASK_DIR/GATE_REPORT.md"
    echo "- AUDIT.md: $TASK_DIR/AUDIT.md"
    echo "- AUDIT_PACK.md: $TASK_DIR/AUDIT_PACK.md"
    echo "- SELF_CONTEXT.md: $TASK_DIR/SELF_CONTEXT.md"
    echo ""
    echo "## Result"
    echo "- exit: $final_exit"
    echo "- finished_at: $(date -Is)"
  } >> "$SUMMARY_REPORT"
  echo "=== 00_run_task: summary written to $SUMMARY_REPORT ==="
}

load_env_file_if_present() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -z "$line" || "${line:0:1}" == "#" ]]; then
      continue
    fi
    if [[ "$line" == export\ * ]]; then
      line="${line#export }"
      line="${line#"${line%%[![:space:]]*}"}"
    fi
    if [[ "$line" != *"="* ]]; then
      echo "Failed to source .env file; check syntax: $env_file" >&2
      return 1
    fi
    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "Failed to source .env file; check syntax: $env_file" >&2
      return 1
    fi
    if [[ -n "$value" ]]; then
      if [[ ("$value" == \"*\" && "$value" == *\") || ("$value" == \'*\' && "$value" == *\') ]]; then
        value="${value:1:${#value}-2}"
      fi
    fi
    if [[ -z "${!key-}" ]]; then
      export "$key=$value"
    fi
  done < "$env_file"
  return 0
}

require_python3() {
  if command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  echo "Error: python3 not found. Install Python 3.8+ to run plan/gate helpers." >&2
  return 1
}

write_ssot_snapshot() {
  local snapshot_path="$TASK_DIR/.SSOT_SNAPSHOT"
  local goal_path="$TASK_DIR/GOAL.md"
  local spec_path="$TASK_DIR/SPEC.md"
  if [[ ! -f "$goal_path" || ! -f "$spec_path" ]]; then
    return 0
  fi
  {
    echo "GOAL.md $(sha256sum "$goal_path" | awk '{print $1}')"
    echo "SPEC.md $(sha256sum "$spec_path" | awk '{print $1}')"
  } > "$snapshot_path"
}

ensure_ssot_snapshot() {
  local snapshot_path="$TASK_DIR/.SSOT_SNAPSHOT"
  if [[ -f "$snapshot_path" ]]; then
    return 0
  fi
  write_ssot_snapshot
}

get_last_failed_phase() {
  local summary_path="$1"
  local line name exit_code
  if [[ ! -f "$summary_path" ]]; then
    echo ""
    return 0
  fi
  while IFS= read -r line; do
    if [[ "$line" =~ ^- ]] && [[ "$line" == *"exit="* ]]; then
      name="$(printf "%s" "$line" | sed -E 's/^- ([^:]+):.*/\\1/')"
      exit_code="$(printf "%s" "$line" | sed -E 's/.*exit=([0-9]+).*/\\1/')"
      if [[ "$exit_code" =~ ^[0-9]+$ ]] && [[ "$exit_code" -ne 0 && "$exit_code" -ne 127 ]]; then
        echo "$name"
        return 0
      fi
    fi
  done < "$summary_path"
  echo ""
}

phase_index() {
  case "$1" in
    Plan) echo 1 ;;
    Implement) echo 2 ;;
    Build) echo 3 ;;
    Gate) echo 4 ;;
    AuditPack) echo 5 ;;
    *) echo 999 ;;
  esac
}

should_run_phase() {
  local name="$1"
  local start="$2"
  local name_idx start_idx
  name_idx="$(phase_index "$name")"
  start_idx="$(phase_index "$start")"
  [[ "$name_idx" -ge "$start_idx" ]]
}

debug_phase() {
  local name="$1"
  local cmd_desc="$2"
  local debug_log="$TASK_DIR/DEBUG_REPORT.md"
  {
    echo "## Debug: $name"
    echo "- command: $cmd_desc"
    echo "- started_at: $(date -Is)"
    echo '```'
  } >> "$debug_log"
}

debug_phase_end() {
  local debug_log="$TASK_DIR/DEBUG_REPORT.md"
  {
    echo '```'
    echo "- finished_at: $(date -Is)"
    echo
  } >> "$debug_log"
}

echo "=== 00_run_task: $TASK_DIR ==="
summary_init

if [[ "$MODE" == "default" ]]; then
  set +e
  "${SCRIPT_DIR}/05_run_audit.sh" "$TASK_DIR"
  exit_code=$?
  set -e
  summary_phase "Gate+AuditPack" "$exit_code"
  if [[ $exit_code -ne 0 ]]; then
    echo "Error: run_audit failed (exit=$exit_code)" >&2
    summary_finalize "$exit_code"
    exit "$exit_code"
  fi
  summary_finalize 0
  echo "=== 00_run_task: done ==="
  exit 0
fi

start_phase="Plan"
if [[ "$MODE" == "resume" ]]; then
  last_failed="$(get_last_failed_phase "$SUMMARY_REPORT")"
  if [[ -z "$last_failed" ]]; then
    echo "Error: no failed phase found in RUN_SUMMARY.md for resume" >&2
    exit 2
  fi
  start_phase="$last_failed"
  echo "=== Resume from: $start_phase ==="
fi

if ! load_env_file_if_present "${ROOT_DIR}/.env"; then
  summary_phase "Env" 2 "failed"
  summary_skip "Plan"
  summary_skip "Implement"
  summary_skip "Build"
  summary_skip "Gate"
  summary_skip "AuditPack"
  summary_finalize 2
  exit 2
fi

echo "=== Auto A/5: Plan (Claude API) ==="
if should_run_phase "Plan" "$start_phase"; then
  if ! require_python3; then
    summary_phase "Plan" 2 "missing python3"
    summary_skip "Implement"
    summary_skip "Build"
    summary_skip "Gate"
    summary_skip "AuditPack"
    summary_finalize 2
    exit 2
  fi
  set +e
  "${SCRIPT_DIR}/02_build_self_context.sh" "$TASK_DIR"
  context_exit=$?
  set -e
  if [[ $context_exit -ne 0 ]]; then
    echo "Warning: failed to build SELF_CONTEXT.md (exit=$context_exit); planning with GOAL.md only" >&2
    summary_phase "SELF_CONTEXT" "$context_exit" "warning"
  else
    summary_phase "SELF_CONTEXT" 0
  fi

  set +e
  python3 "${SCRIPT_DIR}/02_make_spec_api.py" "$TASK_DIR"
  plan_exit=$?
  set -e
  summary_phase "Plan" "$plan_exit"
  if [[ $plan_exit -ne 0 ]]; then
    echo "Error: plan failed (exit=$plan_exit)" >&2
    summary_skip "Implement"
    summary_skip "Build"
    summary_skip "Gate"
    summary_skip "AuditPack"
    debug_phase "Plan" "python3 ${SCRIPT_DIR}/02_make_spec_api.py ${TASK_DIR}"
    set +e
    python3 "${SCRIPT_DIR}/02_make_spec_api.py" "$TASK_DIR" 2>&1 | tee -a "$TASK_DIR/DEBUG_REPORT.md" >/dev/null
    dbg_exit=$?
    set -e
    debug_phase_end
    summary_debug "Plan" "$dbg_exit"
    summary_finalize "$plan_exit"
    exit "$plan_exit"
  fi
  write_ssot_snapshot
else
  summary_skip "Plan"
fi

echo "=== Auto B/5: Implement (Codex) ==="
if should_run_phase "Implement" "$start_phase"; then
  ensure_ssot_snapshot
  set +e
  "${SCRIPT_DIR}/05_codex_implement.sh" "$TASK_DIR"
  implement_exit=$?
  set -e
  summary_phase "Implement" "$implement_exit"
  if [[ $implement_exit -ne 0 ]]; then
    echo "Error: implement failed (exit=$implement_exit)" >&2
    summary_skip "Build"
    summary_skip "Gate"
    summary_skip "AuditPack"
    debug_phase "Implement" "${SCRIPT_DIR}/05_codex_implement.sh ${TASK_DIR}"
    set +e
    "${SCRIPT_DIR}/05_codex_implement.sh" "$TASK_DIR" 2>&1 | tee -a "$TASK_DIR/DEBUG_REPORT.md" >/dev/null
    dbg_exit=$?
    set -e
    debug_phase_end
    summary_debug "Implement" "$dbg_exit"
    summary_finalize "$implement_exit"
    exit "$implement_exit"
  fi
else
  summary_skip "Implement"
fi

echo "=== Auto C/5: Build/Run ==="
if should_run_phase "Build" "$start_phase"; then
  ensure_ssot_snapshot
  set +e
  "${SCRIPT_DIR}/06_build_run_codex.sh" "$TASK_DIR"
  build_exit=$?
  set -e
  summary_phase "Build" "$build_exit"
  if [[ $build_exit -ne 0 ]]; then
    echo "Error: build/run failed (exit=$build_exit)" >&2
    summary_skip "Gate"
    summary_skip "AuditPack"
    debug_phase "Build" "${SCRIPT_DIR}/06_build_run_codex.sh ${TASK_DIR}"
    set +e
    "${SCRIPT_DIR}/06_build_run_codex.sh" "$TASK_DIR" 2>&1 | tee -a "$TASK_DIR/DEBUG_REPORT.md" >/dev/null
    dbg_exit=$?
    set -e
    debug_phase_end
    summary_debug "Build" "$dbg_exit"
    summary_finalize "$build_exit"
    exit "$build_exit"
  fi
else
  summary_skip "Build"
fi

echo "=== Auto D/5: Gate ==="
if should_run_phase "Gate" "$start_phase"; then
  ensure_ssot_snapshot
  set +e
  "${SCRIPT_DIR}/03_gate.sh" "$TASK_DIR"
  gate_exit=$?
  set -e
  summary_phase "Gate" "$gate_exit"

  if [[ $gate_exit -ne 0 ]]; then
    echo "Error: gate failed (exit=$gate_exit)" >&2
    summary_skip "AuditPack"
    debug_phase "Gate" "${SCRIPT_DIR}/03_gate.sh ${TASK_DIR}"
    set +e
    "${SCRIPT_DIR}/03_gate.sh" "$TASK_DIR" 2>&1 | tee -a "$TASK_DIR/DEBUG_REPORT.md" >/dev/null
    dbg_exit=$?
    set -e
    debug_phase_end
    summary_debug "Gate" "$dbg_exit"
    summary_finalize "$gate_exit"
    exit "$gate_exit"
  fi
else
  summary_skip "Gate"
fi

echo "=== Auto E/5: AuditPack ==="
if should_run_phase "AuditPack" "$start_phase"; then
  set +e
  "${SCRIPT_DIR}/04_audit_pack.sh" "$TASK_DIR"
  audit_exit=$?
  set -e
  summary_phase "AuditPack" "$audit_exit"
  if [[ $audit_exit -ne 0 ]]; then
    echo "Error: audit_pack failed (exit=$audit_exit)" >&2
    debug_phase "AuditPack" "${SCRIPT_DIR}/04_audit_pack.sh ${TASK_DIR}"
    set +e
    "${SCRIPT_DIR}/04_audit_pack.sh" "$TASK_DIR" 2>&1 | tee -a "$TASK_DIR/DEBUG_REPORT.md" >/dev/null
    dbg_exit=$?
    set -e
    debug_phase_end
    summary_debug "AuditPack" "$dbg_exit"
    summary_finalize "$audit_exit"
    exit "$audit_exit"
  fi
else
  summary_skip "AuditPack"
fi

summary_finalize 0
echo "=== 00_run_task: done (auto) ==="
exit 0

echo "=== 00_run_task: done ==="

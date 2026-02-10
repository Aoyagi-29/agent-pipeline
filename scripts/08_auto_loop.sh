#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/08_auto_loop.sh <task-dir>"
  echo ""
  echo "Auto loop with bounded retries/replans."
}

if [[ $# -ne 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage >&2
  exit 2
fi

TASK_DIR="$1"
if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUMMARY_REPORT="$TASK_DIR/RUN_SUMMARY.md"
DECISION_LOG="$TASK_DIR/DECISION_LOG.md"

MAX_BUILD_LOOPS="${MAX_BUILD_LOOPS:-3}"
MAX_REPLANS="${MAX_REPLANS:-2}"
MAX_TOTAL_RUNS="${MAX_TOTAL_RUNS:-6}"
MAX_ENV_RETRIES="${MAX_ENV_RETRIES:-2}"
MAX_DIFF_FILES="${MAX_DIFF_FILES:-50}"

if ! [[ "$MAX_BUILD_LOOPS" =~ ^[0-9]+$ ]] || [[ "$MAX_BUILD_LOOPS" -le 0 ]]; then
  echo "Error: MAX_BUILD_LOOPS must be a positive integer" >&2
  exit 2
fi
if ! [[ "$MAX_REPLANS" =~ ^[0-9]+$ ]] || [[ "$MAX_REPLANS" -lt 0 ]]; then
  echo "Error: MAX_REPLANS must be a non-negative integer" >&2
  exit 2
fi
if ! [[ "$MAX_TOTAL_RUNS" =~ ^[0-9]+$ ]] || [[ "$MAX_TOTAL_RUNS" -le 0 ]]; then
  echo "Error: MAX_TOTAL_RUNS must be a positive integer" >&2
  exit 2
fi
if ! [[ "$MAX_ENV_RETRIES" =~ ^[0-9]+$ ]] || [[ "$MAX_ENV_RETRIES" -lt 0 ]]; then
  echo "Error: MAX_ENV_RETRIES must be a non-negative integer" >&2
  exit 2
fi
if ! [[ "$MAX_DIFF_FILES" =~ ^[0-9]+$ ]] || [[ "$MAX_DIFF_FILES" -le 0 ]]; then
  echo "Error: MAX_DIFF_FILES must be a positive integer" >&2
  exit 2
fi

get_target_repo() {
  local repo_file="$TASK_DIR/TARGET_REPO"
  if [[ ! -f "$repo_file" ]]; then
    echo "$ROOT_DIR"
    return 0
  fi
  local repo
  repo="$(head -n 1 "$repo_file" | tr -d '\r' | xargs)"
  if [[ -z "$repo" ]]; then
    echo "$ROOT_DIR"
    return 0
  fi
  echo "$repo"
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
      name="$(printf "%s" "$line" | sed -E 's/^- ([^:]+):.*/\1/')"
      exit_code="$(printf "%s" "$line" | sed -E 's/.*exit=([0-9]+).*/\1/')"
      if [[ "$exit_code" =~ ^[0-9]+$ ]] && [[ "$exit_code" -ne 0 && "$exit_code" -ne 127 ]]; then
        echo "$name"
        return 0
      fi
    fi
  done < "$summary_path"
  echo ""
}

get_last_exit_code() {
  local summary_path="$1"
  local line exit_code=""
  if [[ ! -f "$summary_path" ]]; then
    echo ""
    return 0
  fi
  while IFS= read -r line; do
    if [[ "$line" =~ ^- ]] && [[ "$line" == *"exit="* ]]; then
      exit_code="$(printf "%s" "$line" | sed -E 's/.*exit=([0-9]+).*/\1/')"
    fi
  done < "$summary_path"
  echo "$exit_code"
}

read_report_tail() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tail -n 200 "$file"
  fi
}

extract_signature() {
  local phase="$1"
  local report=""
  case "$phase" in
    Plan) report="$TASK_DIR/DEBUG_REPORT.md" ;;
    Implement) report="$TASK_DIR/IMPLEMENT_REPORT.md" ;;
    Build) report="$TASK_DIR/BUILD_REPORT.md" ;;
    Gate) report="$TASK_DIR/GATE_REPORT.md" ;;
    AuditPack) report="$TASK_DIR/AUDIT.md" ;;
    *) report="$TASK_DIR/DEBUG_REPORT.md" ;;
  esac
  if [[ -f "$report" ]]; then
    local sig
    sig="$(rg -m1 -n "Unauthorized|ERROR|Error:|Exception|Traceback|FAIL|failed|Missing scopes|timeout|timed out|rate limit|ECONN|ENOTFOUND|EAI_AGAIN|HTTP [0-9]{3}" "$report" 2>/dev/null || true)"
    if [[ -n "$sig" ]]; then
      echo "$sig"
      return 0
    fi
  fi
  local exit_code
  exit_code="$(get_last_exit_code "$SUMMARY_REPORT")"
  echo "phase=${phase} exit=${exit_code:-unknown}"
}

classify_failure() {
  local sig="$1"
  if [[ "$sig" =~ (Unauthorized|401|403|rate\ limit|timed\ out|timeout|ECONN|ENOTFOUND|EAI_AGAIN|502|503|504) ]]; then
    echo "ENV"
    return 0
  fi
  if [[ "$sig" =~ (Acceptance\ Criteria|success\ criteria|成功条件|仕様が曖昧|ambiguous|not\ defined|missing\ input|missing\ output) ]]; then
    echo "SPEC_GAP"
    return 0
  fi
  if [[ "$sig" =~ (flaky|intermittent|nondeterministic) ]]; then
    echo "FLAKY"
    return 0
  fi
  echo "CODE_BUG"
}

detect_out_of_scope() {
  local repo
  repo="$(get_target_repo)"
  if [[ ! -d "$repo" ]]; then
    echo "0"
    return 0
  fi
  local diff_names
  diff_names="$(git -C "$repo" diff --name-only)"
  if [[ -z "$diff_names" ]]; then
    echo "0"
    return 0
  fi
  if printf "%s\n" "$diff_names" | rg -q "tasks/.*/(SPEC|GOAL)\.md"; then
    echo "1"
    return 0
  fi
  local count
  count="$(printf "%s\n" "$diff_names" | wc -l | tr -d ' ')"
  if [[ "$count" -gt "$MAX_DIFF_FILES" ]]; then
    echo "1"
    return 0
  fi
  echo "0"
}

append_decision_log() {
  local cycle="$1"
  local observation="$2"
  local hypothesis="$3"
  local change="$4"
  local verification="$5"
  {
    echo "## Loop Cycle ${cycle}"
    echo "- Observed: ${observation}"
    echo "- Hypothesis: ${hypothesis}"
    echo "- Change: ${change}"
    echo "- Verification: ${verification}"
    echo
  } >> "$DECISION_LOG"
}

total_runs=0
replans=0
build_loops=0
env_retries=0
same_sig_streak=0
last_sig=""

while [[ "$total_runs" -lt "$MAX_TOTAL_RUNS" ]]; do
  total_runs=$((total_runs + 1))
  if [[ "$total_runs" -eq 1 ]]; then
    "${SCRIPT_DIR}/00_run_task.sh" --auto "$TASK_DIR"
  else
    if [[ -f "$SUMMARY_REPORT" ]] && [[ -n "$(get_last_failed_phase "$SUMMARY_REPORT")" ]]; then
      "${SCRIPT_DIR}/00_run_task.sh" --resume "$TASK_DIR"
    else
      "${SCRIPT_DIR}/00_run_task.sh" --auto "$TASK_DIR"
    fi
  fi

  last_failed="$(get_last_failed_phase "$SUMMARY_REPORT")"
  if [[ -z "$last_failed" ]]; then
    append_decision_log "$total_runs" "Pipeline completed successfully." "N/A" "None" "Exit 0"
    exit 0
  fi

  sig="$(extract_signature "$last_failed")"
  if [[ "$sig" == "$last_sig" ]]; then
    same_sig_streak=$((same_sig_streak + 1))
  else
    same_sig_streak=1
  fi
  last_sig="$sig"

  failure_type="$(classify_failure "$sig")"
  out_of_scope="$(detect_out_of_scope)"

  observation="phase=${last_failed}, sig=${sig}, type=${failure_type}"
  hypothesis="Need decision based on failure type and streak"

  if [[ "$failure_type" == "ENV" ]]; then
    env_retries=$((env_retries + 1))
    if [[ "$env_retries" -le "$MAX_ENV_RETRIES" ]]; then
      change="Retry same step (ENV error) attempt ${env_retries}/${MAX_ENV_RETRIES}"
      verification="Re-run pipeline"
      append_decision_log "$total_runs" "$observation" "$hypothesis" "$change" "$verification"
      continue
    fi
    change="Fail with action items (ENV error retries exhausted)"
    verification="Stop"
    append_decision_log "$total_runs" "$observation" "$hypothesis" "$change" "$verification"
    exit 2
  fi

  if [[ "$failure_type" == "SPEC_GAP" || "$out_of_scope" -eq 1 || "$same_sig_streak" -ge 2 ]]; then
    if [[ "$replans" -lt "$MAX_REPLANS" ]]; then
      replans=$((replans + 1))
      build_loops=0
      change="Replan (replans=${replans}/${MAX_REPLANS})"
      verification="Re-run auto from Plan"
      append_decision_log "$total_runs" "$observation" "$hypothesis" "$change" "$verification"
      "${SCRIPT_DIR}/00_run_task.sh" --auto "$TASK_DIR"
      continue
    fi
    change="Fail (replan limit reached)"
    verification="Stop"
    append_decision_log "$total_runs" "$observation" "$hypothesis" "$change" "$verification"
    exit 2
  fi

  if [[ "$last_failed" == "Implement" || "$last_failed" == "Build" || "$last_failed" == "Gate" ]]; then
    build_loops=$((build_loops + 1))
    if [[ "$build_loops" -gt "$MAX_BUILD_LOOPS" ]]; then
      if [[ "$replans" -lt "$MAX_REPLANS" ]]; then
        replans=$((replans + 1))
        build_loops=0
        change="Replan (build loops exceeded)"
        verification="Re-run auto from Plan"
        append_decision_log "$total_runs" "$observation" "$hypothesis" "$change" "$verification"
        "${SCRIPT_DIR}/00_run_task.sh" --auto "$TASK_DIR"
        continue
      fi
      change="Fail (build loop limit reached)"
      verification="Stop"
      append_decision_log "$total_runs" "$observation" "$hypothesis" "$change" "$verification"
      exit 2
    fi
  fi

  change="Retry same step (non-ENV)"
  verification="Re-run resume"
  append_decision_log "$total_runs" "$observation" "$hypothesis" "$change" "$verification"
done

append_decision_log "$total_runs" "Exceeded max total runs (${MAX_TOTAL_RUNS})." "Loop bound reached" "Fail" "Stop"
exit 2

#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/07_self_improve.sh [--run-auto] [--prefix NAME] [--lookback N] [--task DIR]"
  echo ""
  echo "Analyze recent task reports and create a new self-improvement task."
  echo "With --run-auto, immediately run 00_run_task.sh --auto on the created task."
}

RUN_AUTO=0
LOOKBACK=20
PREFIX="self"
FORCE_TASK=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --run-auto)
      RUN_AUTO=1
      shift
      ;;
    --lookback)
      if [[ $# -lt 2 ]]; then
        echo "Error: --lookback requires a value" >&2
        exit 2
      fi
      LOOKBACK="$2"
      shift 2
      ;;
    --prefix)
      if [[ $# -lt 2 ]]; then
        echo "Error: --prefix requires a value" >&2
        exit 2
      fi
      PREFIX="$2"
      shift 2
      ;;
    --task)
      if [[ $# -lt 2 ]]; then
        echo "Error: --task requires a value" >&2
        exit 2
      fi
      FORCE_TASK="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: ${1:-}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$LOOKBACK" =~ ^[0-9]+$ ]] || [[ "$LOOKBACK" -le 0 ]]; then
  echo "Error: --lookback must be a positive integer" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TASKS_DIR="$ROOT_DIR/tasks"
PATTERN_FILE="${SELF_IMPROVE_PATTERN_FILE:-$ROOT_DIR/scripts/self_improve_patterns.tsv}"

has_pattern() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$file"
  else
    grep -Eq "$pattern" "$file"
  fi
}

matches_patterns() {
  local file="$1"
  local task_name="$2"
  local source_label="$3"
  local line flag pattern message
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    IFS="|" read -r flag pattern message <<<"$line"
    [[ -z "$flag" || -z "$pattern" ]] && continue
    if has_pattern "$pattern" "$file"; then
      case "$flag" in
        env_fallback) need_env_fallback=1 ;;
        generic_profile) need_generic_profile=1 ;;
        python_runtime) need_python_runtime=1 ;;
        test_bootstrap) need_test_bootstrap=1 ;;
        ssot_guard) need_ssot_guard=1 ;;
      esac
      signals+=("$message in $source_label for $task_name")
    fi
  done < "$PATTERN_FILE"
}

get_run_summary_exit() {
  local summary_path="$1"
  local exit_line exit_code
  exit_line="$(rg -n "^- exit:" "$summary_path" 2>/dev/null | tail -n 1 | sed -E 's/.*- exit:[[:space:]]*//')"
  if [[ -z "$exit_line" ]]; then
    exit_code="$(rg -n "exit=" "$summary_path" 2>/dev/null | tail -n 1 | sed -E 's/.*exit=([0-9]+).*/\\1/')"
  else
    exit_code="$exit_line"
  fi
  if [[ -z "$exit_code" || ! "$exit_code" =~ ^[0-9]+$ ]]; then
    echo ""
    return 0
  fi
  echo "$exit_code"
}

if [[ ! -d "$TASKS_DIR" ]]; then
  echo "Error: tasks directory not found: $TASKS_DIR" >&2
  exit 2
fi

if [[ -n "$FORCE_TASK" ]]; then
  if [[ ! -d "$FORCE_TASK" ]]; then
    echo "Error: task directory not found: $FORCE_TASK" >&2
    exit 2
  fi
fi

recent_tasks=()
if [[ -n "$FORCE_TASK" ]]; then
  recent_tasks+=("$FORCE_TASK")
else
  while IFS= read -r path; do
    recent_tasks+=("$path")
  done < <(find "$TASKS_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | head -n "$LOOKBACK")
fi

if (( ${#recent_tasks[@]} == 0 )); then
  echo "Error: no task directories found under $TASKS_DIR" >&2
  exit 2
fi

if [[ ! -f "$PATTERN_FILE" ]]; then
  echo "Error: pattern file not found: $PATTERN_FILE" >&2
  exit 2
fi

failed_tasks=()
for task in "${recent_tasks[@]}"; do
  summary="$task/RUN_SUMMARY.md"
  gate_report="$task/GATE_REPORT.md"
  if [[ -f "$summary" ]]; then
    exit_code="$(get_run_summary_exit "$summary")"
    if [[ -n "$exit_code" && "$exit_code" -ne 0 ]]; then
      failed_tasks+=("$task")
      continue
    fi
  fi
  if [[ -f "$gate_report" ]]; then
    if has_pattern "FAIL" "$gate_report"; then
      failed_tasks+=("$task")
      continue
    fi
  fi
done

need_env_fallback=0
need_generic_profile=0
need_python_runtime=0
need_test_bootstrap=0
need_ssot_guard=0
latest_target_repo=""
signals=()
found_self_context=0
observed_tasks=0
skipped_tasks=()

tasks_to_scan=()
if [[ -n "$FORCE_TASK" ]]; then
  tasks_to_scan=("${recent_tasks[@]}")
elif (( ${#failed_tasks[@]} > 0 )); then
  tasks_to_scan=("${failed_tasks[@]}")
else
  tasks_to_scan=("${recent_tasks[@]}")
fi

for task in "${tasks_to_scan[@]}"; do
  target_file="$task/TARGET_REPO"
  if [[ -z "$latest_target_repo" && -f "$target_file" ]]; then
    latest_target_repo="$(head -n 1 "$target_file" | tr -d '\r' | xargs)"
  fi

  goal_path="$task/GOAL.md"
  spec_path="$task/SPEC.md"
  audit_pack_path="$task/AUDIT_PACK.md"
  audit_path="$task/AUDIT.md"
  if [[ ! -f "$goal_path" || ! -f "$spec_path" || ( ! -f "$audit_pack_path" && ! -f "$audit_path" ) ]]; then
    skipped_tasks+=("$(basename "$task") (missing GOAL/SPEC/AUDIT)")
    continue
  fi
  observed_tasks=$((observed_tasks + 1))

  build_report="$task/BUILD_REPORT.md"
  self_context="$task/SELF_CONTEXT.md"
  gate_report="$task/GATE_REPORT.md"

  source_order=("$audit_pack_path" "$gate_report" "$build_report" "$self_context")
  for src in "${source_order[@]}"; do
    [[ ! -f "$src" ]] && continue
    case "$src" in
      */AUDIT_PACK.md) label="AUDIT_PACK.md" ;;
      */GATE_REPORT.md) label="GATE_REPORT.md" ;;
      */BUILD_REPORT.md) label="BUILD_REPORT.md" ;;
      */SELF_CONTEXT.md) label="SELF_CONTEXT.md" ;;
      *) label="$(basename "$src")" ;;
    esac
    if [[ "$label" == "SELF_CONTEXT.md" ]]; then
      found_self_context=1
    fi
    matches_patterns "$src" "$(basename "$task")" "$label"
  done
done

if [[ "$observed_tasks" -eq 0 ]]; then
  echo "Cannot derive improvements without GOAL/SPEC/AUDIT (no eligible tasks found)" >&2
  exit 2
fi

if [[ -z "$latest_target_repo" ]]; then
  latest_target_repo="$ROOT_DIR"
fi

date_tag="$(date +%Y-%m-%d)"
n=1
while :; do
  task_id="$(printf "%s-%s-%04d" "$date_tag" "$PREFIX" "$n")"
  new_task="$TASKS_DIR/$task_id"
  if [[ ! -e "$new_task" ]]; then
    break
  fi
  n=$((n + 1))
done

mkdir -p "$new_task"
printf "%s\n" "$latest_target_repo" > "$new_task/TARGET_REPO"

improvements=()
if [[ "$need_env_fallback" -eq 1 ]]; then
  improvements+=("- Plan段のAPIキー解決を強化（CLAUDE/ANTHROPIC/.env 読込・エラー明確化）")
fi
if [[ "$need_generic_profile" -eq 1 ]]; then
  improvements+=("- Build段のプロファイル判定を汎用化（palcome 固定依存を除去）")
fi
if [[ "$need_python_runtime" -eq 1 ]]; then
  improvements+=("- Python実行前の依存/ランタイム事前チェックを追加")
fi
if [[ "$need_test_bootstrap" -eq 1 ]]; then
  improvements+=("- pytest未導入時のガイド/自動セットアップ導線を追加")
fi
if [[ "$need_ssot_guard" -eq 1 ]]; then
  improvements+=("- SSOT違反を抑止するガード（SPEC/GOAL変更の検知強化と明確なエラー）")
fi
if (( ${#improvements[@]} == 0 )); then
  improvements+=("- 直近ログの失敗傾向を増やせるよう、Build/Gateの観測項目を拡張")
  improvements+=("- 自己改良タスク生成の品質向上（根拠ログへのリンク/要約）")
fi

{
  echo "# GOAL"
  echo
  echo "## Purpose"
  echo "- pipelineが直近実行ログを根拠に、必要な改良点を自動抽出して自己改良を継続できる状態にする。"
  echo
  echo "## Deliverable"
  for item in "${improvements[@]}"; do
    echo "$item"
  done
  echo "- 変更後に 00_run_task --auto で再実行し、結果を確認できる。"
  echo
  echo "## Constraints"
  echo "- Must: tasks/<id>/SPEC.md を手編集しない"
  echo "- Must: SSOT（GOAL/SPEC/AUDIT）運用を維持する"
  echo "- Must not: git push を自動実行しない"
  echo "- Out of scope: 外部サービスの新規導入"
} > "$new_task/GOAL.md"

if (( ${#signals[@]} > 0 )); then
  {
    echo "# DISCOVERY"
    echo
    echo "Generated from recent task reports:"
    echo "- source_priority: AUDIT_PACK.md > GATE_REPORT.md > BUILD_REPORT.md > SELF_CONTEXT.md"
    for s in "${signals[@]}"; do
      echo "- $s"
    done
    if (( ${#failed_tasks[@]} > 0 )); then
      echo
      echo "Preferred failed tasks (from RUN_SUMMARY/GATE_REPORT):"
      for t in "${failed_tasks[@]}"; do
        echo "- $(basename "$t")"
      done
    fi
    if (( ${#skipped_tasks[@]} > 0 )); then
      echo
      echo "Skipped tasks (missing GOAL/SPEC/AUDIT):"
      for s in "${skipped_tasks[@]}"; do
        echo "- $s"
      done
    fi
    if [[ -n "$latest_target_repo" && -d "$latest_target_repo" ]]; then
      echo
      echo "Changed files (git diff --name-only):"
      (
        cd "$latest_target_repo"
        diff_names="$(git diff --name-only HEAD 2>/dev/null || true)"
        if [[ -n "$diff_names" ]]; then
          printf "%s\n" "$diff_names"
        else
          echo "(no uncommitted changes)"
        fi
      )
    fi
  } > "$new_task/DISCOVERY.md"
elif (( ${#skipped_tasks[@]} > 0 )); then
  {
    echo "# DISCOVERY"
    echo
    echo "No signals matched; some tasks were skipped due to missing files:"
    for s in "${skipped_tasks[@]}"; do
      echo "- $s"
    done
    if [[ -n "$latest_target_repo" && -d "$latest_target_repo" ]]; then
      echo
      echo "Changed files (git diff --name-only):"
      (
        cd "$latest_target_repo"
        diff_names="$(git diff --name-only HEAD 2>/dev/null || true)"
        if [[ -n "$diff_names" ]]; then
          printf "%s\n" "$diff_names"
        else
          echo "(no uncommitted changes)"
        fi
      )
    fi
  } > "$new_task/DISCOVERY.md"
fi

echo "Created: $new_task"
echo "TARGET_REPO: $latest_target_repo"

if [[ "$RUN_AUTO" -eq 1 ]]; then
  "$ROOT_DIR/scripts/00_run_task.sh" --auto "$new_task"
fi

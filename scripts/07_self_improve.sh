#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/07_self_improve.sh [--run-auto] [--prefix NAME] [--lookback N]"
  echo ""
  echo "Analyze recent task reports and create a new self-improvement task."
  echo "With --run-auto, immediately run 00_run_task.sh --auto on the created task."
}

RUN_AUTO=0
LOOKBACK=20
PREFIX="self"

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

if [[ ! -d "$TASKS_DIR" ]]; then
  echo "Error: tasks directory not found: $TASKS_DIR" >&2
  exit 2
fi

recent_tasks=()
while IFS= read -r path; do
  recent_tasks+=("$path")
done < <(find "$TASKS_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | head -n "$LOOKBACK")

if (( ${#recent_tasks[@]} == 0 )); then
  echo "Error: no task directories found under $TASKS_DIR" >&2
  exit 2
fi

need_env_fallback=0
need_generic_profile=0
need_python_runtime=0
need_test_bootstrap=0
latest_target_repo=""
signals=()

for task in "${recent_tasks[@]}"; do
  target_file="$task/TARGET_REPO"
  if [[ -z "$latest_target_repo" && -f "$target_file" ]]; then
    latest_target_repo="$(head -n 1 "$target_file" | tr -d '\r' | xargs)"
  fi

  build_report="$task/BUILD_REPORT.md"
  if [[ -f "$build_report" ]]; then
    if rg -q "CLAUDE_API_KEY is required|ANTHROPIC_API_KEY is required" "$build_report"; then
      need_env_fallback=1
      signals+=("Plan fails on missing API key in $(basename "$task")")
    fi
    if rg -q "No module named 'palcome'|observe_jobs missing" "$build_report"; then
      need_generic_profile=1
      signals+=("Build step assumes palcome in $(basename "$task")")
    fi
    if rg -q "pytest not found, skipped" "$build_report"; then
      need_test_bootstrap=1
      signals+=("pytest unavailable in $(basename "$task")")
    fi
    if rg -q "python: command not found|/usr/bin/python: No such file|No module named pip" "$build_report"; then
      need_python_runtime=1
      signals+=("Python runtime/setup issue in $(basename "$task")")
    fi
  fi
done

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
    for s in "${signals[@]}"; do
      echo "- $s"
    done
  } > "$new_task/DISCOVERY.md"
fi

echo "Created: $new_task"
echo "TARGET_REPO: $latest_target_repo"

if [[ "$RUN_AUTO" -eq 1 ]]; then
  "$ROOT_DIR/scripts/00_run_task.sh" --auto "$new_task"
fi


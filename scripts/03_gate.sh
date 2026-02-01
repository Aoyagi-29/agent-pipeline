#!/usr/bin/env bash
set -euo pipefail

MODE="legacy"
TASK_DIR=""

if [[ $# -gt 2 ]]; then
  echo "Error: invalid arguments" >&2
  exit 2
fi

if [[ $# -eq 0 ]]; then
  echo "Error: <task-dir> is required" >&2
  exit 2
fi

case "${1:-}" in
  --clean)
    MODE="clean"
    TASK_DIR="${2:-}"
    ;;
  --clean-only)
    MODE="clean-only"
    TASK_DIR="${2:-}"
    ;;
  --*)
    echo "Error: invalid arguments" >&2
    exit 2
    ;;
  *)
    MODE="legacy"
    TASK_DIR="${1:-}"
    ;;
esac

if [[ -z "$TASK_DIR" ]]; then
  echo "Error: <task-dir> is required" >&2
  exit 2
fi

if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  exit 2
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Error: not inside a git repository: $(pwd)" >&2
  exit 2
fi

clean_artifacts() {
  local path
  for path in "$TASK_DIR/GATE_REPORT.md" "$TASK_DIR/AUDIT_PACK.md" "$TASK_DIR/AUDIT.md"; do
    if [[ -e "$path" ]]; then
      rm -f "$path"
      echo "Removed: $path"
    fi
  done
}

run_gate() {
  REPORT="$TASK_DIR/GATE_REPORT.md"

  fail=0

  write() { printf "%s\n" "$*" >> "$REPORT"; }

  run_section () {
    local title="$1"; shift
    write "## $title"
    write '```'
    if "$@" >> "$REPORT" 2>&1; then
      write '```'
      write ""
    else
      write '```'
      write ""
      fail=1
    fi
  }

  : > "$REPORT"
  write "# Gate Report"
  write ""
  write "## Timestamp"
  date >> "$REPORT"
  write ""
  run_section "Repo: git status --porcelain" git status --porcelain
  run_section "Repo: git diff --stat" git --no-pager diff --stat

  # ---- SSOT check ----
  ssot_files=()
  while IFS= read -r path; do
    [[ -n "$path" ]] && ssot_files+=("$path")
  done < <(git diff --name-only HEAD -- "$TASK_DIR/SPEC.md" "$TASK_DIR/GOAL.md")

  if (( ${#ssot_files[@]} > 0 )); then
    fail=1
    write "## SSOT Violation"
    write "FAILの理由: SSOT 違反"
    write "以下の禁止ファイルが変更されています:"
    for path in "${ssot_files[@]}"; do
      write "- $path"
    done
    write ""
    write "## Action Required"
    write "SPEC.md / GOAL.md の変更を取り消してください。"
    write ""
  else
    write "## SSOT Check"
    write "SPEC.md および GOAL.md は変更されていません。"
    write ""
  fi

  # ---- Node ----
  if [[ -f package.json ]]; then
    if command -v npm >/dev/null 2>&1; then
      run_section "Node: npm -v" npm -v
      # test
      if npm run | grep -qE '(^| )test'; then
        run_section "Node: npm test" npm test
      else
        write "## Node: npm test"
        write '```'
        write "(skip) no test script"
        write '```'
        write ""
      fi
      # lint (optional)
      if npm run | grep -qE '(^| )lint'; then
        run_section "Node: npm run lint" npm run lint
      fi
    else
      write "## Node"
      write '```'
      write "(fail) npm not found"
      write '```'
      write ""
      fail=1
    fi
  fi

  # ---- Python ----
  if [[ -f pyproject.toml || -f requirements.txt ]]; then
    run_section "Python: python --version" python --version

    if command -v pytest >/dev/null 2>&1; then
      run_section "Python: pytest -q" pytest -q
    else
      write "## Python: pytest"
      write '```'
      write "(skip) pytest not found"
      write '```'
      write ""
    fi

    if command -v ruff >/dev/null 2>&1; then
      run_section "Python: ruff check ." ruff check .
    fi

    if command -v mypy >/dev/null 2>&1 && [[ -f pyproject.toml ]]; then
      run_section "Python: mypy ." mypy .
    fi
  fi

  write "## Result"
  if [[ "$fail" -eq 0 ]]; then
    write "- PASS"
    return 0
  else
    write "- FAIL"
    return 1
  fi
}

case "$MODE" in
  legacy)
    run_gate
    exit $?
    ;;
  clean)
    gate_exit=0
    if run_gate; then
      gate_exit=0
    else
      gate_exit=$?
    fi
    clean_artifacts
    exit "$gate_exit"
    ;;
  clean-only)
    clean_artifacts
    exit 0
    ;;
esac

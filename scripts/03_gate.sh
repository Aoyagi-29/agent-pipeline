#!/usr/bin/env bash
set -euo pipefail

TASK_DIR="${1:-}"
if [[ -z "$TASK_DIR" ]]; then
  echo "usage: scripts/03_gate.sh tasks/<id>" >&2
  exit 2
fi

if [[ ! -d "$TASK_DIR" ]]; then
  echo "error: task dir not found: $TASK_DIR" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not a git repository" >&2
  exit 2
fi

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
  exit 0
else
  write "- FAIL"
  exit 1
fi

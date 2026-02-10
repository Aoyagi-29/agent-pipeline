#!/usr/bin/env bash
set -euo pipefail

MODE="legacy"
TASK_DIR=""
REQUIRE_CLEAN_TREE=0

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
  --require-clean-tree)
    MODE="require-clean-tree"
    REQUIRE_CLEAN_TREE=1
    TASK_DIR="${2:-}"
    ;;
  --*)
    echo "Error: unknown option: ${1:-}" >&2
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

require_clean_tree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree is not clean" >&2
    return 1
  fi
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

  # ---- SSOT check ----
  ssot_files=()
  while IFS= read -r path; do
    [[ -n "$path" ]] && ssot_files+=("$path")
  done < <(git diff --name-only HEAD -- "$TASK_DIR/SPEC.md" "$TASK_DIR/GOAL.md")

  snapshot_path="$TASK_DIR/.SSOT_SNAPSHOT"
  snapshot_mismatch=0
  if [[ -f "$snapshot_path" ]]; then
    if command -v rg >/dev/null 2>&1; then
      expected_goal="$(rg -n '^GOAL\.md ' "$snapshot_path" 2>/dev/null | awk '{print $2}')"
      expected_spec="$(rg -n '^SPEC\.md ' "$snapshot_path" 2>/dev/null | awk '{print $2}')"
    else
      expected_goal="$(grep -E '^GOAL\.md ' "$snapshot_path" 2>/dev/null | awk '{print $2}')"
      expected_spec="$(grep -E '^SPEC\.md ' "$snapshot_path" 2>/dev/null | awk '{print $2}')"
    fi
    if [[ -n "$expected_goal" && -f "$TASK_DIR/GOAL.md" ]]; then
      current_goal="$(sha256sum "$TASK_DIR/GOAL.md" | awk '{print $1}')"
      if [[ "$current_goal" != "$expected_goal" ]]; then
        snapshot_mismatch=1
      fi
    fi
    if [[ -n "$expected_spec" && -f "$TASK_DIR/SPEC.md" ]]; then
      current_spec="$(sha256sum "$TASK_DIR/SPEC.md" | awk '{print $1}')"
      if [[ "$current_spec" != "$expected_spec" ]]; then
        snapshot_mismatch=1
      fi
    fi
  fi

  if (( ${#ssot_files[@]} > 0 )) || [[ "$snapshot_mismatch" -eq 1 ]]; then
    write "## SSOT Violation"
    write "FAIL: SPEC.md and GOAL.md are read-only SSOT artifacts. Revert changes or regenerate before task execution."
    write ""
    if [[ "$snapshot_mismatch" -eq 1 ]]; then
      write "Detected mismatch against .SSOT_SNAPSHOT (files changed after Plan)."
      write ""
    fi
    write "Changed files:"
    for path in "${ssot_files[@]}"; do
      write "- $path"
    done
    write ""
    write "## Action Required"
    write "Run: git checkout HEAD -- tasks/<id>/SPEC.md tasks/<id>/GOAL.md (if tracked)"
    write "Or delete $TASK_DIR/.SSOT_SNAPSHOT and regenerate SPEC.md via Plan."
    write ""
    write "## Result"
    write "- FAIL (SSOT violation detected)"
    return 1
  fi

  run_section "Repo: git status --porcelain" git status --porcelain
  run_section "Repo: git diff --stat" git --no-pager diff --stat

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
    clean_status="$(git status --porcelain)"
    if [[ -n "$clean_status" ]]; then
      echo "Error: working tree is not clean (--clean requires a clean working tree)" >&2
      echo "$clean_status" >&2
      exit 2
    fi
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
  require-clean-tree)
    if ! require_clean_tree; then
      exit 1
    fi
    run_gate
    exit $?
    ;;
esac

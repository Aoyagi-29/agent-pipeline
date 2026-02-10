#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/06_build_run_codex.sh [--max-iterations N] <task-dir>"
  echo "Example: scripts/06_build_run_codex.sh --max-iterations 5 tasks/2026-02-09-0001"
}

MAX_ITERATIONS=5
TASK_DIR=""

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --help|-h)
      usage
      exit 0
      ;;
    --max-iterations)
      if [[ $# -lt 2 ]]; then
        echo "Error: --max-iterations requires a value" >&2
        exit 2
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --*)
      echo "Error: unknown option: ${1:-}" >&2
      exit 2
      ;;
    *)
      if [[ -n "$TASK_DIR" ]]; then
        echo "Error: invalid arguments" >&2
        exit 2
      fi
      TASK_DIR="$1"
      shift
      ;;
  esac
done

if [[ -z "$TASK_DIR" ]]; then
  usage >&2
  exit 2
fi

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$MAX_ITERATIONS" -le 0 ]]; then
  echo "Error: --max-iterations must be a positive integer" >&2
  exit 2
fi

if [[ ! -d "$TASK_DIR" ]]; then
  echo "Error: directory not found: $TASK_DIR" >&2
  exit 2
fi

SPEC_PATH="$TASK_DIR/SPEC.md"
TARGET_REPO_FILE="$TASK_DIR/TARGET_REPO"
BUILD_REPORT="$TASK_DIR/BUILD_REPORT.md"

if [[ ! -f "$SPEC_PATH" ]]; then
  echo "Error: SPEC.md not found in $TASK_DIR" >&2
  exit 2
fi
if [[ ! -f "$TARGET_REPO_FILE" ]]; then
  echo "Error: TARGET_REPO not found in $TASK_DIR" >&2
  exit 2
fi

TARGET_REPO="$(head -n 1 "$TARGET_REPO_FILE" | tr -d '\r' | xargs)"
if [[ -z "$TARGET_REPO" ]]; then
  echo "Error: TARGET_REPO is empty" >&2
  exit 2
fi
if [[ "${TARGET_REPO:0:1}" != "/" ]]; then
  echo "Error: TARGET_REPO must be an absolute WSL path: $TARGET_REPO" >&2
  exit 2
fi
if [[ ! -d "$TARGET_REPO" ]]; then
  echo "Error: TARGET_REPO directory not found: $TARGET_REPO" >&2
  exit 2
fi
if ! git -C "$TARGET_REPO" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Error: TARGET_REPO is not a git repository: $TARGET_REPO" >&2
  exit 2
fi

sanitize_output() {
  sed -E \
    -e 's/(CLAUDE_API_KEY|OPENAI_API_KEY|SUPABASE_SERVICE_ROLE_KEY|service_role|api[_-]?key)[^[:space:]]*/\1=[REDACTED]/Ig' \
    -e 's#(/home/[^[:space:]]*/\.ssh/[^[:space:]]*)#[REDACTED_PATH]#g' \
    -e 's#([^[:space:]]*id_rsa[^[:space:]]*)#[REDACTED_KEYFILE]#g'
}

append_report_block() {
  local title="$1"
  local file="$2"
  {
    echo "### $title"
    echo '```'
    sanitize_output < "$file"
    echo '```'
    echo
  } >> "$BUILD_REPORT"
}

detect_build_profile() {
  if [[ -f "$TARGET_REPO/pyproject.toml" || -f "$TARGET_REPO/requirements.txt" || -f "$TARGET_REPO/setup.py" || -f "$TARGET_REPO/setup.cfg" ]]; then
    echo "python-package"
    return
  fi
  if [[ -f "$TARGET_REPO/package.json" ]]; then
    echo "node-package"
    return
  fi
  if [[ -f "$TARGET_REPO/Makefile" ]]; then
    echo "make-based"
    return
  fi
  echo "generic"
}

detect_python_project() {
  if [[ -f "$TARGET_REPO/pyproject.toml" || -f "$TARGET_REPO/requirements.txt" || -f "$TARGET_REPO/setup.py" || -f "$TARGET_REPO/setup.cfg" || -f "$TARGET_REPO/Pipfile" ]]; then
    return 0
  fi
  if command -v rg >/dev/null 2>&1; then
    rg --files -g '*.py' "$TARGET_REPO" >/dev/null 2>&1 && return 0
  fi
  return 1
}

detect_python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
    return
  fi
  if command -v python >/dev/null 2>&1; then
    echo "python"
    return
  fi
  echo ""
}

has_pyproject_build_system() {
  if [[ ! -f "$TARGET_REPO/pyproject.toml" ]]; then
    return 1
  fi
  if command -v rg >/dev/null 2>&1; then
    rg -n "^[[:space:]]*\\[build-system\\]" "$TARGET_REPO/pyproject.toml" >/dev/null 2>&1
    return $?
  fi
  grep -qE '^[[:space:]]*\[build-system\]' "$TARGET_REPO/pyproject.toml"
}

run_cmd() {
  local title="$1"
  shift
  local out
  out="$(mktemp)"
  set +e
  {
    echo "+ $*"
    (cd "$TARGET_REPO" && "$@")
  } >"$out" 2>&1
  local rc=$?
  set -e
  append_report_block "$title (exit=$rc)" "$out"
  rm -f "$out"
  return "$rc"
}

observe_and_check() {
  local out_file="$1"
  python3 - "$out_file" <<'PY'
import json
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
records = []

def norm(v):
    if v is None:
        return None
    if isinstance(v, str):
        s = v.strip().lower()
        if s in {"", "null", "none"}:
            return None
        return v
    return v

try:
    parsed = json.loads(text)
    if isinstance(parsed, list):
        records = [x for x in parsed if isinstance(x, dict)]
    elif isinstance(parsed, dict):
        if isinstance(parsed.get("jobs"), list):
            records = [x for x in parsed["jobs"] if isinstance(x, dict)]
        else:
            records = [parsed]
except Exception:
    # Fallback: scan text for status words
    if re.search(r"\bsucceeded\b", text, re.IGNORECASE):
        # unknown structure; treat as not enough evidence
        sys.exit(1)
    sys.exit(1)

if not records:
    sys.exit(1)

latest = records[0]
status = str(latest.get("status", "")).strip().lower()
error_code = norm(latest.get("error_code"))
scoring_result = latest.get("scoring_result")

if status != "succeeded":
    sys.exit(1)
if error_code is not None:
    sys.exit(1)
if scoring_result in (None, "", {}, []):
    sys.exit(1)
sys.exit(0)
PY
}

try_fix_step() {
  local iter="$1"
  local fix_cmd="${CODEX_FIX_CMD:-}"
  {
    echo "### Fix Attempt (iteration=$iter)"
    if [[ -z "$fix_cmd" ]]; then
      echo "- skipped: CODEX_FIX_CMD is not set"
    else
      echo "- running CODEX_FIX_CMD in TARGET_REPO"
      echo '```'
      echo "$fix_cmd"
      echo '```'
      local out
      out="$(mktemp)"
      if (cd "$TARGET_REPO" && bash -lc "$fix_cmd") >"$out" 2>&1; then
        echo "- result: success"
      else
        echo "- result: failed (continuing)"
      fi
      echo '```'
      sanitize_output < "$out"
      echo '```'
      rm -f "$out"
    fi
    echo
  } >> "$BUILD_REPORT"
}

{
  echo "# BUILD REPORT"
  echo
  echo "- task_dir: $TASK_DIR"
  echo "- target_repo: $TARGET_REPO"
  echo "- max_iterations: $MAX_ITERATIONS"
  BUILD_PROFILE="$(detect_build_profile)"
  echo "- build_profile: $BUILD_PROFILE"
  echo "- generated_at: $(date -Iseconds 2>/dev/null || date)"
  echo
} > "$BUILD_REPORT"

PYTHON_PROJECT=0
if detect_python_project; then
  PYTHON_PROJECT=1
fi

PYTHON_CMD="$(detect_python_cmd)"
PYTHON_VERSION=""
if [[ "$PYTHON_PROJECT" -eq 1 && -n "$PYTHON_CMD" ]]; then
  PYTHON_VERSION="$("$PYTHON_CMD" --version 2>&1 | tr -d '\r')"
fi

HAS_BUILD_SYSTEM=0
if has_pyproject_build_system; then
  HAS_BUILD_SYSTEM=1
fi

PIP_CMD=()
PIP_VERSION=""
if [[ "$PYTHON_PROJECT" -eq 1 && -n "$PYTHON_CMD" ]]; then
  if "$PYTHON_CMD" -m pip --version >/dev/null 2>&1; then
    PIP_CMD=("$PYTHON_CMD" -m pip)
    PIP_VERSION="$("$PYTHON_CMD" -m pip --version 2>&1 | tr -d '\r')"
  elif command -v pip >/dev/null 2>&1; then
    PIP_CMD=(pip)
    PIP_VERSION="$(pip --version 2>&1 | tr -d '\r')"
  fi
fi

{
  echo "## Precheck"
  if [[ "$PYTHON_PROJECT" -eq 1 ]]; then
    if [[ -n "$PYTHON_CMD" && -n "$PYTHON_VERSION" ]]; then
      echo "- python: found ($PYTHON_VERSION)"
    else
      echo "- python: missing"
      echo "- error: Python interpreter not found. Install Python 3.8+ to proceed."
    fi
    if [[ -n "$PIP_VERSION" ]]; then
      echo "- pip: found ($PIP_VERSION)"
    elif [[ "$HAS_BUILD_SYSTEM" -eq 1 ]]; then
      echo "- pip: missing"
      echo "- error: pip not found. Install pip to build Python packages."
    else
      echo "- pip: missing"
      echo "- note: pip missing; required if you need to install test deps"
    fi
  else
    echo "- python: (skip) not a Python project"
    echo "- pip: (skip) not a Python project"
  fi
  echo
} >> "$BUILD_REPORT"

if [[ "$PYTHON_PROJECT" -eq 1 ]]; then
  if [[ -z "$PYTHON_CMD" || -z "$PYTHON_VERSION" ]]; then
    echo "Error: Python interpreter not found. Install Python 3.8+ to proceed." >&2
    exit 2
  fi
  if [[ "$HAS_BUILD_SYSTEM" -eq 1 && -z "$PIP_VERSION" ]]; then
    echo "Error: pip not found. Install pip to build Python packages." >&2
    exit 2
  fi
fi

PYTEST_FOUND=0
PYTEST_RUN_CMD=()
PYTEST_VERSION=""
if [[ "$PYTHON_PROJECT" -eq 1 ]]; then
  if PYTEST_OUTPUT="$("$PYTHON_CMD" -m pytest --version 2>/dev/null)"; then
    PYTEST_FOUND=1
    PYTEST_VERSION="$(printf "%s" "$PYTEST_OUTPUT" | head -n 1 | tr -d '\r' | awk '{print $2}')"
    if [[ -z "$PYTEST_VERSION" ]]; then
      PYTEST_VERSION="$(printf "%s" "$PYTEST_OUTPUT" | head -n 1 | tr -d '\r')"
    fi
    PYTEST_RUN_CMD=("$PYTHON_CMD" -m pytest -q)
  fi
fi

PYTEST_BOOTSTRAP="${CODEX_BOOTSTRAP_PYTEST:-${PYTEST_BOOTSTRAP:-}}"
if [[ "$PYTHON_PROJECT" -eq 1 && "$PYTEST_FOUND" -eq 0 && -n "$PYTEST_BOOTSTRAP" ]]; then
  {
    echo "## Pytest Bootstrap"
    if [[ "${#PIP_CMD[@]}" -eq 0 ]]; then
      echo "- skipped: pip not available for bootstrap"
    else
      echo "- running: ${PIP_CMD[*]} install -U pytest"
      echo '```'
      out="$(mktemp)"
      if (cd "$TARGET_REPO" && "${PIP_CMD[@]}" install -U pytest) >"$out" 2>&1; then
        echo "- result: success"
      else
        echo "- result: failed"
      fi
      echo '```'
      sanitize_output < "$out"
      echo '```'
      rm -f "$out"
    fi
    echo
  } >> "$BUILD_REPORT"

  if PYTEST_OUTPUT="$("$PYTHON_CMD" -m pytest --version 2>/dev/null)"; then
    PYTEST_FOUND=1
    PYTEST_VERSION="$(printf "%s" "$PYTEST_OUTPUT" | head -n 1 | tr -d '\r' | awk '{print $2}')"
    if [[ -z "$PYTEST_VERSION" ]]; then
      PYTEST_VERSION="$(printf "%s" "$PYTEST_OUTPUT" | head -n 1 | tr -d '\r')"
    fi
    PYTEST_RUN_CMD=("$PYTHON_CMD" -m pytest -q)
  fi
fi

{
  echo "## Pytest Status"
  if [[ "$PYTHON_PROJECT" -eq 0 ]]; then
    echo "- (skip) pytest not applicable"
  elif [[ "$PYTEST_FOUND" -eq 1 ]]; then
    echo "- found (version ${PYTEST_VERSION})"
  else
    echo "- not found; install via: python -m pip install pytest"
    echo "- To enable tests, run: python -m pip install pytest (or pip install -e .[dev]), then re-run: ./scripts/00_run_task.sh --auto $TASK_DIR"
    echo "- Optional auto-setup: set CODEX_BOOTSTRAP_PYTEST=1 and re-run to install pytest automatically"
  fi
  echo
} >> "$BUILD_REPORT"

if [[ "$PYTHON_PROJECT" -eq 1 ]]; then
  if [[ "$PYTEST_FOUND" -eq 0 ]]; then
    echo "WARN: pytest not available. Install via: python -m pip install pytest (or pip install -e .[dev])" >&2
    echo "WARN: To enable tests, run: python -m pip install pytest (or pip install -e .[dev]), then re-run: ./scripts/00_run_task.sh --auto $TASK_DIR" >&2
    echo "WARN: Optional auto-setup: set CODEX_BOOTSTRAP_PYTEST=1 and re-run" >&2
  fi
fi

converged=0
for ((i=1; i<=MAX_ITERATIONS; i++)); do
  {
    echo "## Iteration $i/$MAX_ITERATIONS"
    echo
  } >> "$BUILD_REPORT"

  if [[ "$PYTHON_PROJECT" -eq 1 && "$PYTEST_FOUND" -eq 1 ]]; then
    run_cmd "pytest -q" "${PYTEST_RUN_CMD[@]}" || true
  elif [[ "$PYTHON_PROJECT" -eq 1 ]]; then
    echo "- pytest not found, skipped" >> "$BUILD_REPORT"
    echo >> "$BUILD_REPORT"
  fi

  iter_ok=1
  ran_any_check=0

  if [[ -d "$TARGET_REPO/scripts" ]]; then
    ran_any_check=1
    run_cmd "bash -n scripts/*.sh" bash -lc 'shopt -s nullglob; files=(scripts/*.sh); if (( ${#files[@]} == 0 )); then echo "(skip) no scripts/*.sh"; exit 0; fi; bash -n "${files[@]}"' || iter_ok=0
  fi

  if [[ -f "$TARGET_REPO/pyproject.toml" || -f "$TARGET_REPO/requirements.txt" ]]; then
    ran_any_check=1
    run_cmd "$PYTHON_CMD -m compileall -q ." "$PYTHON_CMD" -m compileall -q . || iter_ok=0
  fi

  if [[ "$ran_any_check" -eq 0 ]]; then
    run_cmd "git status --porcelain" git status --porcelain || iter_ok=0
  fi

  if [[ "$iter_ok" -eq 1 ]]; then
    converged=1
    break
  fi

  try_fix_step "$i"
done

if [[ "$converged" -eq 1 ]]; then
  {
    echo "## Result"
    echo "- converged: yes"
  } >> "$BUILD_REPORT"
  exit 0
fi

{
  echo "## Result"
  echo "- converged: no"
  echo "- reason: latest observation did not satisfy success criteria"
} >> "$BUILD_REPORT"
exit 1

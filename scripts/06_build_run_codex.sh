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
  echo "- generated_at: $(date -Iseconds 2>/dev/null || date)"
  echo
} > "$BUILD_REPORT"

if [[ ! -f "$TARGET_REPO/palcome/tools/observe_jobs.py" ]]; then
  {
    echo "## Precheck"
    echo "- observe_jobs missing: $TARGET_REPO/palcome/tools/observe_jobs.py"
    echo "- expected command: python -m palcome.tools.observe_jobs --limit 5"
    echo
  } >> "$BUILD_REPORT"
fi

converged=0
for ((i=1; i<=MAX_ITERATIONS; i++)); do
  {
    echo "## Iteration $i/$MAX_ITERATIONS"
    echo
  } >> "$BUILD_REPORT"

  if command -v pytest >/dev/null 2>&1; then
    run_cmd "pytest -q" pytest -q || true
  else
    echo "- pytest not found, skipped" >> "$BUILD_REPORT"
    echo >> "$BUILD_REPORT"
  fi

  run_cmd "python -m palcome.worker --once" python -m palcome.worker --once || true

  obs_out="$(mktemp)"
  (cd "$TARGET_REPO" && python -m palcome.tools.observe_jobs --limit 5) >"$obs_out" 2>&1 || true
  append_report_block "python -m palcome.tools.observe_jobs --limit 5" "$obs_out"

  if observe_and_check "$obs_out"; then
    converged=1
    rm -f "$obs_out"
    break
  fi
  rm -f "$obs_out"
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

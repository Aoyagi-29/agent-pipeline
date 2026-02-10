#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/05_codex_implement.sh <task-dir>"
  echo ""
  echo "Run Codex implementation step based on tasks/<id>/SPEC.md in TARGET_REPO."
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

SPEC_PATH="$TASK_DIR/SPEC.md"
TARGET_REPO_FILE="$TASK_DIR/TARGET_REPO"
GOAL_PATH="$TASK_DIR/GOAL.md"
SELF_CONTEXT_PATH="$TASK_DIR/SELF_CONTEXT.md"
IMPLEMENT_REPORT="$TASK_DIR/IMPLEMENT_REPORT.md"

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
    -e 's/(CLAUDE_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|SUPABASE_SERVICE_ROLE_KEY|service_role|api[_-]?key)[^[:space:]]*/\1=[REDACTED]/Ig' \
    -e 's#(/home/[^[:space:]]*/\.ssh/[^[:space:]]*)#[REDACTED_PATH]#g' \
    -e 's#([^[:space:]]*id_rsa[^[:space:]]*)#[REDACTED_KEYFILE]#g'
}

prompt_file="$(mktemp)"
out_file="$(mktemp)"
cleanup() {
  rm -f "$prompt_file" "$out_file"
}
trap cleanup EXIT

{
  echo "You are a coding agent. Implement the requested work in the target repository."
  echo
  echo "Hard constraints:"
  echo "- Follow SPEC.md below."
  echo "- Do NOT edit tasks/<id>/SPEC.md."
  echo "- Do NOT run git push."
  echo "- Make code changes only in TARGET_REPO."
  echo "- Run relevant validation commands and include concise summary."
  echo
  if [[ -f "$GOAL_PATH" ]]; then
    echo "GOAL.md:"
    echo '```'
    cat "$GOAL_PATH"
    echo '```'
    echo
  fi
  echo "SPEC.md:"
  echo '```'
  cat "$SPEC_PATH"
  echo '```'
  echo
  if [[ -f "$SELF_CONTEXT_PATH" ]]; then
    echo "SELF_CONTEXT.md (reference):"
    echo '```'
    sed -n '1,220p' "$SELF_CONTEXT_PATH"
    echo '```'
    echo
  fi
} > "$prompt_file"

{
  echo "# IMPLEMENT REPORT"
  echo
  echo "- task_dir: $TASK_DIR"
  echo "- target_repo: $TARGET_REPO"
  echo "- generated_at: $(date -Iseconds 2>/dev/null || date)"
  if [[ -n "${CODEX_IMPLEMENT_CMD:-}" ]]; then
    echo "- mode: CODEX_IMPLEMENT_CMD override"
    echo "- command: ${CODEX_IMPLEMENT_CMD}"
  else
    echo "- mode: codex exec --full-auto"
    echo "- command: codex exec --full-auto -"
  fi
  echo
} > "$IMPLEMENT_REPORT"

set +e
# --- load repo .env for automation-only codex exec ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.env"
  set +a
fi
: "${OPENAI_BASE_URL:=https://api.openai.com/v1}"
CODEX_ALLOW_API_KEY="${CODEX_ALLOW_API_KEY:-}"
case "${CODEX_ALLOW_API_KEY}" in
  1|true|TRUE|yes|YES) CODEX_ALLOW_API_KEY=1 ;;
  *) CODEX_ALLOW_API_KEY=0 ;;
esac

# record to IMPLEMENT_REPORT (no secret value)
{
  echo "-- OPENAI_BASE_URL=${OPENAI_BASE_URL:-<empty>}"
  echo "-- CODEX_ALLOW_API_KEY=${CODEX_ALLOW_API_KEY}"
  if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
    echo "-- OPENAI_API_KEY=${OPENAI_API_KEY:+SET}${OPENAI_API_KEY:-NOT_SET}"
  else
    echo "-- OPENAI_API_KEY=IGNORED"
  fi
} >> "$IMPLEMENT_REPORT"
# ----------------------------------------------------

if [[ -n "${CODEX_IMPLEMENT_CMD:-}" ]]; then
  if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
    (cd "$TARGET_REPO" && OPENAI_API_KEY="${OPENAI_API_KEY:-}" OPENAI_BASE_URL="$OPENAI_BASE_URL" bash -lc "${CODEX_IMPLEMENT_CMD}") >"$out_file" 2>&1
  else
    (cd "$TARGET_REPO" && env -u OPENAI_API_KEY OPENAI_BASE_URL="$OPENAI_BASE_URL" bash -lc "${CODEX_IMPLEMENT_CMD}") >"$out_file" 2>&1
  fi
  rc=$?
else
  if ! command -v codex >/dev/null 2>&1; then
    echo "Error: codex command not found (or set CODEX_IMPLEMENT_CMD)" >&2
    rc=2
    {
      echo "### Implementation Command (exit=2)"
      echo '```'
      echo "codex command not found"
      echo '```'
      echo
    } >> "$IMPLEMENT_REPORT"
    set -e
    exit 2
  fi
  if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
    (cd "$TARGET_REPO" && OPENAI_API_KEY="${OPENAI_API_KEY:-}" OPENAI_BASE_URL="$OPENAI_BASE_URL" codex exec --full-auto - < "$prompt_file") >"$out_file" 2>&1
  else
    (cd "$TARGET_REPO" && env -u OPENAI_API_KEY OPENAI_BASE_URL="$OPENAI_BASE_URL" codex exec --full-auto - < "$prompt_file") >"$out_file" 2>&1
  fi
  rc=$?
fi
set -e

{
  echo "### Implementation Command (exit=$rc)"
  echo '```'
  sanitize_output < "$out_file"
  echo '```'
  echo
} >> "$IMPLEMENT_REPORT"

if [[ "$rc" -ne 0 ]]; then
  if rg -q "Missing scopes: api\\.responses\\.write" "$out_file" >/dev/null 2>&1; then
    {
      echo "### Codex Auth Hint"
      echo "- Detected 401 Unauthorized with missing scope: api.responses.write."
      echo "- This indicates the current Codex auth lacks required API scopes."
      if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
        echo "- Check that OPENAI_API_KEY has the responses.write scope and proper org/project role."
      else
        echo "- Options:"
        echo "  - Re-authenticate: run \`codex logout\` then \`codex login\` to refresh ChatGPT auth."
        echo "  - Or set \`CODEX_ALLOW_API_KEY=1\` and provide a properly scoped OPENAI_API_KEY."
      fi
      echo
    } >> "$IMPLEMENT_REPORT"
  fi
fi

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
exit 0

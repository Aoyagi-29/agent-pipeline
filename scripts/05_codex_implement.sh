#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/05_codex_implement.sh <task-dir>"
  echo ""
  echo "Run implementation step based on tasks/<id>/SPEC.md in TARGET_REPO."
  echo "Default backend: Pi (openai-codex / gpt-5.5 / xhigh)."
  echo "Override via AGENT_BACKEND, AGENT_MODEL, AGENT_THINKING, CODEX_MODEL,"
  echo "or full command overrides PI_IMPLEMENT_CMD / CODEX_IMPLEMENT_CMD."
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/agent_model.sh
source "${SCRIPT_DIR}/lib/agent_model.sh"

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

# --- load repo .env for automation ---
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.env"
  set +a
fi

# Ensure user-local pi is visible
if [[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

: "${OPENAI_BASE_URL:=https://api.openai.com/v1}"
CODEX_ALLOW_API_KEY="${CODEX_ALLOW_API_KEY:-}"
case "${CODEX_ALLOW_API_KEY}" in
  1|true|TRUE|yes|YES) CODEX_ALLOW_API_KEY=1 ;;
  *) CODEX_ALLOW_API_KEY=0 ;;
esac

if [[ -n "${AGENT_THINKING+x}" && -n "${AGENT_THINKING:-}" ]]; then
  AGENT_THINKING_SET=1
fi
agent_model_defaults

BACKEND="$(agent_resolve_backend 2>/dev/null || true)"
if [[ -z "$BACKEND" || "$BACKEND" == "missing" ]]; then
  BACKEND="missing"
fi

# Full command overrides take precedence
OVERRIDE_CMD=""
OVERRIDE_LABEL=""
if [[ -n "${PI_IMPLEMENT_CMD:-}" && "$BACKEND" == "pi" ]]; then
  OVERRIDE_CMD="$PI_IMPLEMENT_CMD"
  OVERRIDE_LABEL="PI_IMPLEMENT_CMD"
elif [[ -n "${CODEX_IMPLEMENT_CMD:-}" ]]; then
  OVERRIDE_CMD="$CODEX_IMPLEMENT_CMD"
  OVERRIDE_LABEL="CODEX_IMPLEMENT_CMD"
  BACKEND="custom"
fi

{
  echo "# IMPLEMENT REPORT"
  echo
  echo "- task_dir: $TASK_DIR"
  echo "- target_repo: $TARGET_REPO"
  echo "- generated_at: $(date -Iseconds 2>/dev/null || date)"
  echo "- AGENT_BACKEND=${AGENT_BACKEND}"
  echo "- resolved_backend=${BACKEND}"
  echo "- AGENT_PROVIDER=${AGENT_PROVIDER}"
  echo "- AGENT_MODEL=${AGENT_MODEL}"
  echo "- AGENT_THINKING=${AGENT_THINKING}"
  echo "- CODEX_MODEL=${CODEX_MODEL}"
  if [[ -n "$OVERRIDE_CMD" ]]; then
    echo "- mode: ${OVERRIDE_LABEL} override"
    echo "- command: ${OVERRIDE_CMD}"
  elif [[ "$BACKEND" == "pi" ]]; then
    echo "- mode: pi -p --model ${AGENT_MODEL} --thinking ${AGENT_THINKING}"
    echo "- command: pi -p --model ${AGENT_MODEL} --thinking ${AGENT_THINKING} @prompt"
  elif [[ "$BACKEND" == "codex" ]]; then
    echo "- mode: codex exec --full-auto"
    echo "- command: codex exec --full-auto --model ${CODEX_MODEL} -"
  else
    echo "- mode: unresolved"
  fi
  echo
  echo "-- OPENAI_BASE_URL=${OPENAI_BASE_URL:-<empty>}"
  echo "-- CODEX_ALLOW_API_KEY=${CODEX_ALLOW_API_KEY}"
  if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
      echo "-- OPENAI_API_KEY=SET"
    else
      echo "-- OPENAI_API_KEY=NOT_SET"
    fi
  else
    echo "-- OPENAI_API_KEY=IGNORED"
  fi
  echo
} > "$IMPLEMENT_REPORT"

run_with_optional_api_key() {
  # $1 = working directory command string via bash -lc, or use remaining args
  if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
    (cd "$TARGET_REPO" && OPENAI_API_KEY="${OPENAI_API_KEY:-}" OPENAI_BASE_URL="$OPENAI_BASE_URL" "$@")
  else
    (cd "$TARGET_REPO" && env -u OPENAI_API_KEY OPENAI_BASE_URL="$OPENAI_BASE_URL" "$@")
  fi
}

set +e
rc=2
if [[ -n "$OVERRIDE_CMD" ]]; then
  if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
    (cd "$TARGET_REPO" && OPENAI_API_KEY="${OPENAI_API_KEY:-}" OPENAI_BASE_URL="$OPENAI_BASE_URL" bash -lc "${OVERRIDE_CMD}") >"$out_file" 2>&1
  else
    (cd "$TARGET_REPO" && env -u OPENAI_API_KEY OPENAI_BASE_URL="$OPENAI_BASE_URL" bash -lc "${OVERRIDE_CMD}") >"$out_file" 2>&1
  fi
  rc=$?
elif [[ "$BACKEND" == "pi" ]]; then
  if ! command -v pi >/dev/null 2>&1; then
    echo "Error: pi command not found. Run: ./scripts/09_setup_pi.sh" >&2
    {
      echo "### Implementation Command (exit=2)"
      echo '```'
      echo "pi command not found"
      echo '```'
      echo
    } >> "$IMPLEMENT_REPORT"
    set -e
    exit 2
  fi
  # Prefer @file so large SPEC prompts do not hit ARG_MAX.
  # Run from REPO_ROOT so project .pi/settings.json applies; TARGET_REPO is in the prompt.
  # Explicit --model/--thinking always win over settings defaults (orchestration control).
  local_pi_cwd="$REPO_ROOT"
  if [[ -f "$TARGET_REPO/.pi/settings.json" ]]; then
    local_pi_cwd="$TARGET_REPO"
  fi
  if [[ "$CODEX_ALLOW_API_KEY" -eq 1 ]]; then
    (cd "$local_pi_cwd" && OPENAI_API_KEY="${OPENAI_API_KEY:-}" OPENAI_BASE_URL="$OPENAI_BASE_URL" \
      pi -p --model "$AGENT_MODEL" --thinking "$AGENT_THINKING" \
      @"$prompt_file" "Implement the work described in the attached prompt. Follow all hard constraints. Work in TARGET_REPO: $TARGET_REPO") >"$out_file" 2>&1
  else
    (cd "$local_pi_cwd" && env -u OPENAI_API_KEY OPENAI_BASE_URL="$OPENAI_BASE_URL" \
      pi -p --model "$AGENT_MODEL" --thinking "$AGENT_THINKING" \
      @"$prompt_file" "Implement the work described in the attached prompt. Follow all hard constraints. Work in TARGET_REPO: $TARGET_REPO") >"$out_file" 2>&1
  fi
  rc=$?
elif [[ "$BACKEND" == "codex" ]]; then
  if ! command -v codex >/dev/null 2>&1; then
    echo "Error: codex command not found (or set AGENT_BACKEND=pi / CODEX_IMPLEMENT_CMD)" >&2
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
    (cd "$TARGET_REPO" && OPENAI_API_KEY="${OPENAI_API_KEY:-}" OPENAI_BASE_URL="$OPENAI_BASE_URL" \
      codex exec --full-auto --model "$CODEX_MODEL" - < "$prompt_file") >"$out_file" 2>&1
  else
    (cd "$TARGET_REPO" && env -u OPENAI_API_KEY OPENAI_BASE_URL="$OPENAI_BASE_URL" \
      codex exec --full-auto --model "$CODEX_MODEL" - < "$prompt_file") >"$out_file" 2>&1
  fi
  rc=$?
else
  echo "Error: no implementation backend available. Install Pi: ./scripts/09_setup_pi.sh" >&2
  {
    echo "### Implementation Command (exit=2)"
    echo '```'
    echo "no backend (pi/codex) available"
    echo '```'
    echo
  } >> "$IMPLEMENT_REPORT"
  set -e
  exit 2
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
        echo "  - Re-authenticate Pi: run \`pi\` then \`/login\` → ChatGPT Plus/Pro (Codex)."
        echo "  - Or for codex CLI: \`codex logout\` then \`codex login\`."
        echo "  - Or set \`CODEX_ALLOW_API_KEY=1\` and provide a properly scoped OPENAI_API_KEY."
      fi
      echo
    } >> "$IMPLEMENT_REPORT"
  fi
  if rg -qi "No models available|Use /login|/login" "$out_file" >/dev/null 2>&1; then
    {
      echo "### Pi Auth Hint"
      echo "- Pi reports missing provider auth or models."
      echo "- Run: ./scripts/09_setup_pi.sh --login-hint"
      echo "- Then: pi → /login → ChatGPT Plus/Pro (Codex)"
      echo
    } >> "$IMPLEMENT_REPORT"
  fi
fi

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi
exit 0

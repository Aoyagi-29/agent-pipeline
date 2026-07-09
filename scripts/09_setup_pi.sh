#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/09_setup_pi.sh [--check] [--login-hint]

Install Pi coding agent (user-local npm prefix) and write project defaults:
  - .pi/settings.json  (openai-codex / gpt-5.5 / xhigh)
  - ensure ~/.local/bin is on PATH guidance

Options:
  --check        Only verify install + print resolved model knobs
  --login-hint   Print Codex (ChatGPT Plus/Pro) login steps and exit
  -h, --help     Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/agent_model.sh
source "${SCRIPT_DIR}/lib/agent_model.sh"

CHECK_ONLY=0
LOGIN_HINT=0

while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --login-hint)
      LOGIN_HINT=1
      shift
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

print_login_hint() {
  cat <<'EOF'
=== Codex (ChatGPT Plus/Pro) login for Pi ===

1. Ensure ChatGPT Plus or Pro is active on your OpenAI account.
2. Start Pi interactively in a project directory:

     pi

3. Run:

     /login

4. Select: ChatGPT Plus/Pro (Codex)
5. Complete browser (or device-code) auth.
6. Verify models:

     pi --list-models openai-codex

Credentials are stored in ~/.pi/agent/auth.json and refresh automatically.

Optional (codex CLI, used as AGENT_BACKEND=codex fallback):

     npm install -g @openai/codex   # or follow OpenAI Codex CLI docs
     codex login

EOF
}

if [[ "$LOGIN_HINT" -eq 1 ]]; then
  print_login_hint
  exit 0
fi

ensure_path_hint() {
  local local_bin="$HOME/.local/bin"
  if [[ ":$PATH:" != *":${local_bin}:"* ]]; then
    export PATH="${local_bin}:$PATH"
  fi
  if ! command -v pi >/dev/null 2>&1; then
    echo "Note: add to your shell rc if needed:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

install_pi() {
  if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm not found. Install Node.js 20+ first." >&2
    exit 2
  fi
  echo "=== Installing @earendil-works/pi-coding-agent (user prefix: \$HOME/.local) ==="
  npm install -g --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent
  ensure_path_hint
  if ! command -v pi >/dev/null 2>&1; then
    echo "Error: pi not found on PATH after install. Expected: $HOME/.local/bin/pi" >&2
    exit 1
  fi
  echo "Installed: $(command -v pi) ($(pi --version 2>/dev/null || echo unknown))"
}

write_project_settings() {
  local settings_dir="$ROOT_DIR/.pi"
  local settings_path="$settings_dir/settings.json"
  mkdir -p "$settings_dir"

  agent_model_defaults
  # defaultModel in settings is the bare model id; provider is separate
  local bare_model="${AGENT_MODEL#*/}"
  if [[ "$AGENT_MODEL" != */* ]]; then
    bare_model="$AGENT_MODEL"
  fi

  cat > "$settings_path" <<EOF
{
  "defaultProvider": "${AGENT_PROVIDER}",
  "defaultModel": "${bare_model}",
  "defaultThinkingLevel": "${AGENT_THINKING}",
  "quietStartup": true,
  "enabledModels": [
    "openai-codex/gpt-5.5",
    "openai-codex/gpt-5.4",
    "openai-codex/gpt-5.3-codex",
    "openai-codex/*"
  ]
}
EOF
  echo "Wrote $settings_path"
}

write_env_example_if_missing() {
  local example="$ROOT_DIR/.env.example"
  if [[ -f "$example" ]]; then
    return 0
  fi
  cat > "$example" <<'EOF'
# agent-pipeline orchestration knobs (copy to .env and adjust)
# .env is gitignored.

# Implementation backend: pi (default) | codex
AGENT_BACKEND=pi

# Pi / Codex subscription model (provider/id). Default: GPT-5.5 via ChatGPT Codex.
AGENT_PROVIDER=openai-codex
AGENT_MODEL=openai-codex/gpt-5.5
AGENT_THINKING=xhigh
# Shorthand also works: AGENT_MODEL=openai-codex/gpt-5.5:high

# Legacy codex CLI model id (used when AGENT_BACKEND=codex)
CODEX_MODEL=gpt-5.5

# Set to 1 only if you intentionally want OPENAI_API_KEY for codex CLI
# CODEX_ALLOW_API_KEY=0

# Optional full command override for implement step
# CODEX_IMPLEMENT_CMD=
# PI_IMPLEMENT_CMD=
EOF
  echo "Wrote $example"
}

check_status() {
  ensure_path_hint
  echo "=== Pi / Codex status ==="
  if command -v pi >/dev/null 2>&1; then
    echo "pi: $(command -v pi) ($(pi --version 2>/dev/null || echo unknown))"
  else
    echo "pi: NOT FOUND"
  fi
  if command -v codex >/dev/null 2>&1; then
    echo "codex: $(command -v codex)"
  else
    echo "codex: not found (optional; Pi openai-codex provider is enough)"
  fi

  if [[ -f "$HOME/.pi/agent/auth.json" ]]; then
    auth_keys="$(python3 - "$HOME/.pi/agent/auth.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    data = json.loads(p.read_text(encoding="utf-8") or "{}")
except Exception:
    print("")
    raise SystemExit(0)
if isinstance(data, dict) and data:
    print(",".join(sorted(str(k) for k in data.keys())))
else:
    print("")
PY
)"
    if [[ -n "$auth_keys" ]]; then
      echo "pi auth: present ($HOME/.pi/agent/auth.json) keys=[${auth_keys}]"
    else
      echo "pi auth: empty — run: ./scripts/09_setup_pi.sh --login-hint"
    fi
  else
    echo "pi auth: missing — run: ./scripts/09_setup_pi.sh --login-hint"
  fi

  echo ""
  echo "=== Resolved orchestration model knobs ==="
  # Mark thinking as explicitly set if env provided, so shorthand does not override
  if [[ -n "${AGENT_THINKING+x}" && -n "${AGENT_THINKING}" ]]; then
    AGENT_THINKING_SET=1
  fi
  agent_model_print

  if command -v pi >/dev/null 2>&1; then
    echo ""
    echo "=== pi --list-models openai-codex (may be empty until /login) ==="
    set +e
    pi --list-models openai-codex 2>&1 | head -n 30
    set -e
  fi
}

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  check_status
  exit 0
fi

install_pi
write_project_settings
write_env_example_if_missing
echo ""
check_status
echo ""
print_login_hint
echo "=== Done. Next: authenticate Codex via Pi /login, then run tasks with --auto ==="

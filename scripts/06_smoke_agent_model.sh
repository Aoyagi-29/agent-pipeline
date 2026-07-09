#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/agent_model.sh
source "${SCRIPT_DIR}/lib/agent_model.sh"

fail=0
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL $name: got='$got' want='$want'" >&2
    fail=1
  else
    echo "OK   $name=$got"
  fi
}

# defaults
unset AGENT_BACKEND AGENT_PROVIDER AGENT_MODEL AGENT_THINKING CODEX_MODEL AGENT_THINKING_SET
agent_model_defaults
assert_eq "default backend" "$AGENT_BACKEND" "pi"
assert_eq "default model" "$AGENT_MODEL" "openai-codex/gpt-5.5"
assert_eq "default thinking" "$AGENT_THINKING" "xhigh"
assert_eq "default codex model" "$CODEX_MODEL" "gpt-5.5"

# shorthand thinking in AGENT_MODEL
unset AGENT_BACKEND AGENT_PROVIDER AGENT_MODEL AGENT_THINKING CODEX_MODEL AGENT_THINKING_SET
AGENT_MODEL="openai-codex/gpt-5.4:medium"
agent_model_defaults
assert_eq "shorthand model" "$AGENT_MODEL" "openai-codex/gpt-5.4"
assert_eq "shorthand thinking" "$AGENT_THINKING" "medium"
assert_eq "shorthand codex" "$CODEX_MODEL" "gpt-5.4"

# explicit AGENT_THINKING wins over shorthand
unset AGENT_BACKEND AGENT_PROVIDER AGENT_MODEL AGENT_THINKING CODEX_MODEL
AGENT_MODEL="openai-codex/gpt-5.5:high"
AGENT_THINKING="low"
AGENT_THINKING_SET=1
agent_model_defaults
assert_eq "explicit thinking wins" "$AGENT_THINKING" "low"
assert_eq "explicit model strip" "$AGENT_MODEL" "openai-codex/gpt-5.5"

# bare model gets provider prefix
unset AGENT_BACKEND AGENT_PROVIDER AGENT_MODEL AGENT_THINKING CODEX_MODEL AGENT_THINKING_SET
AGENT_MODEL="gpt-5.5"
AGENT_PROVIDER="openai-codex"
agent_model_defaults
assert_eq "bare model prefix" "$AGENT_MODEL" "openai-codex/gpt-5.5"

# orchestration override
unset AGENT_BACKEND AGENT_PROVIDER AGENT_MODEL AGENT_THINKING CODEX_MODEL AGENT_THINKING_SET
AGENT_MODEL="openai-codex/gpt-5.3-codex"
AGENT_THINKING="high"
AGENT_THINKING_SET=1
agent_model_defaults
assert_eq "override model" "$AGENT_MODEL" "openai-codex/gpt-5.3-codex"
assert_eq "override thinking" "$AGENT_THINKING" "high"
assert_eq "override codex" "$CODEX_MODEL" "gpt-5.3-codex"

if [[ "$fail" -ne 0 ]]; then
  echo "SMOKE_AGENT_MODEL_FAIL" >&2
  exit 1
fi
echo "SMOKE_AGENT_MODEL_OK"
